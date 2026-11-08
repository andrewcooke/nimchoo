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
AI-written increments, each correct, none revisiting the whole.  There are also real bugs (§3), each an instance of a missing abstraction.

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

## 3. Bugs, and the missing abstractions behind them

These were found by reading part of the code; there will be more of the same kinds.  Each bug is an instance of
a class, and the class is a missing abstraction (a common idea with no single home).  So the fix is the
abstraction, plus a test that would catch the next instance; the known bugs are its first cases.  The classes
are lettered so that the plan (§7) can refer to them.

### 3.1 Checked (confirmed in the code)

**A. The structure of an activity's track is left to each consumer.**  `climbs/work.nim:204-233` builds one
profile from every point, though `buildProfile` (profile.nim:76) says its input is one timer segment: a ride
with the timer stopped while the rider is moved (car, train) gets the gap as road (invented climbs, efforts
across the gap; a café stop is harmless).  *Fix:* one loader that returns a track as its segments, so a
consumer cannot ignore them; check the other consumers (impulses, names, map) against it.

**B. Noisy input reaches every consumer, and work grows with it unbounded.**  One bad GPS fix makes a box of
more than 4000 cells, and `names/lookup.nim:66` falls back to `allCountries()`: every country's GeoNames file
is downloaded (~250 zips).  *Fix:* explicit limits wherever work fans out (downloads, cells, sizes), refusing
with a message; later, cleaning at import (outlier positions, impossible jumps) in one place, with the per-activity
arrays.

**C. Queries are not checked against the schema.**  No index on `effort(activity_id)`: deleting activities and
`activity_id in (...)` scan the table.  SQLite does not index foreign keys by itself.  *Fix:* a test that every
foreign-key column has an index (`pragma foreign_key_list`, `index_list`); once queries go through the typed
layer, a test that runs `explain query plan` on them and flags scans of big tables.

**D. Running a child process.**  `serve/server.nim:19-21` reads all of stdout, then all of stderr, then waits
with a timeout: a hung worker is never timed out or killed, and one that fills the stderr pipe deadlocks.  The
server is single-threaded, so one slow `map` blocks every request.  *Fix:* one helper that runs a child (both
outputs read at once, a timeout, kill); the server stops blocking on one request.

**E. Cache keys that do not cover all the inputs.**  `map/command.nim:186-188` reuses an existing file; the
key covers the activities only, so a renamed climb or a changed detector keeps the old map until the cache is
deleted.  `ff` does it right (`inputKey`).  *Fix:* one cache interface: a cached file is keyed by the inputs
its maker declares (the data and the versions of the methods).  It belongs to the cache package (§6) and ties
to the versions of on-demand work.

**F. One fact in several places.**  `commandNames` (cli/common.nim) lists `import` (gone) and lacks
`landmarks`, so `landmarks` runs are not logged.  *Fix:* the registry (§6); more generally 4.1.

**G. Facts about each FIT base type spread over `case` statements.**  A bool's invalid marker (0xFF) reads as
true (`fit/decode.nim:124-127`); every other type drops invalid values.  *Fix:* one table of base-type facts,
the invalid check applied to every type before it is interpreted.

**H. Limits checked against what a file claims, not what it does.**  `zipbytes.nim:60` checks the declared
size, inflates everything, and compares afterwards.  Low risk (GeoNames, the profile).  *Fix:* the rule that a
limit applies to what is actually read; here, cap the inflated output.

### 3.2 Reported, not yet checked (confirm each with a test before fixing)

* **I. Text compared in different ways.**  SQL `lower()`/`trim()` are ASCII-only (ordinal.nim, landmarks.nim,
  suggest.nim) and `findShown` uses ASCII `toLower`, while `--name` uses `foldText`: `--name ñuñoa` and `--edit
  Ñuñoa` match differently, and the numbering key can differ from the display key.  *Fix:* one fold function,
  registered in SQLite, used everywhere.
