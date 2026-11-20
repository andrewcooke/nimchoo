# part C: climbs, geo, cache, download (status: done)

## 1. `effort.start_m` is measured from the start of the stretch, not of the ride

`climbs/work.nim:69` (`overRide`), `climbs/match.nim:237` (`startDist: p.s.dist`), shown by `climbs/map-efforts.js:17`.

Since algorithm version 4 a ride is matched one stretch at a time (`overRide` calls `overPaths(sector, p)` for each
stretch), and `overPaths` builds `cum` from 0 at the first point of the path it is given.  So `startDist` is metres from
the start of the *stretch*, yet the schema (`001-schema.sql:37`: "metres along the ride at the start gate"), the doc of
`Effort.startDist` ("metres along the ride given") and the map popup ("started N m into the ride") all say ride.
Scenario: a ride stopped by hand at the café after 40 km, then up Farellones from 3 km after the restart: the popup says
"started 3000 m into the ride".  (It is also flat-projected distance in the sector's projection, not the ride's
`distance` record; small, but a second meaning.)

Fix: add the stretch's offset (cumulative distance of the ride up to the stretch's first point, or the record's
`distance` at the start gate) in `overRide`, and test with a two-stretch ride.  Confidence: confirmed.

## 2. The profile interpolates the altitude across any gap, though its doc says it never does

`climbs/profile.nim:86-91` (doc at lines 8-10; `detect.nim` `findClimbs(p: Profile)` relies on it).

The doc: "where there is none it is not made up (NaN), and a climb never crosses such a gap", and `findClimbs` searches
each `validRuns` run separately for that reason.  But the code fills every sample between the first and the last point
that has an altitude by interpolating between the two nearest ones, however far apart (`d >= altD[0] and d <= altD[^1]`
is the only test).  So NaN appears only before the first and after the last altitude, `validRuns` gives one run, and a
climb can be made from a straight line across a barometer dropout.  Scenario: altitude missing for 3 km in the middle of
a stretch (a device that drops the field, a merged file): the samples across the hole rise linearly between the two ends
and can complete or join a climb.

Fix: leave NaN where the two altitude points either side are more than some distance apart (e.g. 50 m, ten steps), so
`validRuns` really splits; or change the doc if interpolation is what is wanted.  Confidence: confirmed (code); how
often it happens with real files is unmeasured.

## 3. `climbs --edit NAME --auto` offline says the climb "is now called unnamed"

`climbs/command.nim:74-90` (`editClimb`, `ckAuto`).

`ensureSectorNames` does not raise when `--offline` and the places are not cached: it counts the climb in `named.left`
and leaves the name null.  `editClimb` ignores `left` and says `was & " is now called " & shownName(st, id)`, and a null
name is shown as "unnamed" (or "unnamed₇": `setAuto` has just numbered it in the unnamed group).  Scenario: `nch
--offline climbs --edit 'Farellones₃' --auto` with the places round it not in the cache prints "Farellones₃ is now
called unnamed₇", which is false: it has no name yet and the next online `nch climbs` names it.  The branch also
repeats `nameClimbs` (open the names, name, report damaged) by hand, without its log line or its `left` warning; that
copy is where the case was lost.

Fix: call `nameClimbs` here too and word the result from `Named` (named / nothing near / left for later).  Confidence:
confirmed.

## 4. The naming warnings lose their style: `say warnLine(...).text`

`climbs/naming.nim:83,88`; the `say` given is `g.say osErr` (`command.nim:132`, `:79`) or the import's `ctx.say`.

`nameClimbs` builds a `warnLine` (style `warn`) and then passes only its `.text` to `say`, which writes plain text in the
theme's `default`.  So "warning: 2 climbs have a route that cannot be read ..." and "... climbs left unnamed
(`--offline` ...)" are the only warnings of `nch climbs` not in the warning colour (the retired note just below uses
`g.warn`).  The ui rule is "everything a person reads is in the theme".  Also: the `left` warning is not logged (the
damaged one is), and it is not pluralised ("1 climbs left unnamed"; `counted` exists).

