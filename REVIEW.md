# nimchoo: code review (2026-11-08)

Scope.  First pass, by hand: the dispatcher, the CLI parser, the db layer and every SQL fragment, climbs
(command, params, detect), the activities command and its criteria, the importer pool, the server handler, a
sample of tests, TODO.md's conventions; the import graph and the real database (read-only).  Second pass, by
three subagents: fit/, profile/, xlsx, zip, bundle/; names/, landmark/, download/, the rest of climbs/, geo;
ff/, model/, map/, serve/, templating, cache, ui/.  Their most serious claims were checked by hand; the rest are
marked "reported".  ~18k lines of source; 1159 tests, all passing (`nimble test`, 2026-11-08).

Section 6 (packages) was agreed in discussion with the author afterwards.

## 1. Summary

The code is **competent and careful, but "locally good, globally drifting"**.  Individual functions are clear,
pure where they can be, well commented and well tested; the error discipline (`{.push raises: [].}` everywhere,
checked by the compiler) is stricter than most Nim.  What is weak is the layer above the functions: the same
fact is written in several places that nothing keeps in step, module boundaries no longer match what the
modules do, the database layer stops halfway (typed writes, string reads), work that SQL should do is done in
Nim, and some parts are built bigger than they need to be.  These are the typical results of many small
AI-written increments, each correct, none revisiting the whole.  There are also a handful of real bugs (§3).

## 2. Good

* **Error handling**: four kinds of failure, one mechanism each; `raises` is compiler-checked; commands return
  exit codes and never leak traces for expected errors.
* **Schema**: `strict` tables, `without rowid` where it pays, `on delete cascade` from user down, spatial
  indexes used where it matters.  WAL, `synchronous=normal`, incremental vacuum: all appropriate.
* **Database versions**: numbered SQL fragments per module, checksums, append-only, applied in a transaction,
  squashed at milestones.  Good; it stays (and becomes per package, §6).
* **Pure modules**: `climbs/detect`, `geo`, `shape`, `climbpick`, `match`, `ordinal`, `bits` are small, pure,
  documented and tested.  Distinct types for `FitTime`/`UnixTime` and the ids.
* **The FIT tokenizer** checks every length read from the file before using it, with offsets in the errors.
  Real variant objects where they are used (`Token`, `Event`, `FieldValue`).
* **`download/fetch`** is a model design: network and disk injected, size and free space checked, atomic writes.
* **The web server**: whitelist routing, Host check, token compared in constant time and kept out of logs and
  URLs, CSP, no shell; no path traversal found.
* **The maths**: impulses integrated analytically; storing impulses per hour is the right design.
* **Tests**: real databases in temp dirs, error paths tested, `offline: true` enforced, a structure test.
* **Dependencies**: few and sensible (zippy, db_connector, checksums).

## 3. Bugs

### 3.1 Checked

* **Climbs ignore timer segments.**  `climbs/work.nim:204-233` builds one profile from every point of the
  activity, though `buildProfile` (profile.nim:76) says its input is one timer segment.  A ride with the timer
  stopped while the rider is moved (car, train) gets the gap as road: invented climbs, efforts across the gap.
  A café stop is harmless.
* **One bad GPS fix can fetch every country**: `names/lookup.nim:66` falls back to `allCountries()` when the
  box has more than 4000 cells, and every country's GeoNames file is downloaded (~250 zips).
* **No index on `effort(activity_id)`**: deleting activities and `activity_id in (...)` scan the table.
* **The web server can hang**: `serve/server.nim:19-21` reads all of stdout, then all of stderr, then waits
  with a timeout; a hung worker is never timed out or killed, and one that fills the stderr pipe deadlocks.  The
  server is single-threaded, so one slow `map` (the first works out climbs) blocks every request.
* **The map cache goes stale**: `map/command.nim:186-188` reuses an existing file; the key covers the
  activities only, so a renamed climb (or a changed detector) keeps the old map until the cache is deleted.
* **`landmarks` runs are not logged**: `commandNames` (cli/common.nim) lists `import` (gone) and lacks it.
* **A FIT bool's invalid marker (0xFF) reads as true** (`fit/decode.nim:124-127`); every other type drops
  invalid values.
