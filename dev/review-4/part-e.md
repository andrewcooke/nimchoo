# part E: db, web, map, calendar, ff, model, log (status: done)

## 1. one dropped connection (or a worker that cannot be started) stops the whole server

`src/nimchoo/packages/web/server.nim:31-50`

`onRequest` awaits the worker and then `req.respond`; nothing in it catches.  `asynchttpserver.acceptRequest` runs it under
`asyncCheck processClient(...)` (nim-2.2.12 `lib/pure/asynchttpserver.nim:410`), and `asyncCheck` re-raises a failed future
out of `poll`, so it leaves `waitFor loop()` and lands in `serveForever`'s `except Exception`: the server ends.  Scenario:
open a map page whose frame takes a few seconds (heat, climbs), reload or close the tab before it arrives; the worker
finishes, `respond` writes to a socket the browser has closed, asyncnet fails the send with `OSError` (EPIPE / connection
reset: Nim sends with MSG_NOSIGNAL), and the server exits.  `serveWeb` then reports it as
`cannot listen on 127.0.0.1:62466: Broken pipe (another program has the port? try --port N)` (`launch.nim:203-210`),
which sends the user looking in the wrong place.  Every later `nch map` starts a new server, so it "works", but the pages
already open die with it.  Not tested: `tests/web/` drives `handle` with a fake runner, never a real socket.

Fix: wrap the body of `onRequest` in `try ... except CatchableError` (a server loop: allowed by the rules, with a comment),
logging a `leDenied`/failure line; and let `serveForever` say "stopped: ..." rather than "cannot listen" once it has listened.
Confidence: plausible (the propagation path is confirmed in the stdlib; the EPIPE was not reproduced).

## 2. no busy timeout: two writers at once fail at once with "database is locked"

`src/nimchoo/packages/db/store.nim:203-222` (the pragmas of `openStore`); `store.nim:228` (`begin`); `ff/command.nim:120-129` (`ensureImpulses`)

No connection sets `busy_timeout` (grep: no "busy" in the sources), so SQLite's default of 0 applies: a statement that needs
the write lock while another process holds it fails at once with SQLITE_BUSY.  WAL lets readers through, but not a second
writer.  And `begin` is a deferred `BEGIN`: `calculateMissing` reads (`missing`), then writes; if another connection
committed in between, the upgrade fails with SQLITE_BUSY_SNAPSHOT, which no timeout can fix.  Scenario: `nch import DIR` in
one terminal, `nch ff` (or reloading the ff page: its worker writes impulses) in another, which fails with `nch ff: database
is locked` (the page shows it as a 500).  Same for any two commands that write (climbs being worked out, a selection saved).

Fix: `pragma busy_timeout = 5000` in `openStore`, and a `beginWrite` (`begin immediate`) for transactions that will write.
Confidence: confirmed (no timeout anywhere); the clash itself not reproduced.

## 3. a statement with more than one SQL statement in it silently runs only the first

`src/nimchoo/packages/db/statement.nim:54`

`prepareStmtAs` passes `nil` as `pzTail` to `sqlite3_prepare_v2`, so anything after the first `;` is ignored without a
word: `db.execute("delete from a where ...; delete from b where ...", ...)` deletes from `a` only, and the access check
sees only the first statement too.  Text that is only a comment or blank gives `SQLITE_OK` with a nil statement, which
then fails at `step` with an unhelpful message.  The `:name` checks (`prepareSql`) do not catch it either: a `:name` used
only in the dropped part raises "is not used by the query", which points the wrong way.  This is a class of bug the
"values by name" checks were built to stop, one level down.

Fix: take the tail and raise `StoreError("more than one statement: use execScript")` if it is not blank; refuse a nil
statement.  Confidence: confirmed (SQLite API semantics; no current caller found doing it, so latent).

## 4. `nch log` renders its own colours and prints with `g.say`: the one command left outside `g.show`

`src/nimchoo/packages/log/command.nim:59-60, 83-88`

`show` turns each `Line` into a string with `render(styled(l), paintOf(g, osOut))` and `run` prints those with `g.say`.
The rule (CLAUDE.md "output", and the last commits: "drawing: everything through g.show; sayRendered gone") is that
styled output goes through `g.show`.  It is the only user of `paintOf` outside `core/globals.nim` (grep).  The guard test
(`tests/core/test_globals.nim`) catches `stdout.say`/`echo`, not this.

Fix: return `seq[Line]` from `show` and `g.showAll(osOut, ...)`; stop exporting `paintOf` from `ui/style` so the next one
cannot.  Confidence: confirmed.

## 5. the log's line format is known in two places, and `LogLine` holds sentinels

`src/nimchoo/packages/log/lines.nim:11-24, 34-71`; `src/nimchoo/core/logfile.nim:39-41, 87-90`