* **J. Failures that become data.**  A route that fails to parse gives an empty path, then stored as "nothing
  near": a parsing bug would mark a climb unnameable for good.  Several `except ValueError: discard` drop bad rows.
  *Fix:* the rule that a failure is never stored as a result (raise, or warn and leave the row undone).
* **K. Writing files.**  `bundle/unpack.nim` and `serve/pages.nim` use a fixed `.part` name (two processes
  clash); `unpack.nim` catches `Exception` (hides bugs).  *Fix:* one atomic-write helper with a unique temporary
  name (one exists in serve: use it everywhere).
* **L. Corrupt input reaching a Defect.**  A huge `date_time` overflows in `fromUnix` when `nch fit` prints it
  (`raises: []` does not cover Defects).  Chained FIT files keep the previous file's timestamp; a 0xFFFFFFFF
  timestamp is accepted; a compressed timestamp with no base aborts the file instead of warning; a component
  scale of 0 is not rejected; duplicate names in the profile silently overwrite.  *Fix:* fuzzing (3.3), then
  each case.
* Geography: `countries.nim ensureCountries` keeps one outline per ISO (`limit 1`), so split or disputed
  countries lose parts; cells near a border are assigned by exact intersection with a generalised 1:50m
  outline, so a neighbour can be missed.  The antimeridian is only half handled (low priority; document it).
* Validators that disagree (F/I again): `validModelName` allows `--`, which `isCacheFileName` rejects, so `ff`
  fails for such a model; the map request uses `bits` as typed, not re-encoded from the ids (two spellings,
  two cache files).
* Smaller: the token cookie has no `Max-Age` (bookmarks stop working when the browser closes, though the docs
  say otherwise); `{{{style}}}` is raw JSON inside `<script>` (a `</script>` in the edited style breaks the
  page); `model/calc.nim:20-23`'s comment understates the hour-bucket error about 10x (0.3%, not 0.03%).

### 3.3 Finding more

* **Fuzz the FIT decoder**: mutate real FIT files at random; the result must be success or a `FitError`,
  never a Defect.  Cheap, and it tests L directly.
* **Invariant checks on real data**, run over the author's database as well as test data: every effort lies
  within one timer segment; every activity's samples are in time order; every climb has a name decision; and so on.
* **Schema tests** (C): an index for every foreign key; no scans of big tables in the program's queries.

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

* The cost is **a row per second**, not the number of tables: `heartrate` is ~16 bytes per reading, mostly the
  repeated `(activity_id, t)` key and its index; the value is one byte.
* Every read of `coords` and `heartrate` is "all of one activity, in time order" (`climbs/work.nim:92`,
  `importer/naming.nim:54`, `model/impulses.nim:26`) or "has it any" (`model/impulses.nim:73,111`,
  `selection/criteria.nim:611,613`).  Nothing filters, sorts or aggregates single samples in SQL.
* So per-second data should be **one row per activity, holding arrays** (§6): heart rate ~6 MB instead of 100,
  read in one go.  The cost: an array is opaque to SQL (nothing needs that today; a package that ever does can
  keep a row table of its own).
* `route` is a second full copy of the positions.  It is needed for the spatial index but may not need every
  point: `ST_Simplify` at ~2-5 m could shrink it a lot without changing a "passes near" answer.  Measure.

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
* (done 2026-11-08: TODO.md is open work, history in HISTORY.md, conventions in CLAUDE.md.)  It was 2,758 lines, mostly history; its "Conventions" and "Code layout" describe commands that no longer
  exist (`import`, `list`, `destroy`, `heatmap`) and "one third-party dependency".  Sonnet reads it as current.
* Long, branchy `run` procs (follows from 4.2).

## 5. The author's questions

**Hand-written CLI parsing.**  Common in Nim, and 224 lines is not the problem; the problem is 4.1/4.2.
`std/parseopt` only tokenises; `cligen` builds the CLI from a proc signature, which fights the "one action per
call" shape; `confutils` (Status) is solid but heavy; `argparse` is Python-like.  For tab completion the
deciding fact is that the useful completions are **dynamic** (climb, user and model names, sports come from the
database), which no library does for you.  So: keep the parser, make the spec the single source (each option
carries its help text and the kind of value it completes), generate `usage` from it, parse into a variant
object, and add a hidden `nch __complete WORDS...` that a small bash/zsh function calls.  With packages (§6) each
package registers its commands and options, so completion reads them from the registry.

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