* **The zip size limit does not limit**: `zipbytes.nim:60` checks the *declared* size, inflates everything,
  and compares afterwards.  Low risk (inputs are GeoNames and the profile), but it should cap the output.

### 3.2 Reported, not yet checked (check each with a test before fixing)

* Case folding disagrees: SQL `lower()`/`trim()` are ASCII-only (ordinal.nim, landmarks.nim, suggest.nim) and
  `findShown` uses ASCII `toLower`, while `--name` uses `foldText`: `--name ñuñoa` and `--edit Ñuñoa` match
  differently, and the numbering key can differ from the display key.
* `countries.nim ensureCountries` keeps one outline per ISO (`limit 1`): split or disputed countries lose
  parts.  Cells near a border are assigned by exact intersection with a generalised 1:50m outline, so a
  neighbour can be missed and its names never loaded.
* A route that fails to parse gives an empty path, then stored as "nothing near": a parsing bug would mark a
  climb unnameable for good.  Several `except ValueError: discard` drop bad rows silently.
* Corrupt FIT input can crash rather than raise `FitError`: a huge `date_time` overflows in `fromUnix` when
  `nch fit` prints it (a Defect; `raises: []` does not cover Defects).
* Chained FIT files keep the previous file's timestamp across a new header; a 0xFFFFFFFF timestamp is
  accepted; a compressed timestamp with no base aborts the file instead of warning.
* A component scale of 0 is not rejected (plain fields are); duplicate names in the profile silently overwrite.
* `bundle/unpack.nim` catches `Exception` (hides bugs); it and `serve/pages.nim` use a fixed `.part` name
  (two processes clash).
* The map request uses `bits` as typed, not re-encoded from the ids: two spellings, two cache files.
* `validModelName` allows `--`, which `isCacheFileName` rejects: `ff` fails for such a model.
* The token cookie has no `Max-Age`: bookmarks stop working when the browser closes (the docs say otherwise).
* `{{{style}}}` is raw JSON inside `<script>`: a `</script>` in the author's edited style breaks the page.
* `model/calc.nim:20-23`'s comment understates the hour-bucket error about 10x (0.3%, not 0.03%).
* The antimeridian is only half handled (BuildMbr boxes, projection, interpolation).  Low priority; document it.

## 4. Problems, by pattern

### 4.1 One fact, several copies

The pattern behind the author's enum question.  Nothing keeps the copies in step, and some have drifted.

* Command names: the `usage` text, the `dispatch` case, `commandNames` (already wrong: §3.1).
* Each command's options: the `Spec`, the hand-written `usage`, the validation code; for the web-able ones also
  `commandRules` (serve/request.nim) and `webQuery`.  Adding an option means editing up to five places.
* `cache/files.nim`: an enum with a doc comment per value **and** a parallel `kindHelp` array.  (`array[Kind,
  string]` checks the count; the keyed form `[ckDownloads: "...", ...]` also checks the order; better still,
  one table of records.)
* `BaseType` facts (size, signedness, invalid marker, name, FIT number by position only) in five `case`
  statements; `baseTypeOf` twice with different meanings; FIT type names compared as strings
  (`"date_time"`) though `TypeKind` has them.
* GeoNames feature codes (PPLQ/PPLW/PPLH, parks, hills) listed separately in `activity.destKind`,
  `activity.startText` and `climbpick.kindOf`: the naming rules can drift apart.
* The same function written several times: three route parsers (`work.parseLineString`, `duplicates.pathOf`,
  `naming.parseRoute`); two `num` helpers (attempts, report) plus `queryNumber` (ff); two or three table
  aligners; the SpatiaLite index sub-query in five places; `shape.nim:94-122` re-implements `geo.RouteGrid`;
  three hex checks; user lookup by name in `openStore`, `user/wipe.findUser`, `selection/command.userIdOf`;
  two near-identical Ctrl-C handlers (`ui/live`, `ui/interrupt`).
* Messages that hard-code the constants they describe ("80%", "25 m" in `duplicateLines`).
* CLAUDE.md and AGENTS.md are identical copies (both tracked).

### 4.2 Illegal states are representable