`logfile.nim` writes `2026-11-02T23:10:34Z INFO  import    duplicate  text` from its `Level` enum and widths; `log/lines.nim`
reads it back with its own knowledge of it (`isLevel` lists "INFO", "WARN", "ERROR" again; a 20-character time ending in
`Z`; the event is the fourth word).  Change one and the other quietly stops recognising lines (they then show unstyled,
and `--last` says "no run").  And `LogLine` is a bag: `command` is `""` "if the line is not in the current format", and the
four positions mean something only when `event.isSome`; `Filter.count` is `0` for "all".  Parse, don't validate.

Fix: a `parseLogLine(raw): Option[ParsedLine]` in `core/logfile.nim` beside the writer (level as `Level`), used by `log`;
`count: Option[int]`.  Confidence: confirmed.

## 6. the page's Content-Security-Policy repeats the hosts of `libraries.cdn`, which the user is told to edit

`src/nimchoo/packages/web/handler.nim:68-73`; `src/nimchoo/packages/web/libraries.cdn`; `web/package.nim` doc

The policy allows scripts and styles from `https://unpkg.com` and images from `https://tile.openstreetmap.org`, written in
the code.  The same hosts are in `libraries.cdn`, which the documentation says is "kept in the cache's system/ part, where
it can be edited" (to use another version, or another CDN or tile server).  Point a library at `cdn.jsdelivr.net` or the
tiles at another server and the browser blocks it: an empty map, with the reason only in the browser's console.
One fact, two places.

Fix: build the policy from the origins of the URLs in the libraries file in use (`libraries()`), at server start.
Confidence: confirmed (in the code); the failure is by inspection.

## 7. the two page commands (`map`, `ff`) each write the web steps out by hand, and differ

`src/nimchoo/packages/map/command.nim:228-282`; `src/nimchoo/packages/ff/command.nim:228-335`

Both do: find the cache directory, make its directories, dispatch on `WebMode` (`wkStop` -> `stopWeb`, `wkServe` ->
`serveWeb`, `wkWorker`/`wkFile` -> write files atomically and print their paths), and turn `TemplateError`/`IOError`
into a failure that names the templates.  The copies have drifted:
* no cache directory: map says "no place for the cache: set NCH_CACHE or HOME", ff "no cache directory is known (set
  NCH_CACHE)" (twice, two wordings); `cache` says "set NCH_CACHE, XDG_CACHE_HOME or HOME" and `activities` a fourth.
  `cachePath` reads all three variables, so map's and ff's hints are incomplete.  One message belongs in `cache`.
* map calls `makeCacheDirs` before anything; ff only on the file/worker path.
* the template failure text is written twice with different wording; map's `fmt`, ff's `&` (ff/command.nim has no
  `strformat` at all: every message is pieced together with `&`, against the printing rule).
* map checks the selection before serving; ff checks FTHR/heart rate only after opening its own session.

Fix: a `webCommand`-style helper in `web` (cache dir, dirs, mode dispatch, file writing and its failures) that a page
command gives a `makeFiles` proc; one `noCacheDir` message in `cache`.  Confidence: confirmed.

## 8. an empty selection is a failure on the map and a normal line on the calendar

`src/nimchoo/packages/map/command.nim:134-135`; `src/nimchoo/packages/calendar/command.nim:110-112`

Same subject, same condition, same words: `nch map` writes "the selection of activities is empty (...)" to stderr via
`failure` and exits 1; `nch calendar` writes it to stdout as a plain line and exits 0.  A script cannot tell an empty
calendar from a full one by its status, and the theme styles them differently.  (The `ui` doc should say which is meant;
the rest of the "consistency" pass made such cases one.)

Fix: decide once (an empty selection is "nothing to show", exit 0 with a warning, or a failure) and give `subject` a
helper that both call.  Confidence: confirmed.

## 9. choosing a subject by name is written twice (map, calendar), with its checks and its table

`src/nimchoo/packages/map/command.nim:85-120` and `map/params.nim:31-33`; `src/nimchoo/packages/calendar/command.nim:83-101` and `calendar/params.nim:22-24`

`isWord` (identical), the positional `SUBJECT` parser and "expected at most one SUBJECT", the lookup "no subject 'x' (the
subjects are a, b)", the default from `defaultSubject`, and `registryLines` (a table of subjects and their frames plus
"the subject is X when none is given") are copied between the two views.  `plan.md` expects more views over the same
registry; each will copy it again.  (Also: calendar's frame doc says "a subject has at most one calendar frame" but
`choose` silently takes `frames[0]`: nothing checks it, where the registry generator could.)

Fix: `subject/subjects.nim` gets `isSubjectName`, `findSubject(all, Option[string]): Parsed[Subject]` and the positional
option; the views keep only their frame lookup.  Confidence: confirmed.

## 10. `nch models` has no `--delete`, though CLAUDE.md names it among the plural commands that do

`src/nimchoo/packages/model/command.nim:20-26`, `model/params.nim:150-160`; CLAUDE.md "the shape of the commands"