Fix: give `nameClimbs` a `Line` sink (or `Globals` and `g.warn`) instead of a `string` one.  Confidence: confirmed.

## 5. Matching a typed climb name is written three times, in Nim loops

`climbs/attempts.nim:62-88` (`namedClimbs`, for `climbs --names`), `climbs/criterion.nim:23-56` (`resolveClimbs`, for
`activities --climbs`), `climbs/edit.nim:14-42` (`findShown`, for `--edit NAME`).

Each loads `shownNames`, folds every name and every `ordinalForms` of the text, and loops; the first two are the same
rule ("the shown name holds the text, else a whole number is a climb's id") written twice, and they already differ in
more than the documented retired/not-retired: `namedClimbs` silently finds nothing for a text no climb has (so
`climbs --names farelones` says "no climb meets the criteria"), while `resolveClimbs` names the text that failed.  One
fact, one place: the next change to how names are typed (it has changed twice: "(4/5)", subscripts) must be made in
three places.

Fix: one `matchClimbNames(st, texts, retired: bool): seq[(text, ids)]` in display/report, used by all three (and with
`fold()` already an SQL function, the "holds" test could be one query).  Confidence: confirmed.

## 6. `--duplicates` help says "more than half"; the test is at least four fifths

`climbs/params.nim:283` against `climbs/overlap.nim:24` (`nearCopyLimit = 0.2`) and `climbs/duplicates.nim:1`.

The help: "list the climbs that largely overlap (more than half of each lies within 25m of the other)".  The query keeps
pairs with `sa > :keep and sb > :keep`, `keep = 1.0 - nearCopyLimit` = 0.8, and the report's own heading (made from the
constant) says "at least 80% of each".  "More than half" is `repeatLimit` (0.5), the other use of the same query: the
help mixed the two.  The radius is taken from `gateRadius`; the share was typed by hand.

Fix: make the share in the help from `nearCopyLimit` (as `duplicateLines` does).  Confidence: confirmed.

## 7. `--from` / `--near` / `--radius` written twice: `climbs/params.nim` and `activities/criteria.nim`

`climbs/params.nim:14-15,33-39,138-163,177-200,363-369`; `activities/criteria.nim:19-27,89-90,333-345,375-379,497-512`;
the resolution `climbs/found.nim:34-46` vs `activities/command.nim:318`.