**Bags of booleans.**  `climbs/params.nim`: 14 bools, ~40 lines ruling out combinations by hand, then `run`
re-discovers the action with an `if` chain.  Ten commands have this shape (a `Params` with `problem: string`);
`ff` has a bag of output modes (`stdout`, `worker`, `serve`, `noOpen`...) with a `webProblem` to forbid
combinations.  The idiom (Nim, Rust, Haskell...) is **parse, don't validate**: parse into a variant object with
one branch per action, so an impossible combination cannot exist and `run` is a `case` the compiler checks:

```nim
type
  ClimbChange = enum ccRename, ccAuto, ccRetire, ccUnretire
  ClimbAction = enum caShow, caAll, caDelete, caEdit, caRetired, caDuplicates
  Climbs = object
    case action: ClimbAction
    of caShow:
      names: seq[string]
      verbose, everyone: bool
    of caDelete:
      force: bool
    of caEdit:
      climb: string
      change: ClimbChange
      newName: string     # used only when change is ccRename
    of caAll, caRetired, caDuplicates:
      discard
```

**Sentinels.**  `""` for success in every parser (`args.nim`, all `Params`); `""` for "no name" and for
unknown FIT names; `-1` for "no number" (`FieldValue.number`, `timestampField`); booleans read as `r[2] == "1"`;
a stored start place whose `"near "` prefix is both text and state (`nameFor` tests `startsWith("near ")`).
Use `Option`, enums, or a small `Result`.

### 4.3 The database layer stops halfway

* `db_connector` returns every value as a string: ~120 `parseInt`/`parseFloat` calls on database values, each
  with its own error handling (many `try/except` exist only for this); NULL arrives as `""`.
* Because reads cannot bind typed values, SQL is built by concatenation with hand quoting
  (`selection/criteria.nim`, `names/countries.nim`...).  Correct today, but it is what every reviewer checks,
  and TODO Task 10 item 6 dropped the fix as "a big change" because `Stmt` cannot read rows.
* `db/statement.nim` already wraps the C API for writes (and has `nextRow`, `blobAt`).  Adding typed column
  readers, a `rows` iterator and a `query` that fills a tuple (with `Option` for NULL) removes both problems.
  Alternative: the `tiny_sqlite` library; evaluate before choosing.
* Routes are read as WKT text (`AsText`) and parsed in Nim; read them as numbers or a blob.
* `bringUpToDate` carries dead paths (legacy checksums, the "older version" column check, `seed_version`,
  `reseed`, `withSeed`, used by nothing).  The fragment mechanism itself is good and stays.
* Accent-insensitive search builds globs like `*[tT]oyo*`; a Nim function registered in SQLite
  (`sqlite3_create_function`, `fold(name) like ?`) is simpler, bindable, and fixes the folding bug in §3.2.
* `InitSpatialMetadata(0, 'WGS84_ONLY')` would load the one coordinate system used, not all WGS84 ones.

### 4.4 Work that SQL should do

* `climbs/duplicates.nim duplicateGroups` compares every pair of climbs in Nim; the spatial index should give
  the candidate pairs.
* `climbs/attempts.nim summaries`: three queries per climb and the ranking in Nim; one query with
  `rank() over (...)`.  `map/command.nim climbsOf` is also a query per climb.
* `names featuresNear` pulls every feature in a box (streams, farms...) and filters in Nim; filter by class and
  order by distance in SQL.
* `countriesOfCell` inserts row by row without a transaction; one `insert ... select` does it.
* `ensureCells` unzips and parses the whole country file again for each new 1-degree cell.
* `missingCells` and `prepare` run a `count(*)` per cell or per country.

### 4.5 Sample storage

474 MB for 1112 activities: `coords` 263 MB (6.2 M rows), `route` 101 MB, `heartrate` 100 MB (6.1 M rows).

* `heartrate` repeats the `(activity_id, t)` key of `coords` for every second and costs a join.  The normal
  design is one `sample` table with the common FIT channels as nullable columns (§6).
* `route` is a second full copy of the positions.  It is needed for the spatial index but may not need every
  point: `ST_Simplify` at ~2-5 m could shrink it a lot without changing a "passes near" answer.  Measure.
* Bigger option, not recommended yet: one compressed blob of columns per activity instead of rows.

### 4.6 Module boundaries have drifted

* Directories do not match commands: `activities` is in `selection/`, `users` in `user/`.
* Shared code lives in whichever module needed it first: the delete countdown in `user/wipe.nim` (used by
  climbs, landmark, db, cache, delete), the time types in `fit/time.nim` (used by seven directories).