CLAUDE.md: plural commands (`activities`, `climbs`, `users`, `models`, `landmarks`) take `--add NAME`, `--edit NAME ...`,
`--delete NAME`.  `models` takes only `--add` ("a model is never changed once it is made", which explains no `--edit`,
not no `--delete`).  A model added with a typo stays for ever (only `nch db --delete` removes it); `ff_model` already
cascades to `impulse`, so deleting is safe.  Also `calc.problem(m): string` returns `""` for "fine" and `finish` checks
`why.len > 0`: validation with a sentinel, where the rules ask for parsing into `Parsed`/`Option`.

Fix: `--delete NAME -f` (not `default`), with the shared confirm; `problem` -> `Option[string]` or a `Parsed[Model]`.
Or, if no delete is wanted, say so in CLAUDE.md.  Confidence: confirmed.

## 11. `--port` "not given" is the default port: `--file --port 62466` passes, `--file --port 8000` is refused

`src/nimchoo/packages/web/webopts.nim:113`

`let serving = w.start or w.newToken or w.port != defaultPort`: the value doubles as "was it given".  So `nch map --file
--port 62466` is accepted and the port ignored, while any other port is a usage error; and `--stop --port 0` (any free
port) is accepted and then asks port 0.  A sentinel, where the rules ask for `Option`.

Fix: `port: Option[int]` in `WebArgs`; refuse 0 with `--stop`.  Confidence: confirmed.

## 12. sentinels in the web and db plumbing

`src/nimchoo/packages/web/token.nim:17-53`; `src/nimchoo/packages/db/access.nim:31-37,128-131`; `db/command.nim:43`; `ff/page.nim:15-17`

* `loadToken` returns `tuple[token, problem: string]` (problem `""` = fine, token `""` = none) and `randomToken` returns
  `""` on failure; callers test `problem.len > 0` (launch.nim:126,173,217).  Should raise an `NchError` or return a
  variant.
* `access.leave()` returns `""` for "allowed" and `caller == ""` means "not checked"; `packageOfFile` returns `""` for
  `core` and the tests (so everything outside a package bypasses the authorizer: by design, but invisible in the types).
* `freeSpace` returns `""` for "none or unknown".
* `ff/page.renderPage` returns `none` when the data's name is not a cache CSV name: that name is made by `ff` itself, so it
  is a bug (a `doAssert`), not an absence; the caller turns it into "cannot make a page for ..." with exit 1.

Fix: `Option`/variants as the rules say; `doAssert` in `renderPage`.  Confidence: confirmed.

## 13. `nch ff --file` works the impulses out and reads them twice, in two transactions

`src/nimchoo/packages/ff/command.nim:131-171, 324-327`

`makeCsv` runs `ensureImpulses` (a write transaction) and `hourlyImpulses`; then `latestStats` runs both again and
recomputes the responses.  Besides the double work (the hourly query over every impulse of the user, the response over the
whole history), the CSV and the "top N%" line are read from two states of the database: an import between them makes the
printed latest values disagree with the file just written.  `map` makes all its frames in one read transaction for this
reason (`map/command.nim:146`).

Fix: one `ensureImpulses`, one `hourlyImpulses`, pass the rows to both.  Confidence: confirmed.

## 14. smaller drift and stale text

* `map/command.nim:43`, `ff/command.nim:41`: the help says the page is "served on localhost ... (Ctrl-C stops it)".  Since
  the one shared server (launch.nim), a later `nch map`/`nch ff` returns at once and Ctrl-C does nothing; `--stop` is the
  way.  Stale.
* `calendar/command.nim:148-154`: the width is `if isatty(stdout): terminalWidth() else: 0` with `0` meaning "no limit",
  its own test of the terminal (it ignores `TERM=dumb`, which `ui/live.helpWidth`/`canLive` respect).  A `ui/live` helper
  and `Option[int]` would make it one rule.
* `map/page.nim:118`, `map/command.nim:194-199`: `pageHtml` takes `seq[tuple[frame, shown]]`, but the only caller passes
  `f.shown` for every frame ("at first; the browser remembers"): the tuple is left from when the address chose the
  frames.  Pass the frames.
* `db/command.nim:117-121`, `ff/command.nim` and `model/command.nim:89`: messages still built with `&`/`$` in files
  touched by the consistency pass (`ff` has a dozen); the printing rule wants `fmt` for new and converted text.

Confidence: confirmed.

## what is good

* `web/request.nim` and `handler.nim` are pure and small, with the route made from each command's own option spec
  (`pageOf`): what the server passes on cannot differ from what the command parses.  The token, Host and `/status`/`/stop`
  header rules are careful and tested (and fuzzed).
* The access model is applied at prepare time with the package worked out at compile time; `Sql` carries its
  contributors; the `:name` checks are thorough.  Clean, cheap and hard to get round by accident.
* The views really are live: map frames are made per request in one read transaction, ff's served page omits
  `--before` so "today" moves; file names come from the options.
* `{.push raises: [].}` everywhere it should be; every command follows the same `parseArgs` -> `Parsed` -> `usageError` /
  `failure` shape, and usage is built from the option descriptions in all seven packages.
