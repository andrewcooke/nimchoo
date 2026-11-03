# TODO

## Conventions

### Error handling

Four kinds of things go wrong, and each has one mechanism:

1. **Bugs are Defects.** A violated precondition or a "can't happen" case uses
   `doAssert`/`raiseAssert` (or the built-in bounds checks).  Never caught, never turned
   into a warning, so tests fail loudly.  A table lookup that must succeed uses
   `must`/`mustMut` (`src/nimchoo/lookup.nim`), which asserts instead of raising
   `KeyError`.
2. **Input we cannot use is an exception**: a corrupt FIT file, a bad profile, a file that
   is not an xlsx.  All are subtypes of `NchError` (`src/nimchoo/errors.nim`:
   `FitError` with `offset`, `ProfileError` with `sheet` and `row`, `XlsxError`), raised
   with the `raiseFit` / `raiseProfile` / `raiseXlsx` helpers, and listed in
   `{.raises.}`.
3. **Ordinary absence is an `Option`**: a bad (invalid) field value, an unknown base type,
   a missing field.  No sentinel values.
4. **Oddities we can recover from are warnings**, collected on the tokenizer/decoder
   (`warnings`; the reader merges them in file order), never logged or printed by library
   code.  Each is a `Warning` with a `WarningKind` (`src/nimchoo/warnings.nim`), so callers
   and tests act on the kind, not the text.

Rules that follow:
* `try` only at boundaries: the CLI, and where a third-party or `std` call is wrapped into
  one of our errors (`xlsx.nim` wraps `parsexml` and `zippy`).  Never
  `except CatchableError`/`KeyError`/`Exception`, and never turn a caught bug into a warning.
* Every module starts with `{.push raises: [].}`, so a proc can raise nothing unless it
  says so: procs that can raise declare exactly what (`{.raises: [FitError].}`; file
  readers also `IOError`), and the compiler checks it.  `std` calls that can raise are
  wrapped into our errors or declared.
* **CLI contract** (`src/nimchoo/cli/common.nim`): a command's `run(args): int` is
  `{.raises: [].}`; it returns 0 for success, 1 when the work failed (unusable input,
  I/O error) after one line on stderr and no trace, and 2 for a usage error.  Anything
  else that escapes is a bug and is allowed to crash with a trace.

### Coding style

What the code does today; new code should look like the code around it.

**Language and dependencies**
* Nim 2.2, standard library first.  One third-party dependency (`zippy`, for inflate);
  no C libraries.  Compiler-checked is better than convention (`raises`, `case` over enums).

**Layout**
* 2-space indentation, no tabs, an informal 80-column limit (wrap long expressions; a
  few lines run to 100), one blank line between top-level declarations.
* Every module opens with a `##` comment saying what it is for, and `##` documents each
  exported thing (and non-obvious private ones).  Comments say *why* (provenance,
  a choochoo behaviour we kept or dropped, a spec quirk), not what the next line does.

**Naming**
* `camelCase` for procs, variables, fields and constants (`fitEpoch`, `exitOk`);
  `PascalCase` for types; lower-case one-word module names (`basetype.nim`).
* Enum members carry a short tag of their type: `wkDataSize` (`WarningKind`), `vkInt`
  (`ValueKind`), `fkPlain` (`FieldKind`), `tkMapping` (`TypeKind`), `btUint8`
  (`BaseType`), `evRecord` (`EventKind`), `tokData` (`TokenKind`).
* Export with `*` only what other modules need.  `export` is used only to re-export a
  module's own public types (`errors`, `profile/model`).

**Imports** (one block at the top, after the module comment)
* `std/` first, as one bracketed list (`import std/[options, strutils]`), then project
  modules alphabetically: relative inside `src/` (`./`, `../`), `nimchoo/...` in tests.
* `{.push raises: [].}` comes straight after the imports (see Error handling).

**Functions and data**
* `func` for pure functions (43 of the 108 top-level routines today); `proc` for anything with effects,
  and where `std` forces it (`times.utc`).  Small and single-purpose; results are returned
  rather than written to out-parameters (the exceptions are `var` collectors such as the
  warnings list, and iterators).
* Data is plain value objects; kinds are `case` (variant) objects.  Objects refer to each
  other by name or index, never by `ref`.  No module-level mutable state, no globals.
  `let` by default, `var` only where something is mutated.
* Absence is an `Option`; lookups that must succeed use `must`/`mustMut`.  `cast` appears
  only for bit-level reinterpretation (`bytes`, `basetype`) and inside `lookup.nim`.
  Templates only where a proc cannot do it (three so far).

**Tests**
* `std/unittest`: one `suite` per area, `test` names are plain sentences, `check` and
  `expect`.  One `tests/test_<module>.nim` per area, imported from `tests/all.nim`;
  `nimble test` runs them from the project root (paths to the choochoo data are relative).
* Inputs are hand-built where the case is small (`tests/fitbuilder.nim`,
  `tests/xlsxbuilder.nim`) and real files where behaviour has to match the SDK
  (`../choochoo/data/test`).  Error paths are tested too (`expect`, exit codes), and a bug fix comes with a test.
* `nimble csvreport` compares our CSV with the SDK's for the files that have one.

**Working practice**
* Discuss before implementing (see `AGENTS.md`).  One logical step per commit, tests
  passing in each; the message has an imperative summary line and a short paragraph on why,
  and ends with the `Co-Authored-By` line.
* Refactors must not change behaviour: capture the CLI output for all test files before
  and diff it after.

### Output conventions

* **Units:** a table column carries its unit in its header (`km`, not `5.5 km` on every row);
  where a number stands in a sentence the unit is attached with no space, as in intervals
  (`842.2km`, `4h41m`, `within 20km`).  Input never takes a unit for distance (decimal km), and
  `m` always means minutes.
* **Intervals of time** (`ui/interval.nim`, one rule for every listing, now and in future):
  units `d h m s`, no leading unit that is zero, the first unit unpadded and later ones two
  digits: `45s`, `22m05s`, `4h41m`, `2d03h07m`.  Seconds are shown under an hour; from an hour
  the interval is rounded to the minute; from a day it is days, hours and minutes.  Rounding
  carries (`59.6 s` is `1m00s`).  Anything that prints a duration uses `interval`.
* **Words and looks** for what happened are in `ui/vocabulary.nim` (see Task 4); colour is
  used only where it means something, and never the status colours (green imported/saved, red
  failed/deleted, yellow advisory) for anything else.
* **Tests are fast enough to run often:** `nimble test` builds optimised with the run-time
  checks still on (`-d:release --checks:on`: about 6 s to run, against about 29 s for a debug
  build; the first build takes ~35 s, later ones a few seconds); `nimble testdebug` is the
  slow debug build, for tracking down a failure.  The slowest tests are those that decode
  many real FIT files.

### Code layout

```
src/nch.nim                  the one command: global options, then a thin dispatcher
src/nimchoo/
  errors.nim  lookup.nim  warnings.nim   NchError and subtypes; must/mustMut; typed warnings
  modules.nim                 the modules that have database tables: allFragments (in order)
  xlsx.nim                    xlsx reader (zip + xml, from memory); Row, cell
  cli/common.nim              exit codes, Globals, say/usageError/failure, openStore(g)
  fit/                        MODULE: the FIT format and `nch fit`
    bytes.nim                 getUint/getInt/getBits/canRead, readBytes
    basetype.nim              BaseType, bad-value markers, decode of base-type values
    crc.nim  time.nim         the FIT CRC; FIT time, expandTimestamp16
    header.nim                FileHeader, readHeader, problems
    tokens.nim                the tokenizer (definitions, data, timestamps; no profile)
    records.nim               FieldValue, Record, Event; field, valueName
    decode.nim                the Decoder: plans, scaling, composite/dynamic, developer fields
    reader.nim                Reader: tokenizer + decoder as events/records iterators
    csvout.nim                SDK-format CSV lines
    command.nim               `nch fit` (no tables)
  profile/                    LIBRARY: the FIT profile
    model.nim  load.nim       the profile as plain data; loading it from Profile.xlsx
    default.nim               the embedded Profile.xlsx
  db/                         INFRASTRUCTURE: the SQLite database, knows no module
    fragment.nim              Fragment, fragment() (embeds the .sql file next to the caller)
    store.nim                 Store, openStore (load SpatiaLite, apply missing fragments, find the user)
    statement.nim             re-runnable prepared statements, execScript
    001-schema.sql            the user table (everything hangs off it) and SpatiaLite's metadata
  ui/                         INFRASTRUCTURE: terminal output, knows no module
    style.nim                 styled spans, visible width, truncation, ANSI rendering
    live.nim                  a throttled, in-place live region on stderr
    logfile.nim               the log file: path, line format, rotation
  importer/                   MODULE: `nch import`, and the activity tables it owns
    extract.nim               readActivities: sessions, segments, coordinates (no database)
    route.nim                 the route as WKT: a part for each segment
    importer.nim              importFile: hash, skip repeats, write a file in one transaction
    batch.nim                 importPaths: find files, skip the unchanged, import, emit events
    seen.nim  failure.nim     the seen_file table (load/match/batch-write); kinds of failure
    events.nim                ImportEvent, Summary, Sink, fanOut
    sinks.nim  display.nim    plain lines (and the Report used by tests); the live display
    logsink.nim               the log lines for events
    command.nim               `nch import`
    ddl.nim                   its fragments
    001-schema.sql            file, activity, coords, segment, route, seen_file
  destroy/command.nim         MODULE: `nch destroy`; newer than importer, so it counts its activities
  selection/                  MODULE: `nch list`, and the selection table
    criteria.nim              the command line -> criteria (times, positions); criteria -> SQL (pure)
    command.nim  ddl.nim      `nch list`; its fragments
    selection.nim             selectionKey: a short hash of the selection's content
    001-schema.sql            selection
tests/                        mirrors src/nimchoo/: tests/<dir>/test_<file>.nim tests <dir>/<file>.nim
                              (a few cover neighbouring files); all.nim imports them all;
                              support/ is shared (fitbuilder, xlsxbuilder, csvcompare);
                              csvreport.nim compares our CSV with the SDK's
```

**A module is a directory with everything for its command(s):** the command (`command.nim`, thin:
arguments, choosing sinks, exit status), the logic, and, if it has tables, `ddl.nim` and its
`.sql` file(s).  We do not separate commands from the library code they sit on: the module
that first brings in a concept owns it (`importer/` owns activities, segments and
coordinates) and later commands use its library files.  The one rule, kept by a test
(`tests/test_structure.nim`): **only `nch.nim` imports a `command.nim`.**  A module's
directory is named for the concept it owns, and its commands are what it offers: `importer/`
(`nch import`; `import` is a Nim keyword, and neither `import_` nor backticks work for a
module name), `selection/` (`nch list`, which makes and shows the selection), `fit/`
(`nch fit`).  Where a command only works on its own, the directory is just its name
(`heatmap/`, `destroy/`, `log/`).

To add tables to a module: write `NNN-name.sql` in its directory (DDL only), list it in its
`ddl.nim` with `fragment("NNN-name.sql")`, and add the module's `ddl` to `modules.nim` after the
modules whose tables it refers to.  Aim for one file per module while nothing is released; once
a database exists, never edit a fragment that has been applied: add a new one.  A test fails if
a `.sql` file exists that is not listed.  The database records the fragments it has had (table
`fragment`, by name `module/file`, with the SHA-256 of its SQL), so opening it applies only the
missing ones, each in a transaction; a recorded fragment this build lacks means the database is
from a newer nch, and one whose checksum differs (a fragment edited since: allowed while nothing
is released) means it was made by another version: both are refused with "run `nch destroy -f`
and import again".  A fragment may carry a *seed*, code that fills its tables with data the
program carries (the places), run once in the same transaction.  Data (e.g. the default user) is inserted from Nim, not from SQL.

Dependencies run one way: `errors/lookup/warnings` -> `fit/bytes` -> `fit/{basetype,crc,
time}` -> `fit/header` -> `fit/tokens`; `profile/model` -> `profile/load` (+ `xlsx`);
`fit/records` -> `fit/decode` -> `fit/reader` -> `fit/csvout` -> `fit/command`; `db` ->
`importer`; `ui` is used by `importer` and `cli`; `nch.nim` on top.  Nothing below
`fit/records` imports from `profile/`, and `db` and `ui` import no module.