* Directory cycles: `fit ↔ profile` (one thing: merge); `climbs ↔ selection` (only `selection/fold.nim`, a
  leaf, plus `activities` using climbs for `--climb`); `names ↔ landmark` (no file cycle: names uses the
  landmark library, the landmark command uses names).  `activities` is a hub: it imports importer, delete,
  climbs and selection.
* `db/` (said to "know no module") has `command.nim`, importing `cli`, `download`, `user`.
* SQL strings read other modules' tables, which no import shows.

The fix is the package design (§6): declared dependencies, checked, and extension points instead of cycles.

### 4.7 Built bigger than needed

* `templating.nim` implements Mustache sections, inverted sections, lists and scopes; no template uses them.
  About 60 lines would do (a runtime engine is justified: the templates are edited in the cache).
* Two cache naming schemes (`ff` readable, `map` proquint) and two ways for the server to find the check;
  the proquint collision loop and the request stored in the file are more than 48 bits need.
* `fit/decode.nim decode` is ~180 lines with the plain/unknown dispatch written twice; `emitPlain` and
  `decodeField` take 12 parameters (a context object); plan building is written twice.
* `bundle/` (manifest, hash detection of the author's copy, NOTICE) costs more than the xlsx reader it
  serves; a plain `--profile PATH` might do.  (It is also the seed of the cache manifest, §6.)
* Dead or test-only code: `fit/basetype.decode/RawValues/checkBad`, `Tokenizer.bytes`, `readWorkbook`,
  `climbs/profile.smoothed/filtered`, `Effort.startElev/finishElev/finishDist` (always NaN in use).
* Legacy steps in fragments, for the next squash: `names/002-country-cells.sql`'s `update country set geom =
  null`, the back-fill in `climbs/002-name-number.sql`.  Stale comments (`nch sector`, "(n/m)", heatmap).

### 4.8 Housekeeping

* A compiled binary is tracked: `tests/delete/test_delete` (the `.gitignore` pattern `/tests/test_*` only
  matches the top level).  `tests/sector/` is an empty leftover.
* TODO.md is 2,758 lines, mostly history; its "Conventions" and "Code layout" describe commands that no longer
  exist (`import`, `list`, `destroy`, `heatmap`) and "one third-party dependency".  Sonnet reads it as current.
* Long, branchy `run` procs (follows from 4.2).

## 5. The author's questions

**Hand-written CLI parsing.**  Common in Nim, and 224 lines is not the problem; the problem is 4.1/4.2.
`std/parseopt` only tokenises; `cligen` builds the CLI from a proc signature, which fights the "one action per
call" shape; `confutils` (Status) is solid but heavy; `argparse` is Python-like.  For tab completion the
deciding fact is that the useful completions are **dynamic** (climb, user and model names, sports come from the
database), which no library does for you.  So: keep the parser, make the spec the single source (each option
carries its help text and the kind of value it completes), generate `usage` from it, parse into a variant
object, and add a hidden `nch __complete WORDS...` that a small bash/zsh function calls.

On libraries generally: use one when it does something hard and is maintained by an organisation or many
users (zippy, db_connector, checksums qualify); write it yourself when it is small and shapes the program (the
CLI).  The own xlsx reader is justified (runtime `--profile`, nothing suitable in Nim).

**The module model.**  The idea is sound, and the author's aim (a DAG of packages, third-party packages
dropped in) is achievable in Nim: see §6.

**Enum descriptions.**  See 4.1.  Sloppy, as suspected, and checkable by the compiler.

**Nim to JavaScript.**  No, for now.  The page is a template the author edits by hand, Leaflet is JavaScript,
and Nim's JS output is large and harder to debug.  It would pay only if real logic had to be shared between
server and browser.  The page's geometry code (offsets, smoothing, lanes) has no tests: if it grows, move it
to a `map-geometry.js` that can be tested under node.

**Macros.**  None is normal for an application; the 38 templates are used sensibly.  The idiom gaps are
elsewhere (4.2).  Otherwise the style is idiomatic Nim 2 (func/proc split, distinct types, destructors,
`lent`).  The comments are long and plain-English, consistently; much help text is repeated in comments.

**SQLite.**  Used well at the schema level (§2), weak at the access level (4.3, 4.4) and in sample storage
(4.5).  SpatiaLite's many tables are normal.

## 6. Packages (agreed in discussion, 2026-11-08)

The aim: packages declare their dependencies; the build enforces a DAG; a package sees a database that already
has the tables of everything it depends on, and calls its dependencies' code directly.  A third party adds a
package by dropping a directory in and rebuilding (source drop-in, as Caddy does).  Rejected: loading shared
libraries at run time (Nim has no stable ABI: fragile, and needs a rebuild anyway) and packages as separate
programs (more complex and slower; no function calls between packages).

### Framework and packages

* **The framework is minimal**: the `Package` type and the registry, the database handle and the fragment
  mechanism, and the types of the extension points.  Nothing else.  It is the interface packages are written
  against, so it changes carefully.
* **Everything else is a package**, including pure libraries (geo, templating, terminal output, time), the
  web server, the cache, `activities` and the importer.  Small packages, and packages with many dependencies,
  are fine: the cost is a `package.nim` each, which also documents the package.

```nim
# packages/climbs/package.nim
const package* = Package(
  name: "climbs",
  depends: @["sectors", "importer", "names"],
  fragments: @[fragment("001-schema.sql")],
  commands: @[climbsCommand],
)
```

* The registry is generated from the package directories (a macro or a nimble task) and sorted
  topologically; a cycle or a missing dependency fails the build.  It replaces `modules.nim`, `dispatch`,
  `commandNames` and the usage list.
* Tests: a package imports only from itself, the framework and its declared dependencies; the tables named in
  its SQL strings belong to the same set (approximate: table names from the fragments, matched in the code).

### Extension points

An early package defines an extension point; later packages fill it.  This is how cycles are avoided without
merging packages that should be separate.  Known so far:

* **import steps** (exists: heart rate): eager work on each imported activity;
* **on-demand activity work**: "each activity not yet done by version N of my method".  Today `climbs_done`
  and the impulses' "missing" query each do it by hand.  Derived data then never needs a migration: a change
  of method is a version bump and the work is redone;
* **activity criteria**: climbs adds `--climb` to `activities` (breaks `climbs ↔ selection`);
* **name sources, in priority order**: landmarks first, GeoNames after (breaks `names ↔ landmark`);
* **sector naming**: the package that made a sector says how it is named;
* **what will be deleted**: each package adds its line to the deletion message.

### Sectors

`sectors` becomes a package: the `sector` and `effort` tables, matching rides against sectors (most of
`match.nim`), retiring, duplicates, the kept numbering of shared names.  `climbs` depends on it: it detects
climbs, inserts them as sectors, and keeps `climb(sector_id, gain_m, gradient, category)` of its own.  A later
package that finds sectors by overlapping activities does the same with its own table.  No package alters
another's table.

### Samples

The importer owns the raw per-second data: one `sample` table with the common FIT channels (position,
altitude, heart rate, power, cadence, speed, temperature), nullable.  Packages own derived data.  This replaces
`coords` + `heartrate`; the heart-rate import step goes.

### Cache

A package near the bottom, not framework: packages write to it, the loader does not.  It grows the manifest
`bundle/unpack.nim` keeps today into one for every file (detect and warn of edited files), with an area per
package.

### Database versions (fragments) with packages

The current mechanism stays, per package (`package/NNN-name.sql`, as recorded now).  Added rules:

* A fragment touches only its own package's tables.  A table rebuild keeps whatever dependents refer to.
* A new database applies fragments in DAG order; an old one gets later fragments of an early package after the
  fragments of packages that depend on it.  **A test builds the database by several valid orders and compares
  the schemas** (tables, columns, indexes, foreign keys): this automates the comparison CLAUDE.md asks for by
  hand before a squash.
* Fragments are for imported and hand-entered data (users, landmarks, names given by hand, models); derived data
  uses the version bump of on-demand work instead.
* A database with fragments from a package this build lacks is refused, naming the package ("this database has
  tables from package X, which this build does not include").  `nch db --drop PACKAGE` can come later.
* Squashing: as now, until anyone else has a database (a release: tie this to the version rules still open
  from Task 11).  After that, if the fragment lists grow long, the route is a per-package **baseline** (a
  squashed `001` for new databases, the old fragments kept for existing ones, the schema test proving both give
  the same result).  Not built now.

## 7. Plan (for Sonnet; each step one or more commits, tests passing, discuss before starting)

Cheap and safe first; each later step is easier because of the earlier ones.

1. **Housekeeping.**  Untrack `tests/delete/test_delete`, fix `.gitignore` (`/tests/**/test_*` with `!*.nim`),
   remove `tests/sector/`, make AGENTS.md a symlink to CLAUDE.md, add `landmarks` to `commandNames` (the
   registry replaces it later).
2. **The checked bugs (§3.1)**, each with a test that fails first: climbs per timer segment; cap the country
   fallback; index `effort(activity_id)`; the server reads both pipes, times out and kills, and does not block
   on one request; the map cache key covers what the map shows (or the file is always remade: measure first);
   FIT bool invalid marker; cap the inflated zip size.
3. **The reported bugs (§3.2)**: confirm each with a test; fix the real ones, report the rest.
4. **Prune TODO.md.**  Finished tasks out (git has them); rewrite conventions and code layout to match the code
   (or move them to CLAUDE.md); TODO.md holds open work only.
5. **Dead code**: the dead paths in `bringUpToDate`/`fragment.nim` (not the fragment mechanism), and the dead
   and test-only code of 4.7.
6. **Typed database access.**  First half a day evaluating `tiny_sqlite` against extending `db/statement.nim`;
   report back.  Then typed reads, bound parameters everywhere (SpatiaLite then gets real numbers), one user
   lookup, a registered `fold()` SQL function; convert module by module.
7. **Packages (§6)**:
   1. move shared code into packages of its own (time, the delete countdown, text folding, geo...); merge
      `fit` and `profile`;
   2. the framework: `Package`, the generated registry, the topological sort; fragments in DAG order; the
      "missing package" refusal (rebuild the database);
   3. a `package.nim` in each directory;
   4. the import and SQL-table tests;
   5. the extension points, one commit each, each discussed first (on-demand activity work, activity
      criteria, name sources, deletion lines); the cycles go;
   6. the schema-by-several-orders test.
8. **Options carry their help; parse into variants.**  `Opt` gets `help`, `metavar` and a completion kind;
   usage is generated from the spec (prose before and after stays hand-written); the web options come from
   the same spec.  `climbs` first, shown to the author, then the others (`ff`'s output mode as an enum).
   Errors as `Option[string]`, not "".
9. **Tab completion**: `nch __complete` and a bash function; dynamic values from the database.
10. **One owner per fact** (the rest of 4.1): GeoNames codes in one place, `BaseType` facts in one table,
    the duplicated helpers merged, messages built from the constants.
11. **Push work into SQL** (4.4), measuring before and after.
12. **Shrink** (4.7): templating to what is used; one cache naming scheme; `decode` dispatch written once.
13. **Larger changes, each discussed first**: the `sectors` split; the `sample` table (measure size and the
    import, climbs and map times before and after; then a simplified `route`); the cache manifest.

## 8. Proposed additions to CLAUDE.md

```markdown
## guidelines for writing code (from the review of 2026-11-08)

* **one fact, one place.**  a list of names, options, kinds or help texts is written once and everything
  else is made from it (a table indexed by an enum, generated usage).  never keep two lists in step by hand.
* **parse, don't validate.**  input (the command line, rows from the database, files) is turned into a type
  that can only hold valid values (variant objects, enums, distinct types, `Option`).  no bags of booleans
  checked afterwards; no "" or -1 meaning "none" or "ok".
* **revisit, don't pile on.**  when a new feature fits badly on what exists, change what exists (within the
  package rules: a package never alters another's tables).  say so in the discussion rather than working round it.
* **packages declare what they use.**  a package imports only its declared dependencies (checked by a test);
  shared code is a package of its own, not part of the module that needed it first.  an early package that
  must be extended offers an extension point rather than importing the later one.
* **let the database do database work.**  values are bound, never put into sql text; rows are read into typed
  tuples or objects; filtering, joining, ranking and spatial search are sql, not loops in nim.
* **delete dead code and stale docs in the same commit** that makes them dead.  TODO.md holds open work only;
  conventions live here and must describe the code as it is.
* **before finishing a step**, check what else refers to what you changed (grep the names): lists, help text,
  docs, tests.
```