The two commands have the same option rule (CLAUDE.md "`--from` is where a thing starts and `--near` is where its route
passes ... each also takes a place's name ... and says which place it used"), and each has its own copy of: the
defaults `defaultStartKm = 10.0` / `defaultPassKm = 1.0`, the kind enum (`NearKind nrPoint/nrPlace` vs `NearKind`
`Spot`), the "a value that starts with a digit or sign is a position written wrongly" heuristic, the `startKm`/`passKm`
helpers, the help text, and the note "starting near LAT,LON (place), within Nkm".  They have already drifted (activities
also takes `latest`/`previous`; the error examples differ).  A third user (landmarks `--near`) has its own again.

Fix: one `geo`- or `names`-level "spot" (parser, defaults, help fragments, resolver that returns the point and the
note), used by both commands.  Confidence: confirmed.

## 8. "" as "none" or "ok", against the parse-don't-validate rule

- `climbs/params.nim:102` `nameProblem*`: returns "" when the name is fine ("" if `s` can be the name ..."); the rule
  says no "" meaning "ok".  Should be `Option[string]` (or a `ClimbName` distinct type from a `parseClimbName`).
- `climbs/detect.nim:37,42` `Climb.category`: "" if too small, turned into NULL by `bindOptText` and back into "" by
  `coalesce(category, '')` in three queries (`attempts.nim`, `duplicates.nim`, `report.nim`).  `Option[Category]` (an
  enum, which would also make `categoryNames` in `params.nim:17` and `categories` in `detect.nim:27` one list: today the
  category names are written in both).
- `sector.name`: null "not yet named" and '' "looked at, nothing near" (`naming.nim:29`, schema comment): two kinds of
  absence in one text column; a `named_at`/`no_name` flag would say it.

Fix: as each line says.  Confidence: confirmed (rule breaks, not bugs).

## 9. `cache --delete` hides what it could not delete; `except Exception`

`cache/files.nim:88-112` (`deleteKind`), `:57-68` (`walkFiles`), `cache/command.nim:70-77`.

`deleteKind` swallows every `OSError` (a file it could not delete is "left (and not counted)"), and ends with
`except OSError, Exception: discard`; CLAUDE.md: never `except Exception` (only at the top of a thread or server
loop, said so in a comment), and "a failure is never stored as a result: raise, or warn and leave the work undone".
Here it is neither: the command prints "deleted downloads: 3 files (2.1MB)" and exits 0 when, say, `data/` is
read-only and 40 files remain; `walkFiles` likewise turns an unreadable directory into "no files" in `nch cache`.
Scenario: the cache dir owned by root after a `sudo nch ...`; `nch cache --delete all` says it deleted what it could and
nothing about the rest.

Fix: return the paths that failed (or raise a `CacheError` from the first) and have the command `g.warn` them and exit
1; catch `OSError` only.  Confidence: confirmed (the `Exception` clause and the silence; the scenario is constructed).

## 10. `cache` hand-made output beside the shared helpers

`cache/command.nim:33-36,63-64`, `cache/files.nim:31-50`.

- The "kinds" section of the usage is aligned by padding (`" ".repeat(10 - len($k))`), not wrapped to `width` (a long
  `kindHelp` runs past a narrow terminal) and not made the way `calendar`'s "subjects" section is (`registryLines`).
  The ui doc: every table through `ruled`.
- The empty cells are a literal `"-"`, not `notRecorded` (`ui/units.nim:8`), and a count of nothing is not "not
  recorded" anyway: "0" files, "0B".
- `parseKind(s, kind: var Kind): bool`: an out parameter and a bool; should be `Option[Kind]` (parse, don't validate;
  results are returned).  `kindNames` and `kindWords` are two loops over the same enum where `kindWords` would do.

Fix: one line each, as above.  Confidence: confirmed.

## 11. The download failure line is made three times, and unstyled when not live

`download/fetch.nim:107-108` (`describe`, `deFailed`), `download/sinks.nim:97`, `download/spinner.nim:126`; used plain
by `screenSink` (`sinks.nim:35-39`, `write describe(ev)`) through `names/open.nim:31`.

"cannot download {shortUrl(url)}: {message}" is written in `describe` (plain text) and again, styled `bad`, in the live
sink and in the spinner thread.  When the terminal cannot live (piped, or `TERM=dumb` with colour forced), the failure
goes through `screenSink` as a plain string to the command's `say`, so it is in `default`, not `bad`: the same class as
finding 4 (a `string` sink where a `Line` is needed).  Also in this file: `describe`'s `deProgress` branch is dead
(`screenSink` filters it out and nothing else calls `describe`).

Fix: one `failedLine(url, message): Line` used by all three, and `screenSink` taking a `Line` writer.  Confidence:
confirmed.

## 12. "" for "ok" and a bag for a result in `download`

`download/fetch.nim:195-209` (`checkContent`: `""` if what came is right), `:30-34` (`FetchResult`: `ok`, `status`,
`body`, `message`, with `body` meaningful only when `ok` and `message` only when not), `download/sources.nim:11`
(`zipEntry: ""` if not a zip).

Each is a case CLAUDE.md names ("no '' or -1 meaning none or ok", "no bags of booleans checked afterwards"): a
`FetchResult` with `ok: false, body: <something>` can be built, and nothing stops a caller reading `body` of a failure.

Fix: `checkContent` returns `Option[string]` (the problem); `FetchResult` a variant on `ok`; `zipEntry: Option[string]`
(or a `SourceKind` of plain / zip).  Confidence: confirmed (rule breaks).

## 13. `parsePosition` accepts NaN; `--radius nan` too

`geo/position.nim:17-21`; `climbs/params.nim:155-163` (`takeRadius`), the same in `activities/criteria.nim`.

`parseFloat` reads "nan" (and "NaN"), and every range test is false for NaN, so `parsePosition("nan,nan")` is
`some((NaN, NaN))`: `nch climbs --near nan,nan` is accepted, says "passing near nan,nan, within 1km" and finds nothing
(the activities' `--from`/`--near` and `nch landmarks --near/--at` the same).  `takeRadius` tests `r <= 0`, which NaN
passes, so `--radius nan` finds nothing silently.  `cells.cellOf` already writes its test the safe way (`not (lon >= ...
and ...)`).

Fix: test with `classify` (or write the range tests as `not (x >= lo and x <= hi)`) in `parsePosition` and in every
`--radius` reader; a test with "nan".  Confidence: confirmed (from the code and `parseFloat`'s grammar; not run).

## 14. Dead code and stale docs

- `climbs/describe.nim:38` `climbLine`: used only by its test.  `download/fetch.nim:305` `dataUsage` / `DataUsage`: used
  only by its test (`cache/files.useOf(ckDownloads)` does the same for the command).  Delete both.
- The old "(4/5)" numbering is still the example in `climbs/describe.nim:4,16,39` and `climbs/attempts.nim:216`, and
  "(n/m) numbering" in `climbs/001-schema.sql:20`; the numbers are subscripts now ("Cerro San Luis₄", as the package doc
  says).  The same schema comments name `nch sector --edit NAME --rename NEW` (line 10: the command is `climbs`) and "or
  005 by hand" (line 50: there is no 005).  (Fragments are not to be edited once a database has had them, so these go
  right at the next squash; note them in TODO.md until then.)
- `download/sources.nim:2` points to "TODO.md, task 13": TODO.md has no task 13.
- `climbs/work.nim:36`: version 4 says `importer/stretch.nim`, the module doc says `importer/track.nim` for the same
  thing (both exist; say which reads a ride as stretches).
- `climbs/mapframes.nim:36,62,105` write `"unnamed"` where `display.unnamed` exists; `ridesUp*` is exported for nobody.

Confidence: confirmed.

## 15. `climbs --all --delete` speaks of "sectors"; the rest of the command says "climbs"

`climbs/work.nim:291` (`describe(Counts)`), shown by `climbs/command.nim:96-104`.

The user's word is "climb" everywhere (`workedText`, `retiredText`, the done line, the help); `sector` is the table's
name.  But the delete says "would delete 43 sectors and 220 efforts (of every user); use `-f` to confirm" and then
"deleted 43 sectors and 220 efforts".  Smaller drift in the same messages: `workedText` and `damagedText`
pluralise by hand where `counted` exists, and the log line in `command.nim:126-131` restates `workedText` by hand.

Fix: `counted(c.sectors, "climb", "climbs")` and `workedText` in the log.  Confidence: confirmed.

## what is good

- The spatial work is where CLAUDE.md wants it: candidate rides and sectors are integer joins on `route_cell` /
  `sector_gate_cell` (filled by a trigger, one margin constant), overlaps are SpatiaLite, and the one Nim exception
  (`overPaths`) says why, with the measurement.
- `geo/cells.nim` is one definition shared with SQL (`db/functions.nim`), and its doc states the limits accepted.
- Damaged routes are refused everywhere they are read (`parseLineString` gives none, callers raise or skip, never store
  "nothing here"): the "a failure is never stored as a result" rule followed carefully.
- `climbs/params.nim` parses into variants (`Params` on the action, `Listing`, `Change`): a meaningless combination
  cannot be represented; the frames' declared tables are tested against what they read.
- `download` is the single network door: sources listed once, sizes and room checked, writes atomic, events not prints.