**Modules are roughly incremental: a newer module may use the library files of older ones**
(`destroy/` counts `importer`'s activities), never a `command.nim`.  A later module whose data
should be mentioned by `destroy` adds a line to its counts (its rows are deleted either way).

**`nch destroy [-f]`** (`destroy/command.nim`): without `--user`, deletes the database file (and
any `-journal`/`-wal`/`-shm`), so every user goes; with `--user NAME`, deletes that user's row
and everything under it, then `vacuum`s.  Without `-f` it changes nothing, says what it would
delete (`74 activities for all users`, `74 activities and user bob`) and exits 1.  With `-f`,
on a terminal, a red line counts down 5 seconds (`deleting ... in 5 s ... (Ctrl-C to cancel)`);
not on a terminal (scripts, tests) it deletes at once.  Everything a module stores hangs off
`user(id)` with **`on delete cascade`**, so a module needs no cleanup code; a new table must
declare its foreign keys the same way.  The count is "all data" if the database cannot be opened
(e.g. from an older layout), which is exactly when one wants to destroy it.  The default user is
recreated, empty, the next time the database is opened; any other user is gone (there is no
command to create users yet).  A missing database is not an error.  The log is left alone.

**Renamed in the structure revision** (Task 2 notes below use the old names): `activity/` ->
`importer/`, `commands/` -> `cli/` (only `common.nim` stays; `fit.nim` -> `fit/command.nim`),
the three SQL fragments `001-tables`, `002-segment`, `003-seen` squashed into
`importer/001-schema.sql` (and the first-release `user_version` upgrade removed: a database
made by an earlier build must be deleted and re-imported), the tests moved to mirror `src/`.

The Task 1 notes below use the module names of the time (`binary.nim` is now
`fit/{bytes,basetype,crc,time,header}`, `profile.nim` is `profile/{model,load}`, and so on).

## Task 3: `nch heatmap` (GeoJSON) and a local web viewer (planned)

Goal (AGENTS.md, "two layers"): something graphical that uses the selection (`nch list --save`).  Layer 1 writes files
in a format third parties understand (GeoJSON); layer 2 is a minimal local web server that
reads the URL after `localhost` as an `nch` command and shows the result.  Plotting stays
outside nch: Leaflet in the browser draws, nch only makes data and pages.

### The flow

1. `nch heatmap` writes `heatmap--...geojson` to the cache directory and prints its path.
   (Usable on its own: upload the file to geojson.io, QGIS, Kepler.gl ...)
2. `nch heatmap --web` runs the worker once itself (so errors, e.g. an empty selection,
   appear in the terminal), starts the server and opens the browser at a `localhost` URL, then
   serves until Ctrl-C.
3. The server turns each request into `nch heatmap --worker ...` (a subprocess).
4. `--worker` makes sure the output files exist (a cache hit does no work) and prints their
   paths on stdout, nothing else: the **first line is the page** (HTML), any others are data
   files the server may serve by name.  Errors go to stderr with a non-zero status.
5. The server returns the page; the page asks for the GeoJSON; the server serves it.

Why not `file://`: a page opened from disk cannot fetch another file (browser rule), and
tile.openstreetmap.org returns an "Access blocked" tile for requests without a Referer, which
is what `file://` pages send (checked with curl: 403 placeholder without, real tile with a
`http://localhost:...` Referer).  Serving over `http://localhost` avoids both.

### Decisions

* **The URL is the command line.**  Path = command, query = long options:
  `/heatmap?sel=ab12cd&style=lines&token=...` is `nch heatmap --sel ab12cd --style lines`.
  Meant to allow clickable links between pages later (an activity page, "show this on the
  map"); `--worker` is a convention for every command that makes files.
* **File names are the command line.**  `<command>` plus the options sorted by name, as
  `--name-value` pieces, in the cache directory: `heatmap--sel-ab12cd--style-lines.geojson`
  (and `.html`).  Values are limited to `[A-Za-z0-9._,-]`; anything else is refused, not
  escaped.  Cache directory: `$NCH_CACHE`, else `$XDG_CACHE_HOME/nch`, else `~/.cache/nch`.
  Same options, same files: nothing is recomputed.
* **Bookmarks, not shareable links:** a `localhost` link means nothing to anyone else, so what
  is shared is the files (the `.geojson`; perhaps later a `--standalone` HTML with the data
  inlined, which would need a basemap that works without a Referer).  A bookmark of
  `/heatmap?sel=...` is pinned and works while the server runs (the cookie survives restarts
  because the token is kept).  `/heatmap` with no `sel` means "my current selection": the
  server redirects it to the pinned form, so a reload never changes the data but the bookmark
  always shows the current selection.
* **A URL means one thing: the selection is pinned.**  `sel` = the first 12 hex digits of the
  SHA-256 of the sorted activity ids of the current selection (and the user).  Plain `nch
  heatmap` uses the current selection (and puts its `sel` in the file name).  With `--sel H`:
  if the files for H exist they are returned; else if the current selection hashes to H they
  are made; else an error: "the selection has changed since this page was opened; run `nch
  heatmap --web` again".  So an old browser tab never shows different data after `nch list --save`.
* **Styles.**  First `lines`: a `FeatureCollection`, one feature per selected activity, its
  route as `AsGeoJSON(simplified geom, 5)` (about 1 m), properties `id`, `start` (ISO, UTC),
  `sport`, `distance_m`.  Simplified with SpatiaLite (`SimplifyPreserveTopology`; `--tolerance
  M`, default about 5 m) because 3,000 rides of 2,000 points would otherwise be tens of MB.
  Later `cells`: the route points binned to a grid (`--cell M`), the number of *distinct
  activities* per cell as polygons with a `count`; small however many rides there are.
* **The page** (generated by the worker, tiny): Leaflet 1.9.4 from a CDN (unpkg or jsDelivr)
  with the `integrity` hash taken from Leaflet's download page when it is written; OSM tiles
  with attribution; fetches the GeoJSON from the server; `fitBounds`; lines drawn with weight
  2 and opacity about 0.25 on a canvas renderer, so overlaps glow.  Not embedded in nch: the
  tiles need the network anyway.
* **The server** (`serve/`, a library; commands call it for `--web`; stdlib only, no new
  dependency): `GET /<command>?...` runs the worker and returns its first file as
  `text/html`; `GET /files/<name>` returns a file from the cache directory (a plain name, no
  separators, only `.html .geojson .js .css`; `application/geo+json` for GeoJSON); anything
  else is 404.  Listens on **port 62466** (the keypad digits of "mchoo"; above Linux's
  ephemeral range 32768-60999, in no services list); `--port N` to change it; if it is busy,
  say so and stop (no silent fallback: bookmarks rely on the port).  Prints the URL, opens it
  with `xdg-open` (`--no-open` to skip; the URL is always printed).  Logs requests to the nch
  log.
* **Security** (the server runs commands named in URLs, and any web page open in the browser
  can send requests to `localhost`; binding to 127.0.0.1 only keeps other machines out):
  - bind `127.0.0.1` only;
  - a random token (128 bits from `/dev/urandom`), **kept in `<cache dir>/server-token` (mode
    0600), created on first use** (`--new-token` replaces it).  The URL that `--web` opens
    carries it once; the server then sets a cookie (`HttpOnly`, `SameSite=Strict`, so a request
    started by another site does not carry it) and redirects to the URL without the token.
    Every other request needs the cookie (or the token); without either it is 403 with a page
    that says to open the URL `nch heatmap --web` prints;
  - the `Host` header must be `127.0.0.1:PORT` or `localhost:PORT` (against DNS rebinding);
  - an **allowlist** of commands the server will run (`heatmap` only: read-only and safe to
    repeat; never `import`, `list --save`, `destroy`) and, for each, of option names and value
    characters;
  - the worker is started with an argument list, never through a shell.

### Refinements (sketched with the user, 2026-11-03)

* **Checked on the author's machine:** `xdg-open` and Firefox are installed; unpkg is reachable;
  Nim's `asynchttpserver` is in the standard library (no new dependency).  Leaflet 1.9.4
  integrity hashes, computed from the downloaded files: `leaflet.js`
  `sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=`, `leaflet.css`
  `sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=`.
* **Pieces:** `heatmap/page.nim` (pure: the page text; the data file name is a validated cache
  file name, so it is safe in HTML and JS), `--worker` (writes the geojson if missing and the
  page always, prints the page path then the data path), `serve/request.nim` (pure: request
  checks), `serve/token.nim`, `serve/server.nim`, then `--web`, `--no-open`, `--port`,
  `--new-token` in `heatmap`.
* **Redirect for a URL with no `sel`:** the server reads the key from the file name the worker
  returns, so `cache.nim` gets the inverse of `fileStem` (`parseStem`).
* **Hardening:** a Content-Security-Policy (scripts from the server and unpkg, images from the
  server and the OSM tile server, `connect-src 'self'`), `X-Content-Type-Options: nosniff`;
  request lines go to the nch log.
* **Integration test:** start `nch heatmap --web --no-open --port 0` (the OS picks a free port,
  printed) on a fixture database and use plain HTTP: 200 with the token and a cookie set, 403
  without, 403 for a wrong Host, 404 for other commands and for `..`, the GeoJSON content type,
  a clean stop.  It needs a built `./nch`, so the `test` task builds it first.

### Steps (each a commit; tests pass after each)

1. [x] `cache.nim` (cache directory, file names from options, the character rule,
   `isCacheFileName` for what the server may serve) and `selection/selection.nim`
   (`selectionKey`: 12 hex digits of the SHA-256 of the selected activities' file hashes and
   sessions, so it is the same in any database and does not depend on ids).  Tests: names,
   refusals, the key is stable, order-independent, and follows the selection.
2. [x] `heatmap/` with style `lines`: `params.nim` (command line; the defaults are written
   out because the options name the file), `lines.nim` (GeoJSON text, pure), `command.nim`
   (`nch heatmap [--sel KEY] [--style lines] [--tolerance M]`; prints the file's path; writes
   to a new name and renames, so nobody sees half a file).  Features carry `id`, `start`
   (UTC ISO), `sport`, `distance_m`.  Activities without a route are left out with a note on
   stderr.  Checked on the test rides: 6 routes, 154 KB unsimplified, 46 KB at 5 m, 25 KB at
   50 m.  An existing file is returned without any work, whatever else has changed; `--sel`
   for a selection that is gone and not current is an error.
3. [x] `heatmap/page.nim` (pure: Leaflet 1.9.4 from unpkg with the integrity hashes, OSM tiles
   with attribution, `fetch('/files/<name>')`, lines weight 2 / opacity 0.25 on a canvas, a
   click popup with start, sport and distance, a caption with the number of routes, `fitBounds`;
   the data name must be a cache `.geojson` name, the title is escaped) and `--worker` (makes
   the geojson if missing and the page always, prints the page path then the data path and
   nothing else on stdout; a note about routes left out is on stderr).  The page cannot be
   looked at from disk (it fetches from the server): that is step 4.
4. [x] `serve/` (a library: `request.nim` pure, `token.nim`, `handler.nim`, `server.nim`).
   - `request.nim`: `parseTarget` (a plain absolute path: no scheme/host, no whitespace or
     control characters or backslashes, at most 2,000 characters, percent-decoded),
     `hostAllowed` (Host must be exactly `127.0.0.1:PORT` or `localhost:PORT`), `cookieValue`,
     `sameToken` (compares every character; never matches an empty token), `route` (`/files/NAME`
     for names `cache.isCacheFileName` accepts, or `/COMMAND?options` for the commands in
     `commandRules` -- only `heatmap`, with only `sel`, `style=lines` and a numeric `tolerance`,
     each once -- everything else is nothing).
   - `token.nim`: 32 hex digits from /dev/urandom in `<cache>/server-token`, created empty with
     mode 0600 and then filled, kept across runs, replaced if it is not a token or on `renew`.
   - `handler.nim`: `handle(cfg, port, Incoming) -> Reply`, no sockets: GET only (405), Host (403),
     bad address (400); `?token=T` right -> 302 to the same address without it and
     `Set-Cookie: nch=T; HttpOnly; SameSite=Strict; Path=/`, wrong -> 403; otherwise the cookie must
     match (403 saying to open the address `nch heatmap --web` printed).  A command runs
     `nch [--db ..] COMMAND --worker ARGS` through an injected runner; the first path it prints
     must be an `.html` of the cache directory (else 500), and with no `sel` in the address the
     reply is a 302 to the pinned address, read back from the file name (`cache.parseStem`).  A
     failing worker is a 500 whose text is its message, escaped.  Every reply has a
     Content-Security-Policy (scripts from the server, inline and unpkg; images from the server and
     the OSM tiles; `connect-src 'self'`; no framing), `nosniff` and `no-cache`.  Each request is
     logged (events `served` / `denied`), never with the token.  `'unsafe-inline'` for scripts is
     there because the page's script is inline (it is generated by us from a validated name);
     other origins are still blocked.
   - `server.nim`: `serveForever(cfg, port, ready)` on 127.0.0.1 only with the standard library's
     `asynchttpserver` (port 0 = any free one, told to `ready`); `runWorker(exe)` starts the worker
     with an argument list, no shell, and a 2-minute limit.  A non-GET with no Content-Length is
     refused by the library itself (411) before our code.
   - Checked with the real server and `curl`: 403 without a token or with a wrong Host; 302 and
     the cookie with the token; the pinned redirect; the page (200); the GeoJSON with its type
     (20 features); 404 for `..`, `%2e%2e`, `/destroy`, `?db=` and the token file.
5. [x] `nch heatmap --web [--port N] [--no-open] [--new-token]` (`heatmap/web.nim`; `prepare` in
   `command.nim` is now shared by plain, `--worker` and `--web`): makes the files first (so an
   empty selection, no routes or a stale `--sel` is reported in the terminal and nothing starts),
   loads the token, starts the server on 127.0.0.1 (default port 62466; `--port 0` for any free
   one), prints the address, which pins what was made and carries the token once
   (`http://127.0.0.1:62466/heatmap?sel=KEY&style=lines&tolerance=5&token=...`) and
   `(Ctrl-C to stop)`, and opens it with `xdg-open` in the background (`--no-open` to print only;
   if it cannot open, a note says so).  The address line is flushed (stdout to a pipe is
   block-buffered, and a program reading it would wait for ever).  Ctrl-C ends the process with
   status 130 (`ui/interrupt.nim`; the dispatcher's `exit` log line is not written then).  A port
   that is taken stops it with `cannot listen on 127.0.0.1:PORT ... (is another ... running?)`.
   `--no-open`, `--new-token` and `--port` need `--web`; `--web` and `--worker` exclude each
   other.  Tests (`tests/heatmap/test_web.nim`) start the real `./nch` on a fixture database on a
   free port and speak HTTP: the cookie flow and pinned page and data, 403 for no/wrong token or
   Host, 404 for everything else, the token file (mode 0600, kept, renewed), an old cookie dying
   after `--new-token`, the empty selection, a taken port, Ctrl-C = 130.  `nimble test` builds
   `./nch` first (as an optimised build); without it those tests are skipped.  Not tried by the
   author's own eyes yet: the page in a browser.
6. [x] Docs here; tried by the author on real data in Firefox (2026-11-03): "very good".

### Open questions

* Later: `cells` style; named places (`select --near home`); a generic `nch serve`; links from
  one page to another (the cookie means links need no token); `--standalone` export.

## Task 7: training impulse, fitness and fatigue (planned: findings and the first step, `nch user`)

Goal: the choochoo "FF model" (fitness and fatigue from heart rate), reusing its algorithm with a
much smaller database representation.  Read from `../choochoo/py/ch2` (`data/impulse.py`,
`data/heart_rate.py`, `data/response.py`, `data/lib.py`, `pipeline/calculate/{impulse,response}.py`,
`config/{impulse,profile}.py`).

### The algorithm, as the Python code does it

1. **Heart-rate zone, from FTHR (not max HR).**  FTHR is the *functional threshold* heart rate, the
   highest rate sustainable for about an hour.  The zone edges are percentages of it, the British
   Cycling values `BC_ZONES = (68, 83, 94, 105, 121)` (upper limits of zones 1..5).  The zone is a
   continuous number: at or below 68% of FTHR it is 1; in each band from 68% to 121% it runs linearly
   across a unit (68-83% is 2.0 to 3.0, 83-94% is 3.0 to 4.0, 94-105% is 4.0 to 5.0, 105-121% is 5.0
   to 6.0); above 121% it is 6.  FTHR is a **history** (a value from a date on) and per activity group
   (the author's default is 154 bpm).
2. **Impulse, per 10 seconds.**  Heart rate is interpolated (linearly in time) onto a 10-second grid;
   a gap longer than `max_secs` (60) gives no impulse.  `impulse = ((zone - zero) / (one - zero)) ^ gamma`,
   clipped at 0, with the defaults `gamma = 2`, `zero = 1`, `one = 6`: zone 1 is 0, zone 6 is 1 per
   10 s, zone 3.5 is 0.25.  (The code's `clip(..., inplace=True)` on a column probably does nothing;
   with `zero = 1` the value is never negative, so it does not matter.)  If HR is missing for part of
   an activity that has positions, the impulse is scaled up by `100 / coverage`.
3. **Response (fitness and fatigue).**  The impulses are summed into hourly bins, a zero is put
   in front, and an exponential decay is applied: `y[t] = y[t-1] * exp(-1/tau) + x[t]` with `tau` in
   hours, the first value replaced by `start * alpha` (`alpha = 1 - exp(-1/tau)`), the result
   multiplied by `scale`.  Fitness: 42 days, start 1, scale 1; fatigue: 7 days, start 1, scale 5.
   It is calculated every hour up to now (zeros after the last activity), so it is a smooth curve.
   Per activity it also keeps the change in each (and the time "earned" or needed to recover).
4. **Python's representation:** a database row per 10 seconds for the zone and for the impulse, and a
   row per hour for each response: millions of rows, with derived values stored as if they were data.

### The nch representation (decided with the author, 2026-11-03)

* **Heart rate** is a channel of its own, stored once: `heartrate(activity_id, t, bpm)`, `WITHOUT
  ROWID`, from the `record` messages (a `heartrate/` module, imported alongside the positions).
  Nothing per 10 s is stored.  An activity with no heart rate has no impulse.
* **The variables of the whole calculation are one named set, a row of one table**:
  `ff_model(id, name unique, gamma, zero, one, max_secs, zone1..zone5, fitness_days, fatigue_days)`:
  the impulse variables (gamma, zero, one, max_secs, and the zone edges, five percentages of FTHR,
  defaulting to the British Cycling 68, 83, 94, 105, 121) and the decay period in days of the two
  curves that are made from the impulses (42 for fitness, 7 for fatigue).  (The Python's `start` and
  `scale` are not in the model: see the decisions below.)
  `name` is for display.  A `default` row with these values is put in when the table is made (a
  seed, as for the places); more are added by a command, so that variants can be compared.  A model
  is never edited once it exists (a new one is added), because the impulses made with it would no
  longer match it; deleting one deletes its impulses.  (A model that differs only in the decay
  periods repeats the impulse rows: a handful an activity, so cheap.)
* **Impulse is stored per hour per activity per model**: `impulse(activity_id, model_id, hour_t,
  value)`, primary key `(activity_id, model_id, hour_t)`, `model_id` references `ff_model`.  A
  handful of rows an activity.  Zone and the 10-second grid exist only inside the calculation.
* **FTHR is the user's, not the model's, but every impulse depends on it.**  It is one value per user,
  and changing it is a very rare event that means starting again: `nch user --fthr` on a user who
  already has impulses deletes all of that user's impulses (every model), says so, and they are
  calculated again from scratch.  So nothing records which FTHR an impulse used.  A user with no
  FTHR gets no impulses (and is told so).
* **Fitness and fatigue are not stored:** a pure function of the hourly impulses of one model and the
  curve variables in the same model row, computed when asked (87,000 hours is ten years: trivial),
  with `--model NAME` choosing the model.

### Step 3: the model and the impulse -- built

`model/` (`001-schema.sql`, `ddl.nim`, `calc.nim` pure, `models.nim`, `impulses.nim`, `step.nim`,
`params.nim` pure, `command.nim`).

* **Tables:** `ff_model` (as decided: gamma, zero, one, max_secs, zone1..zone5, fitness_days,
  fatigue_days; checks that the values make sense; models belong to no user; `default` is a seed
  whose values are part of the fragment's checksum) and `impulse(activity_id, model_id, hour_t,
  value)` (WITHOUT ROWID, cascading from both).  A trigger on `user_profile.fthr` deletes the user's
  impulses when the FTHR changes, so the rule holds whatever changes it.
* **`calc.nim`:** `zoneOf`, `level`, `powIntegral` (the exact integral of `max(u,0)^g` along a
  straight line, with the clipping), `hourlyImpulse` (readings to hourly values, split at hour
  boundaries, nothing across a gap over `max_secs`, hours covered with no impulse stored as 0).
  `bucketSeconds` (3600) is a constant.  On the 2018-08-27 ride it gives 72.44 against 72.53 for a
  replica of the Python's 10-second grid (0.1%).
* **When impulses are made (changed 2026-11-03 after import proved slower; first built eagerly):**
  only when wanted, by `nch ff`, and only for the model it uses.  Import stores the heart rate and
  nothing else; `nch user --fthr` and `nch model --add` work nothing out.  `calculateMissing(db, user,
  model)` finds the activities with heart rate and no impulses for that model and fills them in (in one
  transaction), so the first `nch ff` after an import is the slow one.  A changed (or cleared) FTHR
  deletes all of that user's impulses by the trigger, and `nch user` says so.
* **`nch model`** lists the models; `nch model --add NAME [--gamma --zero --one --max-secs --zones
  A,B,C,D,E --fitness-days --fatigue-days]` adds one (variables not given are the default's).
  There is no delete yet.  `nch user --fthr` says if impulses were deleted.
* **Help:** `nch help` no longer repeats "(see `nch X --help`)" for each command: one line at the end.
* The schema changed: `nch destroy -f` and a re-import (the same one as for steps 1-2).

### Step 4: fitness and fatigue -- built

`ff/` (`curve.nim` pure, `params.nim` pure, `command.nim`).

* **`curve.response`:** `y[h] = y[h-1] * exp(-1 hour / tau) + x[h]` from the first hour with an impulse to
  the end of the last day asked for; starts from 0; `dayEnds` picks the last hour of each day of a timezone.
  Tested against the sum of what each impulse has left.
* **`nch ff [--model NAME] [--from DAY] [--to DAY] [--hourly] [--fitness-scale S] [--fatigue-scale S]`**
  prints CSV (`time,fitness,fatigue`) of the current user to standard output, for plotting elsewhere:
  a row a day (the value at the end of the day), or an hour (labelled by the end of the hour, with its
  offset: `2018-08-27T14:00:00-03:00`).  **Days are those of the computer's timezone** (`--utc` for UTC);
  `--from`/`--to` are days of that zone.  The impulses stay in UTC hours; a day's value is that of the
  last whole hour ending before its midnight (in a half-hour zone such as India's, the hour ending half
  an hour early: under half an hour of decay).
  `--to` defaults to today, so the curves fade out after the last activity.  The scales default to 1
  (the original used 1 and 5).  It works out the impulses that are lacking first (see above); an error if the user has no FTHR, or no activity with heart rate, saying what to do.
* **Output goes to the cache** (changed 2026-11-03): `nch ff` writes a CSV in the cache directory and
  prints its path; `--stdout` prints the CSV instead and makes no file.  The name is
  `ff--fatscale-1.0--fitscale-1.0--key-KEY--model-default--res-day--to-2018-09-05--tz-utc.csv` (plus
  `--from-DAY`).  **KEY** (`impulses.inputKey`) is 12 hex digits of a hash of everything the curves
  depend on: the FTHR, the model's values, and the file hash and session of each activity with heart
  rate (not database ids), like the heat map's selection key.  So a file that exists is current:
  `nch ff` then does nothing, not even the impulse calculation.  `--to` is always written out (today
  if not given), so a default run makes a new file each day; the zone is the UTC offset at the end of
  the last day (`tz-east-10800`).  Old files are not deleted (a cache clean-up command is wanted for
  these and the heat map's).  `csv` is now an allowed cache extension.
* **`nch ff --web` / `--worker`** (as for the heat map): `--worker` makes the CSV and a page and prints the
  page's path, then the CSV's; `--web [--port N] [--no-open] [--new-token]` serves them on 127.0.0.1 and
  opens `/ff?...` (the address carries the options that were given, so a reload follows the data).  The
  page (`ff/page.nim`, pure) loads **d3 7.9.0 and Observable Plot 0.6.17 from unpkg under their integrity
  hashes** (the CSP already allowed unpkg), fetches the CSV from `/files/` and draws fitness and fatigue as
  two lines with a pointer tip; days are drawn in UTC (their labels are already local dates), hours in the
  browser's zone.  **Whether Plot is fast enough for hourly data over years is not known**: try
  `nch ff --hourly --web`; uPlot is the fallback.  `--hourly` is chosen when the command is run (there is
  no switch in the page).
* **The server code was generalised for this:** `serve/launch.nim` (`serveWeb(g, command, options, cacheDir,
  query)`, moved out of `heatmap/web.nim`), and `serve/request.nim` has a `CommandRule` per command
  (options that take a value, flags that are `name=1`, and the option that is "pinned" in the address:
  `sel` for the heat map, none for ff).  `defaultPort` moved to `serve/request.nim`.  csv files are served
  as `text/csv`.
* **One idea, one name (consistency pass, 2026-11-03):** the heat map's `sel` and ff's `key` were the same
  thing (a hash of everything the file was made from, in its name), so now both are **`key`**, in file
  names, in the option (`nch heatmap --key K`, `nch ff --key K`: "the file with this key; if it is not
  there and the key is not the current one, the data have changed: say so"), and in the server's rule
  for both (the request lacking `key` is redirected to the same address with the worker's key, plus the
  options it had; the defaults are no longer written into the address).  Older notes in this file that
  say `--sel` / `sel-` mean this.  The printed address is `http://localhost:PORT/...` (the server still
  binds 127.0.0.1 only, and accepts either name in the Host header).  Shared code: `serve/webopts.nim`
  (`--worker --web --port --no-open --new-token`: parsing, their combinations and their help text, used
  by both commands), `serve/pages.nim` (`fill`, `htmlEscape`, `writeAtomic`), `serve/launch.nim`.
  Existing heat map cache files (`heatmap--sel-...`) are simply made again under the new names.
* **Latest values (2026-11-03):** at a terminal (not with `--stdout`, `--worker` or `--web`, and only for the
  current data) `nch ff` prints the path, then the latest value of each curve and the share of the earlier
  days (the day-end values from the first day with an impulse) on which it was higher:
  `fitness  71.49  (higher on 4% of the 200 earlier days)`; fitness green, fatigue red (`ff/stats.nim` and
  `curve.standingAt`, pure).  "Latest" is the last whole hour for today (`as of 15:00 on DAY`), or the end
  of the last day if `--to` is earlier.  The value is scaled by the scale options; the share is not.  This
  needs the impulses, so a plain run calculates them if lacking even when the file is already there (the
  file is not made again).
* **The chart:** fitness green (`#2f9e44`) and fatigue red (`#e03131`), as in the terminal; **drag to zoom** (the
  chart is drawn again with the dragged span as its time axis, from the points inside it), **double-click to
  zoom out**.  Plot has no zoom of its own; this is a small brush written in the page (`ff/page.nim`).  The
  zoom is not kept in the address.  Not done: panning, wheel zoom.
* **A compiler trap met on the way:** `var p = ""` followed by `p = cacheFile(...).get` (`.get` of a temporary
  Option, assigned on to a var) left a dangling string in this Nim: the path became garbage (once it was
  another string's contents).  Keep the Option in a `let` and take `.get` from that.
* Not done: a form column (fitness minus fatigue); a switch between days and hours in the page.
* Not compared with the Python's output directly (no pandas here); the recurrence is the same as its
  `ewm` form (see `data/lib.py`), and the impulses it uses agree with the Python's grid to 0.1%.

### Step 1: `nch user` (per-user information) -- built

What the algorithm needs per user is the **FTHR** (agreed: not max heart rate; nothing in the
current Python code uses max or resting HR).  **One value per user, no history; one name** (the
existing `user.name`, the key for `--user`; no separate display name).

* **A `user/` module** (newer than `importer`, which it reads for counts) owning
  `user_profile(user_id primary key references user(id) on delete cascade, fthr integer)`, a row made
  when a value is first set; `user` itself stays in `db/`.
* **Command line** (options are enough):

      nch user                              the users: name, FTHR (blank if not set), activities
      nch user --create NAME [--fthr N]     make a user (never implicit: a typo must not make one)
      nch [--user NAME] user --fthr 154     set FTHR (of the current user)
      nch [--user NAME] user --clear-fthr
      nch [--user NAME] user --rename NEW

  Names: 1-32 characters, letters, digits, `_`, `.`, `-` (not first): they appear in `--user` and
  in comma-separated lists (`--users a,b`).  The `default` user cannot be renamed (it is made again
  whenever a database is opened).  FTHR is a whole number of bpm, 80 to 230.  `nch destroy --user`
  already removes a user.  Changes are logged (event `saved`).

  **As built** (`user/`: `001-schema.sql`, `ddl.nim`, `params.nim` pure, `command.nim`): exactly the
  above.  `nch user` lists `user fthr activities` (activities counted per user, with commas;
  FTHR `-` if not set); `--create NAME [--fthr N]` makes a user; `--fthr N`, `--clear-fthr`,
  `--rename NEW` act on the user given by `--user` (the default user if none) and may be
  combined; a bare `NAME` is refused and the message says to use `--create NAME` or `--user NAME`.
  A user is refused if the name is taken; `default` cannot be renamed; `nch --user nobody user ...`
  says there is no such user and makes nothing.  Names and FTHR are checked before the database is
  opened.  The FTHR change that must clear impulses is not there yet because there are no
  impulses: it goes in with step 3.

**Default user, changed after step 1:** `user.is_default` (a partial unique index: at most one is 1)
marks the user commands work on without `--user`.  An empty database gets one called `default`,
flagged; if the flagged user is deleted and others remain, the oldest becomes the default.  So the
default can be renamed.  `nch [--user NAME] user --default` moves the flag (`--create NAME --default`
makes a user and does so in one go); `nch user` has a `default` column ("yes").  `openStore` takes
`""` for "the default".  The schema changed, so an existing database needs `nch destroy -f` and a
re-import.

**Decisions on the impulse calculation (2026-11-03, discussed, not yet built):**

* The unit of time for bucketing is **one hour, a named constant in the code**: not a model column and
  not changeable by the user.  Changing it later means recalculating every impulse.  A bucket's lump
  is placed at its **midpoint** when the decay is applied (the error otherwise is up to about
  bucket/tau of that hour's impulse: under 0.6% for the 7 day fatigue constant).
* **No 10 s grid.**  The Python resamples the zone onto 10 s with pandas only for a regular index;
  its real job (irregular recording intervals must not weight the result) is done by weighting each
  reading by the time it covers.  We integrate directly: for each pair of consecutive readings no more
  than `max_secs` apart the zone is a straight line in time, and the impulse function is integrated
  exactly over the interval and added to the hour's bucket.  The **unit stays "per 10 seconds"**
  (the integral over seconds, divided by 10) because the fitness and fatigue scales were tuned to it.
* **A gap longer than `max_secs` gives nothing** (the Python's `limit` fills the first 60 s of every
  long gap; we deliberately do not).
* Check against the Python on a test file by comparing daily totals; the tolerance starts at **1%**
  and may widen to **10%** if the difference is explained by where the Python's grid points fall
  (these models are not precise, and when an impulse "kicks in" can matter more than that).

* **The curves have no `start` and no `scale`** (decided 2026-11-03).  The Python's `start` replaces
  the first hour's value (1 for both) and fades as `exp(-t/tau)`: it is an initial condition of no
  lasting effect, so the curves start from 0.  Its `scale` (1 for fitness, 5 for fatigue) is a
  multiplier of the finished curve only, to make the two comparable in size: it belongs to the
  display (an option of the command that shows them).  So the comparison with the Python has to
  ignore the first weeks (fatigue) or months (fitness), or run the Python from 0.
* **No coverage correction** (the Python scales an activity's impulse by `100 / coverage` where some
  records lack heart rate).  It amounts to filling missing values with averages, like a longer
  `max_secs`; where there is no heart rate there is no impulse.
* **The decay** is `y[h] = y[h-1] * exp(-1 hour / tau) + x[h]` over the hourly impulses `x`, as in the
  Python (a lump counts as at the end of its hour; placing it at the midpoint changes a value by
  `exp(0.5 h / tau)`, 0.03% for the 7 day curve, so it is only a comment in the code).

### Open

* Per sport (activity group) FTHR and models: later, if wanted.

### Later steps (each a commit)

2. Heart rate as a channel -- built.  `heartrate/` (`001-schema.sql`, `ddl.nim`, `step.nim`) owns
   `heartrate(activity_id, t, bpm)` (WITHOUT ROWID, cascades from `activity`), one reading per second
   at most, zero or invalid readings dropped.  The importer knows nothing of it: a module registers an
   `ImportStep` (`db/channel.nim`: the record fields it wants, and a function that writes its rows for
   an activity inside the import's transaction).  `extract.readActivities` collects the wanted fields in
   the same pass (sorted, last of a second kept, assigned to sessions as coordinates are), the importer
   calls each step per activity and counts the rows (`ImportResult.extras`, shown as "2,099 heart-rate
   readings" in the import line and the log).  Steps are listed in `modules.allImportSteps` and reach
   `import` through `Globals.importSteps`.  The schema changed, so an existing database needs
   `nch destroy -f` and a re-import.
3. (built, see above) The model and the impulse: `ff_model` (seeded with `default`), the zone and impulse functions
   (pure; tested on numbers worked by hand and against the Python code on a test file),
   `impulse(activity_id, model_id, hour_t, value)`, calculated for activities that have heart rate
   and whose user has an FTHR, and cleared when that FTHR changes; `nch model add/list`.
4. (built, see above) Fitness and fatigue: the decay (pure; checked against the Python output for the same impulses) and
   a command that prints or exports them for an external plotting service, as with the heat map.

## Task 6: places, and the start of an activity as a point (in progress)

Why: `list -v` should say where an activity started ("a ride in another continent"), `--near`
should mean "starts near" (how rides are named), and named places want a home in the database.

### Design (agreed 2026-11-03)

* **A `place` table** (`places/` module): name, country (ISO two-letter), population, `source`
  (`geonames` | `user`, for places the user names later), a `POINT` geometry (SRID 4326) with a
  spatial index.  Global: no user, so `destroy --user` leaves it.
* **Loaded when the database is made**, from a list the program carries: GeoNames cities5000
  (towns and cities of 5,000 people or more: 69,999 places; 1.2 MB gzipped in the program; about
  0.5 s to load, about 10 MB in each database).  Done by a **seed** on the fragment
  (`Fragment.seed`, run right after the fragment's SQL in the same transaction, once), because
  data is inserted from Nim, not from SQL files; the seed makes the spatial index *after* the
  rows (5x faster).  The 15,000+ list (34,197 places) would be half the size, 1,000+ (171,770)
  2.5x: `tools/makecities.nim` makes the list from any of them.
* **Tests** are built with `-d:nchSmallPlaces`, which carries a 34-place list
  (`cities-test.tsv`) instead, so a test database costs nothing; one test checks the real list.
* **Nearest place:** a bounding-box search on the spatial index, widened (1, 5, 20, 90, 360
  degrees) until something is found, then once more in a box that certainly holds everything as
  near (degrees of longitude are short away from the equator), and wrapped across the date line.
* **The start of an activity** becomes a `POINT` on `activity` (with its own spatial index),
  written at import; `--near` means "starts within the radius"; `latest` / `previous` use that
  start as the centre.  (Needs `nch destroy -f` and a new import.)
* **`list -v`** gets a `place` column before `file`: `Santiago, CL`; more than 10 km away
  `Coyhaique, CL (180km)`; `-` if the activity has no positions.  Columns are padded by
  characters, not bytes (accented names).
* Credit: `NOTICE` (GeoNames is CC BY 4.0).

### Steps (each a commit; tests pass after each)

1. [x] The seed hook (`Fragment.seed`, `withSeed`), the `places/` module (`001-schema.sql`,
   `data.nim` reading the carried list, `seed.nim` loading it and `nearestPlace`), `cities.tsv.gz`
   made by `tools/makecities.nim`, `NOTICE`, `-d:nchSmallPlaces` in the test builds.  A new
   database takes 0.55 s and is 11 MB.  Tests found a real bug on the way: the search box did
   not wrap round the date line, so a point just east of it was matched to Honolulu, not
   Auckland.
2. [x] `activity.start`, a `POINT` with a spatial index (`importer/001-schema.sql`), set at import
   from the first position (NULL without positions).  `--near LAT,LON --radius KM` is now
   "starts within": the index finds the starts in a box (two boxes if the circle crosses the date
   line: `boxes`), then the distance on the ground decides; `latest` / `previous` use where that
   activity started as the centre (`startOf`), and the line says `(the start of the latest
   activity)`.  The route and its index remain, for the map; "passes through" could come back as
   `--through`.
3. [x] **The nearest place is stored with the activity**: `activity.place_id` (references `place`,
   `on delete set null`, indexed), set at import with the start (`importer.nim` asks
   `places/seed.nim`'s `nearestPlace`), so `list -v` needs no lookup: a `place` column before
   `file` from a join, `Santiago, CL`, or `Coyhaique, CL (180km)` if more than 10 km away
   (`placeText`), `-` if unknown.  The places fragment now comes before the importer's in
   `modules.nim` (the newer module may use the older).  Table columns are padded by characters
   (`padLeft` / `padRight`; "Valparaiso" is 10 wide, not 11).  Import of the whole test tree
   (79 files, 74 activities) still takes about 2 s.  Needs a re-import.
   **Seen on real data (the test files), not decided:** the nearest place is often a district
   of the city (`Nunoa` for rides in Santiago, `Whitechapel` for London, `Wersten` for
   Duesseldorf), because GeoNames lists those as separate populated places.  Options: prefer
   the most populous place within some radius (say 15 km) over the nearest; or the 15,000+
   list (it still has Nunoa); or leave it (it is the nearest place).
   The nearest place being a district was seen on real data and accepted ("district is fine").
   **Seen by the author, fixed in 3b:** an old database used to fail with "no such column".
3b. [x] **A database that is out of date is recognised.**  The `fragment` table records the SHA-256 of
   each fragment's SQL (`Fragment.checksum`); opening a database whose recorded checksum differs
   from this build's, or whose `fragment` table has no checksums at all (made before this),
   fails with "the database was made by a different (an older) version of nch ...; it cannot be
   updated: run `nch destroy -f` and import again" instead of SQLite's "no such column".  (Why it
   was needed: while unreleased, a fragment is edited in place, so its *name* does not change.  A
   seed's data is not part of the checksum; a changed list of places needs a new fragment.)
   `nch destroy` (whole database) needs no schema, so it still works on such a database.
3c. [x] **District entries are left out of the list** (decided after the author's rides in Providencia
   were labelled Nunoa): `tools/makecities.nim` drops GeoNames feature code PPLX ("section of a
   populated place": suburbs and districts), 5,309 of 69,999, leaving 64,690 places (1.13 MB).
   On the author's 1,108 starts: nearest place = Santiago for 1,086 (was Nunoa for 1,084).  The
   biggest-place-within-15-km rule was tried and not needed.  Providencia, Las Condes, Vitacura,
   La Reina and Macul are in GeoNames only as administrative areas (ADM3, no population), so no
   list of populated places has them; the answer for those is the user's own named places
   (`nch place add`, item D: not needed yet).  The tool also writes `cities.version` (the SHA-256
   of the list), which is part of the places fragment's checksum (`withSeed(seed, version)`), so
   a database made with another list is refused like any out-of-date one.  The `test` task
   builds `nch-test` (short list, like the tests) for the subprocess tests, so `./nch` is never
   replaced by a test build.
3d. [x] **`list -v` says where each ride started in three columns, `position`, `place`, `file`**:
   `position` is the start as `-33.4362,-70.6090` (lat,lon, four decimals = about 10 m, as Google
   Maps takes it), or a dim `no GPS` if the file has no positions; `place` is the nearest place
   from the list (a name always exists when there is a start), with the distance if over 10 km
   (`Coyhaique, CL (180km)`), blank if there is no start.  Seen on the author's data:
   four rides (e.g. `2018-12-16-lyn.fit`: 195 records, a session and a lap, 856 m in 3 min) have no
   position field anywhere in the file, so nothing can be shown for them and a place is not
   guessed from neighbouring rides.
4. Docs.

## Task 5: `nch list` replaces `nch select` (step 1 built)

Why: `select` and a listing would take the same options, and you want to see what you pick.
One command: the criteria say *which* activities, `--save` says "and keep them", `--show` shows
what was kept.  What is printed is what is saved.

### Design

* **`nch list [CRITERIA] [--save]`**, **`nch list --show`**.  Criteria (as `select` has now):
  `--users A B C`, `--from`, `--to`, `--near LAT,LON|latest`, `--radius KM` (alone = `--near
  latest`), `--newest N`, `--oldest N`, `--latest`; new: `--sport A B` and `--sub-sport A B`
  (several values mean "any of them"; an unknown name is an error that lists the sports in the
  database).  No criteria: all of the current user's activities (so `select --all` goes).
  `--show`: the stored selection; an error with any criterion.  `--save`: replaces the
  selection with what is listed (also an empty list: then it says so).  `-n` is not needed:
  `--newest/--oldest N` limit both the list and what is saved.  `nch select` is removed.
* **Module `selection/`** (renamed from `select/`; the table is already `selection`): `list`
  is its command, in `command.nim`.  A module is named for the concept it owns (as `importer/`
  owns activities), its commands are what it offers (the layout rule in "Code layout" now says so).
  `selection/001-schema.sql` is the same table, so the fragment is now named
  `selection/001-schema.sql` (a database with the old name is refused: `nch destroy -f` and
  re-import, no data of value is at stake yet).  `heatmap` uses `selection/selection.nim` (the key).
* **One SQL builder:** the "which activities" `where` text is built once from the criteria;
  `list` selects rows with it, `--save` inserts the same rows (`insert ... select`).
* **Sport and sub-sport** are columns of `activity` (from the FIT session): `sport` is
  cycling, running, swimming, walking, `fitness_equipment`, `transition` (the gaps in a
  triathlon), `generic`; `sub_sport` is a refinement (`road`, `trail`, `open_water`,
  `virtual_activity` ...) and is often `generic` or missing (about half of the author's rides),
  so `--sub-sport road` misses some road rides: the help says so.  **A multisport file is
  several activities** (a triathlon is swim, transition, bike, transition, run; one test file
  has 19 sessions of a swim-run), so `--sport cycling` is the bike leg alone.  Nothing is
  excluded by default; `transition` rows are shown as they are.
* **The table** (pure function in `selection/table.nim`, tested without a database): one row
  per activity, oldest first: `date` and `start` (your time zone, as `--from`/`--to` are
  read), `sport` (`/sub_sport` added only if neither empty nor `generic`), `distance` (km, one
  decimal), `active` (timer time = active/moving time, h:mm, as Strava's moving time; a total
  elapsed time, pauses included, is stored too and could be an `elapsed` column, e.g. with
  `--elapsed`, later); a `user` column only if more than one user is listed;
  `--file` adds the file name (to see which rows belong to one multisport file).  No `id`
  column: nothing takes an activity id yet (add it with the first command that does).  Last line:
  the count, the total distance and time, and a count by sport when there is more than one
  (`13 running, 2 swimming`).  After `--save`: `saved 42 activities as the selection`.  No
  colour for now.
* **Log:** `list` is logged like other commands (`run`, `exit`); `--save` adds a new event
  `saved` (`42 activities`), in `ui/vocabulary.nim` with its look (green).

### Steps (each a commit; tests pass after each)

1. [x] `select/` is `selection/` (tests mirror it), `select` is `list` with `--save` and `--show`
   (`--show` takes no criteria and not `--save`), without `--all`.  One SQL builder:
   `matchSql(userIds, criteria, centre, columns)` is the query for the matching activities, used
   to count them and by `saveSql` (`insert ... select id from (<that query>)`).  The output is
   still a one-line summary (`matched 3 of 74 activities, ...` / `saved 3 of 74 activities as
   the selection, ...`); heatmap's messages, `commandNames`, usage and tests are changed.  Found
   on the way: `parseArgs` ignored its `zone` parameter (always the local zone): fixed.
   `nch log select` is no longer accepted (`select` is not a command), though old log lines
   still say `select`.
2. [x] `--sport A B` and `--sub-sport A B` (several values and repeats mean "any of them"; lower
   cased, so `Cycling` works; `none` means not recorded, i.e. NULL).  Checked against the
   activities of the users being searched: an unknown name is an error that lists what they have
   with counts (`they have: running 32, cycling 21, swimming 13, ...`), exit 1, nothing changed.
   Applied before `--newest/--oldest` (the newest *cycling* activity).  A sub-sport is checked
   against all of the users' sub-sports, not those of the sport given, so `--sport cycling
   --sub-sport open_water` is accepted and finds nothing.  The values are quoted in the SQL.
3. [x] The table (`selection/table.nim`, pure; the time zone is a parameter): header, a row for
   each activity oldest first (`date`, `start`, `sport`, `distance`, `active`; `user` after
   `start` only if several users are listed; `--file`, a display option that `--show` accepts,
   adds `file` last), then `42 of 310 activities, 2,013.4 km, 98:12 h (13 running, 2 swimming)`
   (the `of 310` is what the users have, left out for `--show`; the count by sport only when
   there is more than one, most first).  `--save` adds `saved 42 activities as the selection`
   and logs the new event `saved`.  `--show` of an empty selection says `selection: empty`.
   Then, as asked: `-n N` is `--newest N`; `-v`/`--verbose` (replacing `--file`, which was
   never in the help) adds the path the file was imported from (where it was last seen, else
   its name); `active` is shown by the interval rule above; looks: transition rows dim all
   through, `-` (not recorded) dim, a distance under 50 m or an active time under 30 s
   (a stray recording: `0.0 km`) yellow, the `saved N activities as the selection` line green;
   not done, by choice: colours per sport, a dim header.
4. [x] `--distance RANGE` and `--active RANGE` (`selection/ranges.nim`, pure): `a-b`, `a-`,
   `-b`, both ends inclusive, either end may be left out (not both), exactly one hyphen (so
   `1-2-3` and a bare `5` are errors with an example); a backwards range says so.  A distance
   is always km, a decimal number with no unit (`5`, `2.5`, `0.5`), digits and a dot only (not
   `1e3`); `m` is never a distance, it is minutes (so `500m` and `5km` are errors: write `0.5`);
   an active
   time is written as it is printed (`45s`, `22m`, `1h30m`, `2d`; units d h m s, largest first,
   each once, a unit on every number: `90` is an error).  Not recorded (NULL) is never in a
   range.  Applied before `--newest/--oldest`.  A value that starts with `-` is read as a
   value by every single-valued option (`--distance -5` is "up to 5 km"; tested).  Named
   `--active` after the column; dates stay `--from`/`--to` because ISO dates have hyphens.
   Idea, not built: `--longest N` (by rank, like `--newest`).
4b. [x] **`centre~tolerance` and `latest`.**  `--distance 42~2` is 40-44 km, `--active 2h~15m`
   is 1h45m-2h15m, the tolerance is an amount or a percentage of the centre (`~10%`); `~`
   never appears in the hyphen ranges, so there is no clash and no `+5` / `-5` ambiguity.  The
   centre may be the word **`latest`**, also for `--sport latest`, `--sub-sport latest` and
   `--near latest` (and `--radius` alone).  **Rule: `latest` is the newest activity among
   those that meet the criteria that do not mention `latest`** (users, dates, plain ranges,
   named sports; not `--newest/--oldest`, which pick afterwards), so the order of options does
   not matter and all uses of `latest` share one reference.  `--sport cycling --distance
   latest~10%` is cycling rides near the length of your latest cycling ride; `--sport latest
   --distance latest~10% --active latest~15%` is rides like your latest.  This changed `--near
   latest`, which used to take the latest of all the users' activities.  A line `latest: ...`
   says which activity it found.  Errors, with nothing changed: no activity meets the other
   criteria; the latest has no distance / active time / positions recorded.  Not built: a
   reference other than the latest (an id, a date, ...) beyond `previous` (see 4c).
4c. [x] **`previous`**: the other reference.  `previous` is the one activity in the selection
   stored before this command (so you pick any ride with `nch list ... --save`, then
   `--sport previous --distance previous~10% --active previous~15%`, `--near previous`).  An
   error unless exactly one activity is selected ("it has N"), nothing changed.  It is read
   before `--save` replaces the selection, so one command can find rides like it and keep them;
   running that command again then fails, as the selection has many.  It is explicit, not
   filtered by the other criteria; `previous` is resolved first, then `latest` is found among
   the criteria that do not mention `latest`, previous ones included, so they mix
   (`--sport previous --distance latest~20%`).  `latest` and `previous` cannot both be given to
   `--sport` or `--sub-sport`.  A line `previous: ...` says which one.  Internally a
   criterion carries a `Reference` (`refLatest` / `refPrevious`) instead of a flag each; the
   single resolution step is `resolve` in `selection/command.nim`.  (The name could be read as
   "the ride before the latest"; the help says what it means.)
5. Docs; try it on the test data (mixed sports) and on a real library.

## Task 4: one vocabulary for the log and the screen, and `nch log` (planned)

Problem: the log has a free-text line with a "topic" and no convention (only `import` puts a
keyword first), colours on screen are chosen in the display code, and the hint after an import
is a `grep` over a log that accumulates.

### Design

* **A line is `time LEVEL command event text`.**  `command` is what the user ran (`import`,
  `destroy`, later `heatmap`, `serve`); `nch` is only for the dispatcher's own trouble (e.g.
  the log could not be opened).  The run and exit lines carry the command they belong to
  (`import  run  /home/andrew/fit/bike`, `import  exit  1`), so `nch log import` shows a whole
  run.  (The old name for `command` was "topic"; for `event`, "keyword".)
* **`event` is a value of an enum** in `ui/vocabulary.nim` (infrastructure, knows no command):
  `start run exit imported duplicate unchanged failed advisory note done deleted ...`, each with
  its text form and its one **look** (colour, bold, dim): imported green, duplicate and
  unchanged grey (dim), failed red (bold), advisory yellow, note/start/done/run/exit plain or
  dim.  The look is chosen by an exhaustive `case`, so an event without a colour does not
  compile, and the log call takes the enum, so an unknown event cannot be logged.  A new event
  is one new enum value in that file.
* **The screen uses the same table:** the counts line (`advisories 85`, `duplicates 1`,
  `failed 2`, `imported 1,112`) takes its colours from the event of the same name.  Plain
  (piped) output stays uncoloured.
* **Level** (INFO / WARN / ERROR) stays, separate from the event; nothing user-facing mentions it.
* **`nch log [COMMAND...] [EVENT...] [--last] [-n N]`** (`log/`, newer than the others): COMMANDs
  and EVENTs are told apart because the two sets never overlap; AND between the kinds, OR
  within one; an unknown name is an error that lists the known ones.  `--last`: only the latest
  run of the given command(s), from its `run` line to the end.  `-n N`: only the last N
  matching lines.  Output is the log lines with the event word coloured (no colour when piped
  or `NO_COLOR`); lines from older versions of the log are shown plain.  The file itself stays
  plain text: an escape next to the word would stop `grep -w` matching.
* **The hint becomes** `more: nch log import advisory duplicate --last`, naming only what
  happened.

* **Later: log level filtering in `nch log`** (e.g. `--level warn`: that level and above).  The
  level is already in every line (INFO / WARN / ERROR) and separate from the event, so this is a
  filter on the parsed line; note that failed lines are ERROR and advisories WARN, so it
  overlaps with the event filter and may matter mostly for new events.
* **Later: light and dark backgrounds.**  Only the basic ANSI colours plus bold/dim are used, which
  terminals remap through their theme, but `dim` can all but vanish on a light background and
  yellow is poor on white.  `look(event)` would take a theme (`light` / `dark`), from
  `NCH_THEME`, else guessed from `COLORFGBG` (set by some terminals), default dark; not by
  querying the terminal's background colour (fragile).  Every look is in `ui/vocabulary.nim`,
  and the live display and `nch log` both use it.

### Steps (each a commit; tests pass after each)

1. [x] `ui/vocabulary.nim` (`LogEvent`: start run exit imported duplicate unchanged failed
   advisory note done deleted; `look` is an exhaustive `case`; `parseEvent`; `span(text,
   event)`), the log API `log(level, command, event, text)`, the new line format (command padded
   to 8 columns, event to 9), every caller (`nch.nim` run/exit now carry the command, destroy,
   the import log sink), the display counts taking their looks from the events.  Tests: words
   unique and parseable, the important looks, the counts' looks equal the events', line format.
2. [x] `log/`: `lines.nim` (pure: take a line apart, filter by command and event, `--last` = from
   the latest `run` line of the given commands, `-n`, styled spans) and `command.nim` (`nch log
   [COMMAND...] [EVENT...] [--last] [-n N]`; names are told apart by what they are, an unknown
   one lists the known; colour only on a terminal, not with `NO_COLOR`; `nch log` itself is not
   logged, or `--last` would always find itself).  `commandNames` in `cli/common.nim` is the
   one list of commands.  Lines from before the format change are shown but match no filter,
   and `--last` says why it found no run.
3. [x] The hint is `more: nch log import <what happened> --last` (the grep recipe, the path
   quoting and the `~` helper are gone); the import usage text points at `nch log --help`.

## Task 2: database (steps 1-3 built: `nch import` with segments, fast re-imports, display and log; more is added piecemeal)

### Engine: leaning to SQLite + SpatiaLite

* User preference: no Docker (dislikes it more than they like Postgres); data volumes are
  small (personal activities), so Postgres's scale is not needed.  Postgres+PostGIS would
  mean a container (rootless Podman + compose/Quadlet) and `libpq`; SQLite means one file.
* choochoo's spatial use (py/ch2, geoalchemy2): routes stored as `Geography` lines with
  M / ZM values (distance, azimuth, elevation, time); queries cast to geometry and
  transform to a local UTM zone (`common/geo.py:utm_srid`) for sectors/climbs, route
  clustering, "nearby" and map display.  ~38 distinct `ST_*` functions.
* Probe of `mod_spatialite` 5.1.0 (GEOS 3.12, PROJ 9.5) on this machine
  (`/usr/lib64/mod_spatialite.so`; loads from Python `sqlite3`):
  * 27 functions exist under the same name (transform, length, distance, intersects,
    intersection, buffer, covers, hausdorff, concavehull, offsetcurve, locatebetween,
    x/y/z/m, start/end/pointn, ...).
  * 9 under another name: SetSRID, MakePoint, MakePointM, MakeLine (aggregate), CastToXY
    (force2d), CastToXYM (force3dm), ST_Line_Substring, ST_Line_Interpolate_Point,
    ST_Line_Locate_Point, DissolvePoints (dumppoints), ST_MakePolygon.
  * Missing: `ST_Dump` (do in Nim / SQL), `ST_ClusterDBSCAN` (cluster in Nim, or drop).
  * No `geography` type: store lon/lat geometry (SRID 4326) and use UTM or the ellipsoidal
    length (`GLength(g, 1)`).
  * Checked OK: XYZM linestrings keep M/Z, ellipsoidal length, line interpolation and
    point location, MakeLine aggregate.
* With `proj` installed (`/usr/share/proj/proj.db`) the remaining checks pass:
  * UTM (EPSG:32719) length of a 0.01 deg test line is 929.96 m vs 930.08 m on the
    ellipsoid (analytic answer 930.079): the 0.013% gap is the UTM scale factor.
  * Buffer + intersects, `ST_OffsetCurve`, and `Transform` between 4326 and UTM work.
  * R*Tree spatial index: `CreateSpatialIndex('act','route')` builds `idx_act_route*`
    tables, and a `SpatialIndex` bbox search finds the right rows.
  * **Loading from Nim works**: `db_connector` (official; `nimble install db_connector`)
    has `enable_load_extension` / `load_extension` bindings over libsqlite3; a Nim
    program loaded `/usr/lib64/mod_spatialite.so`, ran `InitSpatialMetaData`, and got
    the same UTM length.  Note `DbConn` is a `PSqlite3`, so qualify `db_sqlite.close`.
* **Gotchas versus PostGIS** (matter for choochoo's M-based routes):
  * `ST_Line_Substring` interpolates Z but **does not interpolate M** (new points get
    M = 0).  If a sub-route needs its M (time / distance), compute it in Nim.
  * `ST_LocateBetween` returned only the vertex at M=60 for range 30..90, where PostGIS
    returns the interpolated line portion.  Do not rely on it for ranges.
  * No `geography`; SRID 4326 geometry only (use UTM or `GLength(g, 1)` for metres).
### Step 1 as built: `nch import`

(Written when step 1 was built.  Step 2, below, moved the code into the `activity/` module
and replaced `db/migrations.nim` and `PRAGMA user_version` by SQL fragments in each module.)

```
nch [--db PATH] [--user NAME] import [-q] PATH...     (PATH: a file, or a directory searched
                                                       recursively for *.fit / *.FIT)
```
* **Database file:** `--db PATH`, else `$NCH_DB`, else `~/.local/share/nch/nch.db`
  (`std/appdirs.getDataDir`); created on first use.  `--user NAME` selects an existing user
  (default: `default`, created by migration 1); there is no `nch user` command yet.
* **Bootstrap:** every database command starts with `openStore` (`db/store.nim`): create the
  directory and file, `pragma foreign_keys = on`, apply the migrations the file has not had
  (each in a transaction; `PRAGMA user_version` is the schema version; a database from a newer
  nch is refused), find the user.  New tables = new entries in `db/migrations.nim`
  (`allMigrations`); never edit a released one.  SpatiaLite is **not** loaded yet (nothing is
  spatial); that comes with the `route` migration.
* **Schema (migration 1):** `user(id, name)`; `file(id, user_id, name, sha256, imported_at;
  unique user+sha256)`; `activity(id, user_id, file_id, session, start_t, end_t, utc_offset_s,
  sport, sub_sport, elapsed_s, timer_s, distance_m, calories; unique file+session)`;
  `coords(activity_id, t, lon, lat, alt; primary key (activity_id, t)) WITHOUT ROWID`.
  Times are Unix seconds UTC, lon/lat degrees, alt metres.
* **Import rules** (`fit/activity.nim`, pure): one activity per FIT session; a file with no
  `session` message is refused (monitoring, settings, workout and weight files are not
  activities); times below 0x10000000 FIT seconds (before 1998-07-03) are not calendar times
  (FIT spec: seconds since the device was powered on, not UTC; shown as 1990 dates) - such
  records are dropped with a warning and a session that starts then refuses the file; a record goes to the last session starting at or before
  it; records sorted by time; several in one second keep the last (warning); no position, no
  coordinate; `utc_offset_s` = `local_timestamp - timestamp` from the `activity` message.
* **Per file, one transaction** (`db/importer.nim`); a failing file leaves nothing behind
  and the others carry on; the same content imported again by the same user is skipped
  ("already imported"; the hash is of the file's bytes).  A truncated or corrupt FIT file
  fails as a whole: repairing badly broken files is out of scope (use an online FIT fixer).  Warnings are grouped per file: one line per kind, with "and N more".
* Output: `imported  PATH  (1 activity, 2099 coordinates)` / `skipped   PATH  (already
  imported)` / `failed    PATH: reason`, then `N files: a imported, b skipped, c failed`;
  `-q` shows only failures and the summary; exit 1 if anything failed.
* New dependencies: `db_connector` (official; wraps libsqlite3, DbError becomes `StoreError`
  in `db/store.nim`) and `checksums` (sha2).  New error types: `StoreError`, `ImportError`.
* **Results on the 79 test files** (`nch --db X import ../choochoo/data/test/source`, 2.4 s,
  4.5 MB): 42 imported (74 activities, 106,599 coordinates), 3 skipped (copies in
  `python-fitparse-fix/`), 34 failed: 24 have no session (monitoring / settings / workouts /
  weight scales), 5 truncated or corrupt, 4 with device-clock times (1990; `antfs-dump.63` and
  `compressed-speed-distance`, each in two directories) and 1 repaired file with a corrupt
  second session.  Largest ride (24k records): 0.45 s.  First/last coordinates of a ride match
  `nch fit`; `pragma integrity_check` ok.
* Not yet: `nch user`, `route` (SpatiaLite) and anything that reads the data back, other
  channels (heart rate, cadence, power, distance, ...), laps, events (pauses), `--dry-run`,
  device-folder watching.  Old-clock files (1990 timestamps) could be accepted with a
  warning if you have such rides; for now they are refused.

### Step 2 as built: segments, and modules that own their SQL

* **Segments.** A segment is a stretch during which the timer ran (a timer `start` to the
  next stop).  Found in the real files: the 42-minute test ride has 20 start/stop pairs and
  no records at all while paused; the time between segments (412 s) equals elapsed minus
  timer time; most pauses are auto-pause (712 `auto` vs 102 `manual` triggers); files have
  from 1 to ~100 segments; 13 of 43 have a repeated stop, one ends while running, one has
  no timer events.  Table `segment(activity_id, n, start_t, end_t)`, `WITHOUT ROWID`,
  closed intervals on the activity's time axis, disjoint, in time order.  **Samples do not
  refer to segments**: `coords` (and every later channel table) stay keyed
  `(activity_id, t)`, so a channel module never needs to know about segments and segments
  can be recomputed without touching samples; "the coords of segment k" is a primary-key
  range scan.  (Alternative not taken: a `segment_id` on `coords`.)
* **Derivation** (`activity/extract.nim`, `segmentsOf`): per session, from its `event`
  messages with `event = timer`: a start while stopped opens a segment, a stop (`stop`,
  `stop_all`, ...) while running closes it; a start while running and a stop while stopped
  are ignored (normal, no warning); a first event that is a stop means running since the
  session began; still running at the end closes at the session end; no timer events is one
  segment for the whole session; clipped to the session; segments that touch or overlap
  (stop and start in the same second) are merged.  **Every coordinate lies in exactly one
  segment** (tested on every importable test file): a coordinate outside all of them extends
  the nearest and warns (`wkOutsideSegment`).  This happens with older devices that write a
  record a second before the timer-start event (Edge 500: ~45 per file, harmless).
* **Laps are a different partition,** set by the user or the device and ignoring pauses (the
  920xt ride has 3 laps and 15 timer starts).  Not nested in segments; a later `lap` table of
  intervals with the same shape.
* **Why segments matter:** a route through all points joins the two sides of every pause with
  a straight line; moving time is the sum of the segments; and GPX's `<trkseg>` is exactly a
  segment, so the first exporter writes one per segment.
* **Modules own their SQL** (see "Code layout" for the mechanism): the schema is the
  `fragment`s of the database (`db/001-schema.sql`), then those listed in `modules.nim`
  (`activity/sql/001-tables.sql`, `002-segment.sql`).  Replaces `PRAGMA user_version` and
  `db/migrations.nim`.  A database made by step 1 (user_version 1) is recognised, marked as
  having `db/001-user.sql` and `activity/001-tables.sql` (the `legacy` field of a fragment),
  and gets the new `segment` table; **activities it already holds have no segment rows**
  (their files count as already imported), so delete and re-import them if they matter.
* Moved with `git mv`: `fit/activity.nim` -> `activity/extract.nim`, `db/importer.nim` ->
  `activity/importer.nim`, `commands/importfit.nim` -> `activity/command.nim`.  `Globals`
  now carries `fragments` (filled in `nch.nim` from `modules.allFragments`); commands call
  `openStore(g)`.
* Output: `imported  PATH  (1 activity, 20 segments, 2099 coordinates)`.
* **Results on the 79 test files** (2 s): the same 42 imported / 3 skipped / 34 failed; 74
  activities, 435 segments, 106,599 coordinates; no coordinate outside or in two segments, no
  overlapping segments, every activity has segments, `integrity_check` ok.
* **AGENTS.md display layers (recorded, not built):** (1) a command's output is data or files
  in a suitable format for third parties (SVG, GPX, GeoJSON, ...), written to a standard
  directory that also serves as a cache (file names derived from the command invocation, to
  see when a cached result can be reused); (2) later a simple local web server that reads
  the URL after `localhost` as an nch command and shows its result (possibly via a cached
  intermediate html file).  What it asks of the code now is what `fit` and `import` already
  do: computing the result is separate from printing it (`renderInto`, `importPaths`).  The
  output directory convention is settled with the first exporter.
* **Import extension point (not built):** when the first channel module arrives (heart
  rate), the importer gets a list of steps that modules register in `modules.nim`, each
  writing its rows for an activity; designed with that second module.

### Step 3 as built: fast re-imports, a live display, a log

* **Fast path.** Table `seen_file(user_id, path, size, mtime, file_id, failure, message)`
  (`activity/sql/003-seen.sql`), one row per path looked at: absolute, normalised, symlinks not
  resolved.  A file whose path, size **and** mtime match is skipped without being read (path
  alone would miss a file saved over under the same name, e.g. repaired by an online fixer).
  A matching known failure is also skipped and reported as "known"; it does not make the run
  exit 1 (only a failure *in this run* does).  `--slow` ignores the table: it reads and hashes
  everything, retries the failures and refreshes the rows.  A moved or copied file is not in
  the table, so it is hashed, found in `file`, counted as skipped and recorded, so the next
  run is fast.  Rows are written in batches of 200; imports stay one transaction per file.
  The embedded profile is loaded only when a file needs decoding.
* **Accepted limits.** A file rewritten within the same second at the same size is missed
  until `--slow`.  A database from before this step has no rows: the first run is slow once
  and fills the table.  Rows for deleted files stay.
* **Measured** (3,000 files, 381 MB): re-import with nothing new 2.6 s -> 0.02-0.03 s; one
  new ride among them 0.08 s; `--slow` ~2.5 s (SHA-256 runs at ~175 MB/s).
* **Events, not prints.** The importer (`importPaths`) emits `ImportEvent`s (start, file
  start, file done, finish) and prints nothing; a sink is `proc(ev) {.raises: [].}` and
  `fanOut` calls several.  `ImportError` carries a `kind`, so failures are counted by kind
  (`no activity`, `bad time`, `bad format`, `unreadable`, `not found`, `database`) without
  parsing messages.  The plain sink's text is a pure function (`plainLines`), and tests collect
  it with `importReport`.
* **Streams.** stdout carries results and the summary line; stderr carries the live region,
  failures, warnings and notes.
* **Live display** (`ui/`, usable by any command): the command renders its state to styled
  lines (any number); `ui/live` redraws them in place (it can also print permanent lines
  above, unused by import).  Throttled in the driver, not the file reader: first frame after
  150 ms, then at most 10 per second by a monotonic clock, one write per frame.  **The last
  frame is always drawn and left on screen** (so even a very short run shows the final,
  coloured counts), followed by a `done: ...` line on stdout and, on stderr, a `more: grep
  ...` hint (see "Words").  Nothing is printed per file on screen: failures are counted by
  kind and described in the log.  Height capped at terminal height - 1, lines cut to the width by visible width,
  cursor hidden while drawing and restored on exit and on Ctrl-C.  Only when stderr is a
  terminal, `TERM` is not `dumb` and not `-q`; colours only if `NO_COLOR` is unset; otherwise
  the plain lines.  Checked under a pseudo-terminal (frame counts, cursor handling, `NO_COLOR`,
  `TERM=dumb`, a 40-column terminal).  **How it looks to a person has not been checked.**
* **Words** (same on screen, in the log and in hints; "warning" is not used for files): a file
  is `imported`; a `duplicate` (the same content was imported before: found by SHA-256, and the
  log and plain output say which file); `unchanged` (path, size and time as last time: not read);
  a `known failure` (failed before, unchanged); `failed`; and an **advisory** is something
  noticed in a file that was imported anyway (duplicate seconds, a coordinate outside the
  segments, trailing bytes...), counted one by one, not by file.  Counts that are zero are left
  out except imported and failed.  Every log line's text starts with one of `start imported
  duplicate failed advisory note done`, so `grep -w advisory` finds one kind.  After a run, if
  anything failed or was a duplicate or an advisory, stderr gets `more: nch log import failed
  duplicate advisory --last` naming only what happened (and nothing without a log); a test
  checks the hint is a command line `nch log` accepts.  (See Task 4 for `nch log`.)
* **Log file.** `$NCH_LOG`, else `$XDG_STATE_HOME/nch/nch.log` (a relative value is ignored),
  else `~/.local/state/nch/nch.log`; `NCH_LOG=` (empty) switches it off.  One line per event:
  `2026-11-02T23:27:00Z INFO  import    duplicate  PATH  same content as OTHER` (UTC; INFO /
  WARN / ERROR; the levels are not mentioned anywhere a user is told what to do).  `nch` logs
  each `fit`/`import` command's arguments and exit status.  `import` logs the start, each file
  imported, each duplicate (with the path it duplicates), each failure, **every** advisory in
  full (the screen groups them) and the totals; unchanged files and known failures are not
  logged one by one (a re-import of thousands would fill it), only counted in the `done` line.
  `-q` affects the screen only.
  Rotation when opened: over 5 MB, `nch.log` -> `.1` -> `.2` -> `.3`, the oldest deleted.
  Appended in block-buffered mode, flushed on WARN/ERROR and at the end.  A log that cannot be
  opened is disabled with one warning, and the work carries on.  Two `nch` processes at once
  append whole lines safely; a rotation race could lose a few.  No `std/logging`: its rolling
  logger rotates by line count, never deletes old files, and `log` is declared to raise
  anything, against `raises: []`.  `Globals.log` is nil (disabled) unless `nch` opened it, so
  tests never touch the real log.
* **Output conventions that follow:** library code computes and the command prints; progress
  and logging go through events and sinks.

### Routes, `select` and the schema revision (as built; `select` is now `nch list`, see Task 5)

* **SQL file naming:** a module's first file is `NNN-schema.sql` (`db/`, `importer/`,
  `selection/`); a change after release is `NNN-<what changed>.sql`.
* **`activity` has no `user_id`:** the user is the file's (`file.user_id`).  `activity.session`
  is the FIT *session* number: a FIT file has one "activity" message with one or more "session"
  messages, each a stretch of one sport (a triathlon has three); our `activity` is a FIT
  session, hence the clash of words.
* **SpatiaLite is loaded by every connection** (`openStore`: `load_extension`, then
  `pragma trusted_schema = 1`).  Without that pragma SQLite refuses to run the triggers
  SpatiaLite attaches to geometry columns ("unsafe use of GeometryConstraints()"): since 3.31 a
  database's triggers and views are untrusted by default, because a hostile file could use
  them to run functions with side effects.  Safe here because the schema is ours; the
  extension is switched off again straight after loading.  Costs ~20 ms per run (a no-op
  re-import of 3,000 files is 0.05 s).  `db/001-schema.sql` calls `InitSpatialMetadata(0,
  'WGS84')` (0: already in a transaction; only SRID 4326 loaded).
* **`route`** (`importer/001-schema.sql`): one `MULTILINESTRING` (XY, SRID 4326) per activity,
  a part per segment, spatial index `idx_route_geom`, written by the importer in the activity's
  transaction from the same coordinates (so it cannot disagree with them; a lazy route was
  rejected: every consumer would have to remember to build it, a read command would write, and
  building it costs microseconds).  Parts of fewer than two points are left out; an activity
  with no part has no row.  7 decimals (~1 cm).  No M values (SpatiaLite's sub-line functions
  lose them).  An ordinary table, since SpatiaLite cannot put geometry on `WITHOUT ROWID`.
  Distances: `ST_Distance(geom, MakePoint(lon, lat, 4326), 1)` is in metres (ellipsoid).
* **`nch select`** (`select/`): replaces the current user's rows in `selection(user_id,
  activity_id)` (which may point at other users' activities; `on delete cascade` both ways).
  No arguments shows it (`--all` selects everything).  `--users A B C` (default: the current
  user), `--from` / `--to` (local time zone, so `TZ` counts; a `--to` date means the whole day,
  a `--to` minute the whole minute; compared with the activity's start), `--near LAT,LON` or
  `--near latest` (centre of the box around the latest activity of the users) with `--radius
  KM` (default 100; `--radius` alone means `--near latest`), "passes within": a bounding-box probe of the spatial index, then the exact
  distance.  `--newest N` / `--oldest N` (`--latest` = `--newest 1`) keep N of the activities
  that meet the other criteria, by start time.  Not handled: circles across the antimeridian
  (the box widens to all longitudes, so the result is still right, only slower).

### Next (ideas, undecided)

1. Read the data back: `nch activities` (date, sport, distance, timer and paused time,
   segments).
2. Channel modules, each with its own `sql/`: heart rate, cadence, power, distance as
   `(activity_id, t)` tables; then laps and events.  The importer's step list is designed with
   the first.
2b. **`nch log`** (idea): show the log with the keywords coloured as on screen (imported green,
   duplicate grey, advisory yellow, failed red; no colour when piped or `NO_COLOR`), filtered by
   keyword (`nch log advisory duplicate`), `--last` for the latest run only, `-n N`.  The file
   stays plain text (an escape next to the word would stop `grep -w` matching).  The hint at the
   end of an import could then be `more: nch log advisory duplicate`.  Not started: `grep`'s
   own red highlight was the only red seen so far.
3. **Named places** (high priority): `nch place add home LAT LON`, then `select --near home`;
   later perhaps looked up by name over HTTPS (OpenStreetMap's Nominatim: needs OpenSSL, a
   polite user-agent and at most one request a second; cache the answer in the database).  An
   offline alternative is an embedded GeoNames list of cities over 15,000 people.
4. **Something pretty - maps or plots.**  Preference: do not plot locally; generate *input
   files* for external plotting / mapping services (GPX with a `<trkseg>` per segment,
   GeoJSON, CSV) from the database.  The first exporter settles the output-directory/cache
   convention; the local web server comes after that.
5. Later: training load, as a module with its own command and tables.

### Schema direction (agreed in discussion; built piecemeal, one `nch` command at a time)

* Approach for now: read an activity from a FIT file into the database; everything else
  (laps, other channels, processing) is added with the command that needs it, each as a
  new migration.
* **Everything per-sample is its own table, keyed `(activity_id, t)`**, `WITHOUT ROWID`
  (measured: 38.9 MB vs 57.5 MB per 1M rows with a separate index, ~32% smaller; a later
  conversion either way is a table rebuild, 0.7 s per 1M rows).  The first is
  `coords(activity_id, t, lon, lat, alt)`; later `heart_rate`, `cadence`, `power`,
  `distance`, ... in the same shape.  Position is just another channel (indoor and gym
  activities have none).  Always-NULL columns cost ~1 byte each in SQLite, so wide tables
  would also have been fine; this is for consistency.
* Tables for the first step: `user` (very lightweight - two people sharing a computer;
  a default user is created at bootstrap, `--user` later), `file` (name, sha256 UNIQUE,
  imported_at), `activity` (one row per FIT *session*: user_id, file_id, start_utc, sport,
  sub_sport, timer/elapsed time, distance, ...; a file can hold several sessions), `coords`.
* `route` (the whole path as one `LINESTRINGZM`, M = t, with a spatial index) is a **separate
  ordinary table** (`activity_id` UNIQUE): SpatiaLite refuses geometry columns on
  `WITHOUT ROWID` tables.  It is derived from `coords`, added by a later migration when a
  command needs it (maps, "near here"), and built at import from then on.
* Time as Unix seconds UTC (local offset kept on `activity`); coordinates as degrees,
  SRID 4326.  Two records in the same second: keep the last, record a warning.
* Import is one transaction per file and repeatable (same file hash = no-op); each FIT
  record goes to the session whose time range contains it.
* **Bootstrap:** one function (`openDb`) that every database command calls: create the file
  if missing, load `mod_spatialite`, apply pending migrations (tracked with
  `PRAGMA user_version`; SQL kept in code), ensure the default user exists.
* Data: test rides vary a lot (`personal/2018-08-27-rec.fit` has only position, distance,
  speed and heart rate; `python-fitparse/Edge810-Vector...` adds power, temperature and
  cadence; some records drop fields).  Unknown / device-specific messages and fields are
  not stored yet.
* Names so far: `coords` (not `position`: it has time), `route`.

## Task 1: translate the choochoo FIT parser to nim

Source: `../choochoo/py/ch2/fit/` (`profile/*`, `format/{read,tokens,records}.py`).
Profile: `../choochoo/data/sdk/Profile.xlsx` (keep this version for now - eases
validation against choochoo; update to current SDK later).

### Decisions

* Read `Profile.xlsx` directly in nim, at runtime, so users can supply their own
  profile transparently.  No C libraries.
* Default profile embedded in the binary (`staticRead`); `--profile PATH` to override.
* Cache parsed profile (keyed by hash of xlsx bytes) only if parsing proves slow.
* Std lib preferred; stable nimble packages ok (`zippy` is the key dependency).
* Wrap the xlsx library behind a small adapter ("rows of cell values for sheet X")
  so it can be replaced by our own zippy + `std/parsexml` reader if needed.
* Out of scope for now: fix/repair (`fix.py`, `repair_*`), output formats,
  garmin download.

### Update: own xlsx reader (replaced `xl`)

`xl` was only ever meant as a stopgap (HEAD-only dependency, loads from a path only so
the embedded profile needed a temp file).  `src/nimchoo/xlsx.nim` now reads xlsx from
memory: it parses the zip central directory itself (zippy's zip reader is path-only),
inflates entries with zippy, and reads the workbook / relationships / shared strings /
sheet xml with `std/parsexml`.  Handles namespace prefixes (the profile uses `x:`), a
BOM, rich-text shared strings, inline strings and entities.  Identical cells to `xl`
on both profile sheets (13,225 non-empty cells), ~17 ms; `xl` is no longer a
dependency (only zippy).  Tests use hand-made stored-zip xlsx files for the edge
cases.  `xlsxrows.nim` is now a thin layer over it; `loadProfileFromBytes` loads the
embedded profile without a temp file.

### Step 1 result (historical: how `xl` was chosen)

* nimble `xlsx` 0.4.8 does NOT compile on nim 2.2.12 (C codegen error in
  `parseOverride`); it also extracts to a temp dir.  Rejected.
* nimble `xl` (khchen/xl, HEAD, needs only zippy) works.  Use
  `load(path)` then `wb.cells(sheetName)` (fast, readonly iterator).
  Install into a local dir: `nimble --nimbleDir:DIR install -y xl`, compile with `--path`.
* Quirks: `rc` is 0-based (row, col); all values are strings (numbers too); empty
  cells come back as "" (and may be skipped, so build rows sparsely, keyed by col).
  Cells arrive in row order.
* Checked: `farmers_walk` -> value "1"; `Types` 3421 rows, `Messages` 1327 rows;
  dynamic/composite rows look as described in the notes below (components,
  ref_name/ref_value as comma lists).  Not yet checked: subfield rows of
  `session.total_cycles` specifically (do in step 3 tests).
* Timing: load + both sheets = ~38 ms (release).  No cache needed.
* Messages columns (0-based): 0 msg_name, 1 field_no, 2 field_name, 3 type, 4 array,
  5 components, 6 scale, 7 offset, 8 units, 9 bits, 10 accumulate, 11 ref_name,
  12 ref_value.  Types: 0 type_name, 1 base_type, 2 value_name, 3 value, 4 comment.

### Steps

1. [x] Experiment (in /tmp): read `Profile.xlsx` with nimble `xlsx` (fallback `xl`,
       then own reader).  Check known values (`carry_exercise_name.farmers_walk = 1`,
       `session.total_cycles` subfields) and time it.
2. [x] Project setup: nimble package, layout, test framework.
       `nimchoo.nimble` (deps: xl, zippy), `src/nimchoo.nim` (entry), modules in
       `src/nimchoo/` (first: `xlsxrows.nim`, the xlsx adapter), tests in `tests/`
       (`std/unittest`; one `test_*.nim` per module, imported by `tests/all.nim`).
       `nimble setup` once (generates `nimble.paths`, gitignored), then `nimble test`
       / `nimble build`.  Tests run from the project root (profile path is relative).
3. [x] Profile model and loader: `src/nimchoo/profile.nim` (plain-data `Profile`:
       `FitType` / `Field` / `Message` object variants, refer to each other by name;
       `loadTypes`, `loadMessages`, `loadProfile(path)`).  Tests in
       `tests/test_profile.nim`.  Loads 183 types, 87 messages, 1166 fields.
       Deferred: embedded default profile (`staticRead`) - `xl` only loads from a
       path, so needs a temp file or own reader; do when the CLI needs it.
       Notes: composite rows hold per-component comma lists (may contain newlines) in
       scale/units/etc, so the field's own scale/units are not parsed for them; dynamic
       choices keep sheet order (first match wins) with ref values resolved to numbers
       at load time; subfields are ordinary fields in `Message.fields` (number = none).
4. [x] Low-level binary: `src/nimchoo/binary.nim` (CRC, base type sizes/bad
       markers/decoding in both endians, strings, FIT time + `expandTimestamp16`,
       `FileHeader`/`readHeader`/`problems`).  Tests in `tests/test_binary.nim`.
       Conventions: `Option` for legitimately absent values (bad values, unknown base
       type byte); `FitError` only when we cannot continue; diagnostics returned
       (`problems`, `backwards` flag) rather than logged.  Behaviour follows choochoo
       (all-bad arrays -> none; isolated bad elements in arrays stay raw, as the SDK
       CSV does - revisit if it matters).  Timestamps are FIT seconds (int64);
       `fitToUnix` / `fitToTime` convert.  `crc16` over a whole valid file is 0.
       Scan of the 76 test .fit files: 67 clean; 9 report problems - 7 in
       `python-fitparse/` (some deliberately broken) and 2 in `other/` whose header
       data size is 0 (2018-02-24-10-04-10, 2018-04-15-09-18-20).  Step 5 should
       decide how to treat those (tokenise to end of file?).
5. [x] Tokenizer: `src/nimchoo/tokens.nim` (`Tokenizer`, `Token`, `Definition`;
       `initTokenizer(data, ts16)`, `next`, `tokens` iterator).  Tests in
       `tests/test_tokens.nim` (hand-built files + all sdk/personal files).
       * Tokens are small values: byte range + index into `Tokenizer.defs` (every
         definition seen; local type -> def via private `active` table).  Needs only a
         `HashSet` of timestamp_16 (message, field) pairs from the profile
         (`timestamp16Fields`); field 253 is the timestamp in any message.
         Developer field *definitions* (msg 206) are step 6; sizes come from the
         definition so tokenizing doesn't need them.
       * Uses header `dataSize` when it fits (else falls back to end of file - 2, with a
         warning), and handles chained FIT files (a second ".FIT" header after the CRC;
         definitions reset, timestamp kept).
       * Raises `FitError` (with offset) for: data with no definition, truncated
         definition/data message, compressed timestamp before any timestamp.  Tokens
         before the error have already been yielded.  Other oddities go in `warnings`.
       * Note: absolute timestamps in real files are not monotonic (sdk
         MonitoringFile: monitoring_info is stamped 61h before the preceding
         device_info), so no monotonic check.
       Scan of all 76 test files: 72 tokenize fully, 4 raise: python-fitparse
       `activity-settings-nodata` (truncated definition), `activity-unexpected-eof`
       (truncated data), and `other/2018-02-24-10-04-10`, `other/2018-04-15-09-18-20`
       (header dataSize 0 and cut off mid-record, no CRC) - all genuinely truncated
       (what fix/repair was for).  Chained-file handling reads `activity-activity-filecrc`
       and `python-fitparse/event_timestamp` as two files.  Warnings only in
       python-fitparse*/ and other/ files (`other/38014592427` has 17 timestamp_16
       small backwards jumps, as in choochoo issue 5;
       `python-fitparse-fix/event_timestamp` has 256 warnings from junk bytes inside
       the data).
       Decision: a truncated final record stays an error for now (could become a warning
       that stops tokenizing, no checksum token, if the truncated files turn out useful).
6. [x] Message decoding: `src/nimchoo/decode.nim` (`Reader` + `records` iterator;
       `Decoder.decode` for single tokens; `Record`, `FieldValue`, `field`,
       `valueName`).  Tests in `tests/test_decode.nim` (hand-built files, first
       records of sdk Activity/DeveloperData vs the SDK CSVs, all sdk/personal files
       decode with no warnings), plus a profile test that no dynamic field refers to
       another dynamic field.  Shared test builder in `tests/fitbuilder.nim`.
       All 76 test files: 166,689 records in ~0.65s (release); the 4 truncated files
       raise FitError from the tokenizer as in step 5; no decoder warnings.
       Design (differences from choochoo are deliberate - check them in step 7):
       * Values stay numeric (`FieldValue.ints/floats/strings` + profile `typeName`;
         `valueName` maps enums to names).  Bad fields are omitted.  Unknown fields /
         messages are kept with empty names.
       * The definition's base type drives binary decoding (choochoo used the profile
         type with the definition's count).  Enums never scaled; scale 1/offset 0 stays
         int; otherwise float `v/scale - offset`; isolated bad array elements unscaled.
       * Composites expand into their components, decoded as the target field; the
         composite itself is NOT emitted (the SDK CSV does emit e.g. `speed` next to
         `enhanced_speed`).  Outermost component scale/offset wins.  Components are bit
         ranges of the whole field, any size (byte arrays > 8 bytes work); components
         that do not fit are ignored (profile lists 10 x 12 bits for the 12-byte
         `hr.event_timestamp_12`; choochoo emitted zeros).
       * Dynamic fields: first matching choice, trying referenced fields in first-seen
         order.  Components can target dynamic fields (event.data16 -> data).  Decoded in
         three passes (plain, composite, dynamic) instead of choochoo's dependency sort;
         output keeps definition order.
       * Accumulators keyed by (message number, field name) (choochoo: name only), SDK
         rollover arithmetic; reset for chained files.
       * Developer fields registered from field_description records (also scale/offset,
         which choochoo ignored); undescribed ones are skipped with a warning.
       * 19 profile fields have non-integer scales (0.7111111 on *_power_phase,
         10430.38 on aviation_attitude.*).  Choochoo parsed scales as ints and silently
         used 1; we use the real values.
       * Duplicate names (eg altitude/enhanced_altitude both present) are separate
         entries; `field` returns the first (choochoo concatenated them).
7. [x] Validation: `nch fit` + comparison against the SDK CSVs.
       * Structure (decision): a single `nch` command; `src/nch.nim` is a thin
         dispatcher, each subcommand is a module under `src/nimchoo/commands/` with
         `run(args): int` (global options such as database connections are to be
         parsed in `nch.nim` before the command name).  Library modules stay in
         `src/nimchoo/`.
       * `nch fit [--csv] [--profile PATH] FILE`: readable dump (enumerations by name,
         times as ISO UTC, developer fields as `dev.name`) or SDK-format CSV
         including definition rows.  Warnings/errors go to stderr; output before an
         error is kept.  Default profile is embedded (`data/Profile.xlsx` copy,
         `staticRead`, loaded from memory).
       * `decode.nim` gained `events` (definitions + records, with developer field
         names as described so far), `Record.local`; `csvout.nim` writes the rows.
       * Harness: `tests/csvcompare.nim` (choochoo's CSVEqualContext rules: row by
         row, first three cells equal, per-field value/units, `unknown` skipped,
         `.0`/bool fixes, numbers as floats, header/checksum rows dropped, SDK-only
         composite fields skipped, `Activity.fit` ignores `timer_trigger`),
         `tests/test_sdkcsv.nim` (one test per file),
         `nimble csvreport` (differences grouped by message/field/kind, for triage).
       * Scope (decision): the comparison covers `sdk/` and `personal/` (26 files),
         whose CSVs match the SDK version of Profile.xlsx; all 26 match exactly.
         The CSVs in `python-fitparse/` and `other/` (21) are from an older SDK /
         profile and are no longer compared (the other 50 files just have to decode
         without warnings).  They differed only in: cycling `total_cycles` vs our
         `total_strokes`, `session.num_lengths` unknown to their profile, distance
         rounded to 2dp, and one choochoo-made CSV.  Regenerating them with the SDK's
         FitCSVTool (`../choochoo/dev/build-csv.sh`; no Java/SDK on this VM) would
         allow comparing all 76 files.
       * `timestamp_16` fields stay raw (as the SDK prints them); `Record.timestamp`
         has the expanded time.
       * Duplicate names (decision): one entry per name per record.  `FieldValue.bits`
         is the width of the source it was decoded from; the widest source wins (most
         precise; eg `data` 32 bits over `data16` 16 bits, `enhanced_altitude` over
         the value derived from `altitude`), the first on a tie; invalid values are
         dropped first, so a valid narrow value survives an invalid wide one.  Several
         values for one name from the *same* composite (eg the eight event_timestamps
         of `hr.event_timestamp_12`) are concatenated into one array.  The harness
         accepts the SDK's `x|x` (it merges the two sources) for our `x`.
       * Known and accepted differences from choochoo: composite fields themselves
         are not emitted; the 19 fractional scales use their real values; accumulators
         are per (message, field).  None of these showed up as a mismatch against the
         SDK output.

### Notes on the profile spreadsheet

* `Types` sheet (type_name, base_type, value_name, value, comment): a row with
  type_name starts a type; following rows are name -> value pairs.  Capitalised
  names are section headings (skipped).  Hard-coded: string, enum, byte, bool,
  [su]intN[z] / floatN (inferred from name), and overrides date_time,
  local_date_time, timestamp_16.
* `Messages` sheet (msg_name, field_no, field_name, field_type, array, components,
  scale, offset, units, bits, accumulate, ref_name, ref_value, ...): a row with
  msg_name starts a message (number from `mesg_num` type); following rows are
  fields.  Composite if `components` set (comma-separated parallel lists, each
  component delegates to a named field in the same message).  Dynamic if followed
  by rows with field_name but no field_no (subfields selected by ref_name/ref_value).