Per-second data is stored **per activity, as arrays**: one row per activity in a table per channel (or group of
channels), not one row per second.  Under this rule a table per package costs almost nothing, so pluggability
and efficiency agree:

```sql
create table heartrate (
  activity_id integer primary key references activity(id) on delete cascade,
  t0 integer not null,     -- time of the first reading
  bpm blob not null        -- one byte per second; 0: no reading
) strict;
```

* The importer owns time, position and altitude (one table, arrays per activity; the timer segments with them).
* Other channels belong to the package that wants them, taken from the FIT file by an import step (the
  extension point that exists): heart rate stays a package of its own.
* The spatial queries are unaffected: they use `route` and `activity.start`.
* The encoding (plain fixed-width numbers, or compressed with zippy) is decided by measuring; plain first.
* **Defaults** (an alternative needs a reason, given when it is discussed):
  * **refer to samples by time, never by array index** (an index is tied to one encoding; a time is not);
  * **arrays are immutable once written**: cleaning happens before the write; a change to cleaning is a re-import
    (the cascade takes the derived data) or a version bump of the on-demand work;
  * **what SQL cannot check, a test checks**: the invariant checks (§3.3: every effort within one timer
    segment...), run over the author's database too.  Storing a row of arrays per timer segment, rather than per
    activity, would also let a trigger check that an effort lies inside one: to decide at that step.

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

Cheap and safe first; each later step is easier because of the earlier ones.  Letters refer to the classes of §3.

**Mechanical or design.**  Steps marked *(mechanical)* change no behaviour or design the author sees: they can be
approved together and done without a discussion each (the tests are the check).  The others need a discussion
before they start.  Mechanical: 1, 2 (writing the tests; what they find is reported), 4 (confirming), 5, 6, 8.1,
8.3, 8.4, 8.6, 11, 13 (except the cache naming scheme).  Design: 3, 7, 8.2, 8.5, 9, 10, 12 (each change is
measured and shown), 14.

**Order.**  Packages (8) come before the options rewrite (9) so that each command is rewritten once, in its final
home.  Nothing new for the author to use appears until about step 10; open features (TODO.md) can go in after step
3 or step 8, not before 3 (they would build on code with known bugs).

1. *(mechanical)* **Housekeeping.**  Untrack `tests/delete/test_delete`, fix `.gitignore` (`/tests/**/test_*` with `!*.nim`),
   remove `tests/sector/`, add `landmarks` to `commandNames` (F; the
   registry replaces it later).
2. *(mechanical)* **Tests that find bugs** (3.3): the FIT fuzzer, the foreign-key index test, the invariant checks (with a way
   to run them over the author's database).  Report what they find before fixing it.
3. **Fix the classes**, each as the abstraction, a test for the class, and the known bugs as its first cases:
   A (the track loader; climbs per segment; check the other consumers), B (limits where work fans out; the
   country fallback), C (the indexes the test asks for), D (the child-process helper; the server), E (the
   cache interface; the map key), G (the base-type table; the bool marker), H (the zip cap), J (no failure
   stored as a result), K (one atomic write), L (what the fuzzer finds).  I waits for step 7.
   The track loader (A) is built over today's `coords`; step 14 changes the storage, and then only the loader
   changes.
4. *(mechanical)* **The other reported bugs (3.2)**: confirm each with a test; fix the real ones, report the rest.
5. *(mechanical)* **Check the conventions** now in CLAUDE.md against the code.  (TODO.md was pruned to open work and its
   history moved to HISTORY.md on 2026-11-08; the conventions moved to CLAUDE.md, corrected by hand.)
6. *(mechanical)* **Dead code**: the dead paths in `bringUpToDate`/`fragment.nim` (not the fragment mechanism), and the dead
   and test-only code of 4.7.
7. **Typed database access.**  First half a day evaluating `tiny_sqlite` against extending `db/statement.nim`;
   report back.  Then typed reads, bound parameters everywhere (SpatiaLite then gets real numbers), one user
   lookup, the registered `fold()` SQL function (I); convert module by module; then the query-plan test (C).
8. **Packages (§6)**:
   1. *(mechanical)* move shared code into packages of its own (time, the delete countdown, text folding, geo...); merge
      `fit` and `profile`;
   2. the framework: `Package`, the generated registry (F), the topological sort; fragments in DAG order; the
      "missing package" refusal (rebuild the database);
   3. *(mechanical)* a `package.nim` in each directory, with the package's own doc (the feature detail now in CLAUDE.md
      moves there); the track loader lands in the importer package, the cache interface in
      the cache package;
   4. *(mechanical)* the import and SQL-table tests;
   5. the extension points, one commit each, each discussed first (on-demand activity work, activity
      criteria, name sources, deletion lines); the cycles go;
   6. *(mechanical)* the schema-by-several-orders test.
9. **Options carry their help; parse into variants.**  `Opt` gets `help`, `metavar` and a completion kind;
   usage is generated from the spec (prose before and after stays hand-written); the web options come from
   the same spec.  `climbs` first, shown to the author, then the others (`ff`'s output mode as an enum).
   Errors as `Option[string]`, not "".
10. **Tab completion**: `nch __complete` and a bash function; commands and options from the registry, dynamic
    values from the database.
11. *(mechanical)* **One owner per fact** (the rest of 4.1): GeoNames codes in one place, the duplicated helpers merged,
    messages built from the constants.
12. **Push work into SQL** (4.4), measuring before and after.
13. *(mechanical, but the cache naming scheme is design)* **Shrink** (4.7): templating to what is used; one cache naming scheme; `decode` dispatch written once.
14. **Larger changes, each discussed first**: the `sectors` split; per-activity arrays for the per-second data, with
    cleaning at import (B; measure size and the import, climbs and map times before and after; then a simplified
    `route`); the
    cache manifest.

## 8. Proposed additions to CLAUDE.md

(Added to CLAUDE.md on 2026-11-08, with changes: "revisit, don't pile on" and "before finishing a step" became
working practice; "a missing abstraction is the bug" and "a failure is never stored as a result" were added.
CLAUDE.md is the current text.)

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

## 9. For the author

From the record the work left (CLAUDE.md, TODO.md, the commits, the code), not from the conversations.

1. **Specify what, not how.**  Be exact about what you see (output, behaviour, limits); leave the mechanism open.
   At design points ask Sonnet for two or three options and a recommendation rather than giving it the design.
2. **Review shapes, not lines.**  When a change comes back, look at the new types, signatures, schema and module
   dependencies: that is where drift starts, and it is quicker to read than the code.
3. **Hold whole-system reviews**, like this one, at each milestone (or every several features) and before a
   squash, in a fresh session and ideally another model, so that the reviewer is not anchored on the author's
   reasoning.  Each step can be right while the whole drifts; only a whole-system look catches that.
4. **Give permission to revisit.**  "No past to protect" applies to code too: when a feature fits badly, Sonnet
   should say so and propose changing what exists.
5. **CLAUDE.md for rules, not records.**  It is loaded every session; detailed design of particular features
   (climb subscripts, map styling, cache names) pushes Sonnet towards local consistency over overall design.
   With packages, that detail moves to each package's doc.
6. **TODO.md for open work only.**  History is in git (and HISTORY.md); a stale document is read as current.
7. **Make "done" explicit**: tests (with one for the class of bug), docs updated, dead code deleted, references
   checked.
8. **Ask for evidence**: a measurement, or before-and-after examples where there is no ground truth.

Items 1, 4, 6 and 7 are now in CLAUDE.md as working practice; 3 is there as "suggest a review"; 5 is plan step 8.
