# nimchoo: code review (2026-11-08)

Scope: read the dispatcher, the CLI parser, the db layer and every SQL fragment, climbs (command, params,
detect), the activities command and its criteria, the importer pool, the server handler, a sample of tests,
TODO.md's conventions; measured the import graph and the real database (read-only).  ~18k lines of source,
1159 tests, all passing (`nimble test`, 2026-11-08).  Not read line by line: fit/, profile/, xlsx, names/, ff/, map/.

## 1. Summary

The code is **competent and careful, but it is "locally good, globally drifting"**.  Individual functions are
clear, pure where they can be, well commented and well tested; the error discipline (`{.push raises: [].}`
everywhere, checked by the compiler) is stricter than most Nim.  What is weak is the layer above the
functions: the same fact is written in several places that nothing keeps in step, module boundaries no
longer match what the modules do, and the database layer stops halfway (typed writes, string reads).  These
are the typical results of many small AI-written increments, each correct, none revisiting the whole.

## 2. Good

* **Error handling**: four kinds of failure, one mechanism each; `raises` is compiler-checked; commands return
  exit codes and never leak traces for expected errors.
* **Schema**: `strict` tables, `without rowid` where it pays, `on delete cascade` from user down, spatial
  indexes, fragments with checksums and transactional application.  WAL, `synchronous=normal`, incremental
  vacuum: all appropriate.
* **Algorithms**: `climbs/detect.nim` is a clean pure port; distinct types for `FitTime`/`UnixTime` and the ids.
* **Tests**: real databases in temp dirs, error paths tested, `offline: true` enforced, a structure test.
* **The web server**: token, Host check, CSP, no shell.  Safe for a local tool.
* **Dependencies**: few and sensible (zippy, db_connector, checksums).

## 3. Problems, most important first

### 3.1 One fact, several copies (the pattern behind your enum question)

* Command names: `usage` text, `dispatch` case, `commandNames` (cli/common.nim).  **Already out of step**:
  `commandNames` lists `import` (gone) and lacks `landmarks`, so `landmarks` runs are never logged.
* Each command's options: the `Spec`, the hand-written `usage` text, and the validation code.
* `cache/files.nim`: an enum with a doc comment per value **and** a parallel `kindHelp` array.
  (`array[Kind, string]` does check the count; the keyed form `[ckDownloads: "...", ...]` also checks the
  order.  Better still: one table of records.)
* Looking up a user by name: `openStore`, `user/wipe.findUser`, `selection/command.userIdOf`.
* CLAUDE.md and AGENTS.md are identical copies (both tracked).

### 3.2 Command-line parameters are bags of booleans

`climbs/params.nim`: 14 bools, then ~40 lines that rule out combinations by hand ("--rename, --auto ... cannot
be used together"), then `run` re-discovers the action with an `if` chain.  Ten commands have this shape (a
`Params` with `problem: string`).  The idiom (in Nim, Rust, Haskell...) is **parse, don't validate**: parse into
a variant object with one branch per action, so an impossible combination cannot exist and `run` is a `case`
the compiler checks for exhaustiveness:

```nim
type
  ClimbChange = enum ccRename, ccAuto, ccRetire, ccUnretire
  ClimbAction = enum caShow, caAll, caDelete, caEdit, caRetired, caDuplicates
  Climbs = object
    case action: ClimbAction
    of caShow: names: seq[string]; verbose, everyone: bool
    of caDelete: force: bool
    of caEdit: climb: string; change: ClimbChange; newName: string
    of caAll, caRetired, caDuplicates: discard
```

Also: errors returned as strings with `""` meaning success (in `args.nim` and every `Params`).  Unidiomatic
and easy to get wrong; use `Option[string]`, or a small `Result`.

### 3.3 The database layer stops halfway

* `db_connector` returns every value as a string: ~120 `parseInt`/`parseFloat` calls on database values, each
  with its own error handling.
* Because reads cannot bind typed values, SQL is built by concatenation with hand quoting
  (`selection/criteria.nim`).  It is correct today (quotes are doubled), but it is the thing every reviewer
  checks, and TODO Task 10 item 6 dropped the fix as "a big change" because `Stmt` cannot read rows.
* `db/statement.nim` already wraps the C API for writes.  Adding `columnInt/columnFloat/columnText`, a `rows`
  iterator and a `query[T]` that fills a tuple would remove both problems.  Alternative: the `tiny_sqlite`
  library (typed binds and reads, statement cache); evaluate before choosing (see the libraries rule).
* `bringUpToDate` still carries legacy paths (`legacySums`, the "older version" column check, `seed_version`,
  `reseed`, `withSeed`, used by nothing).  The project's own rule ("no past to protect") says delete them.

### 3.4 Storage of samples

474 MB for 1112 activities: `coords` 263 MB (6.2 M rows), `route` 101 MB, `heartrate` 100 MB (6.1 M rows).

* `heartrate` duplicates the `(activity_id, t)` key of `coords` per second and costs a join.  Your instinct is
  right: one `sample` table (`activity_id, t, lon, lat, alt, hr`, position columns nullable for indoor
  rides) is the normal design.  Fields added later by a module are new nullable columns
  (`alter table sample add column power`), which keeps the module idea without a table per field.
* `route` is a second full copy of the positions.  It is needed for the spatial index, but it may not need
  every point: `ST_Simplify` at ~2-5 m would shrink it a lot without changing any "passes near" answer.  Measure.
* Bigger option, for discussion only: one compressed blob of columns per activity instead of rows (5-10x
  smaller, faster to read whole), at the cost of SQL over individual points.  Nothing seems to query single
  points, but this is a larger change; not recommended yet.

### 3.5 Module boundaries have drifted

The idea (a directory per concept, later ones build on earlier ones) is sound for this size of program.  But:

* Directories do not match commands: `activities` lives in `selection/`, `users` in `user/`, `landmarks` in
  `landmark/`, `models` in `model/`.
* Shared utilities live in whichever module needed them first: the delete countdown and "would delete"
  wording are in `user/wipe.nim`, used by climbs, landmark, db; general time types are in `fit/time.nim`.
* Cycles between directories: `climbs ↔ selection`, `names ↔ landmark`, `landmark → climbs → names`.
  Nim allows this (files do not cycle) but it means "independent chunk" no longer holds.
* `db/` (said to "know no module") has `command.nim`, importing `cli`, `download`, `user`.
* The incremental rule leaks into the data (the heartrate table).  Building incrementally is fine;
  **never revisiting** earlier modules is not.  A new module may change an older one's schema with its own
  fragment.

Standalone programs per command would not help: they would all link the same library and open the same
database, so the coupling is the same and the build is slower.  If outside extension is ever wanted, the
cheap path is git-style: `nch foo` runs `nch-foo` on the PATH when `foo` is not built in.  Not needed now.

### 3.6 Housekeeping

* A compiled binary is tracked: `tests/delete/test_delete` (the `.gitignore` pattern `/tests/test_*` only
  matches the top level).  `tests/sector/` is an empty leftover.
* TODO.md is 2,758 lines, mostly history; its "Conventions" and "Code layout" sections describe commands
  that no longer exist (`import`, `list`, `destroy`, `heatmap`) and "one third-party dependency".  Sonnet
  reads this as current guidance.
* `run` procs are long and branchy (follows from 3.2).

## 4. Your questions

**Hand-written CLI parsing.**  Common in Nim, and 224 lines is not the problem; the problem is 3.1/3.2.
The libraries: `std/parseopt` only tokenises; `cligen` (mature, popular) builds the CLI from a proc
signature, which fits flat commands badly and fights the "one action per call" shape; `confutils` (Status)
is solid but heavy; `argparse` is Python-like.  For tab completion the deciding fact is that the useful
completions are **dynamic** (climb names, user names, model names, sports come from the database), which no
library does for you.  So: keep the parser, make the spec the single source (each option carries its help
text and what kind of value it completes), generate `usage` from it, parse into a variant object, and add a
hidden `nch __complete WORDS...` that a tiny bash/zsh function calls (the cobra/clap "dynamic completion"
model).

On third-party libraries generally: use one when it does something hard and is maintained by an
organisation or many users (zippy, db_connector, checksums all qualify); write it yourself when it is small
and central to the program's shape (the CLI).

**The module model.**  See 3.5.  Keep it, with three changes: write down the layers and check them with a
test (like `test_structure.nim` does for commands); move shared code to the layer it belongs to; let a new
module alter older modules' schemas when that gives the better design.

**Enum descriptions.**  See 3.1.  You were right that it is sloppy; it is also checkable by the compiler.

**Nim to JavaScript.**  No, for now.  The page is a template the author edits by hand in the cache, Leaflet is
JavaScript, and Nim's JS output is large and harder to debug.  It would pay only if real logic had to be
shared between server and browser (the bit-string decoding, the lane geometry).  Revisit if the browser
side grows past a few hundred lines.

**Macros.**  Zero macros is fine and normal for an application; templates (38) are used sensibly.  The
idiom gaps are elsewhere: variant objects for "one of several", typed results instead of strings, and
`Option`/`Result` instead of "" sentinels.  The style is otherwise idiomatic Nim 2 (func/proc split,
distinct types, destructors, `lent`).  The comments are unusually long and plain-English; that is your
style and it is consistent, but much of the help text is also repeated in comments.

**SQLite.**  Used well at the schema level (3.2's list).  Weak at the access level (3.3) and in sample
storage (3.4).  SpatiaLite's tables are normal; `InitSpatialMetadata(0, 'WGS84_ONLY')` would load only the
one coordinate system used instead of all WGS84 ones (fewer rows, same tables).  The accent-insensitive
search builds globs like `*[tT]oyo*`; registering a Nim function in SQLite (`sqlite3_create_function`,
`fold(name) like ?`) would be simpler and bindable.

## 5. Plan (for Sonnet; each step one commit, tests passing, discuss before starting)

Ordered so that the cheap, safe ones go first and each later step is easier because of the earlier.

1. **Housekeeping.**  Untrack `tests/delete/test_delete`, fix `.gitignore` (`/tests/**/test_*` with
   `!*.nim`), remove `tests/sector/`.  Make AGENTS.md a symlink to CLAUDE.md.
2. **Command registry.**  One `const commands: array[Command, CommandInfo]` (name, one-line help, `run`)
   in `nch.nim`; dispatch, the usage list and the log's list of names come from it.  Fixes the
   `landmarks`/`import` bug.  `cache/files.nim`: one table for kinds and help.
3. **Prune TODO.md.**  Move finished tasks to `HISTORY.md` (or delete: git has them); rewrite the
   conventions and code layout to match the code; keep TODO.md to open work.
4. **Typed database reads.**  Extend `db/statement.nim`: column readers, a `rows` iterator, `query`/`value`
   helpers returning typed tuples and `Option` for NULL; bound parameters everywhere (SpatiaLite then gets
   real numbers).  Convert module by module; delete the `parseInt` sites and hand quoting.  One user lookup.
   (First: half a day evaluating `tiny_sqlite` against this; report back.)
5. **Remove dead paths in the schema check** (`db/store.nim` `bringUpToDate`, `db/fragment.nim`): the legacy
   checksums, the "older version" column check, `seed_version`/`reseed`/`withSeed`.  **The fragment mechanism itself
   (numbered SQL files, checksums, append-only, squashing) is good and stays.**
6. **Options carry their help; parse into variants.**  Add `help`, `metavar` and a completion kind to `Opt`;
   generate usage from the spec (prose before/after stays hand-written).  Convert `climbs` first as the
   example, show it to the author, then the others.  Errors as `Option[string]`, not "".
7. **Tab completion.**  `nch __complete` + a bash function; dynamic values from the database.
8. **Layers.**  Write the intended layers in CLAUDE.md, add a test that checks directory imports against
   them, and move code to fit: the delete countdown to `ui/`, time types to `time.nim`, `db/command.nim` out
   of `db/`, break the `climbs ↔ selection` and `names ↔ landmark` cycles (probably by moving the shared
   pieces down).  Consider renaming `selection/` to `activities/` so directories match commands.
9. **Samples table** (needs a squash/rebuild; discuss first): `coords` + `heartrate` -> `sample`; measure size
   and the import, climbs and map times before and after.  Then measure a simplified `route`.

## 6. Proposed additions to CLAUDE.md

```markdown
## guidelines for writing code (from the review of 2026-11-08)

* **one fact, one place.**  a list of names, options, kinds or help texts is written once and everything
  else is made from it (a table indexed by an enum, generated usage).  never keep two lists in step by hand.
* **parse, don't validate.**  input (the command line, rows from the database, files) is turned into a type
  that can only hold valid values (variant objects, enums, distinct types, `Option`).  no bags of booleans
  checked afterwards; no "" or -1 meaning "none" or "ok".
* **revisit, don't pile on.**  when a new feature fits badly on what exists, change what exists (a new
  fragment may alter another module's table; a helper moves to the layer it belongs to).  say so in the
  discussion rather than working round it.
* **respect the layers** (base -> data -> derived -> presentation -> commands; checked by a test).  shared code
  lives in the lowest layer that needs it, not in the module that needed it first.
* **database access is typed**: values are bound, never put into sql text; rows are read into typed
  tuples or objects.
* **delete dead code and stale docs in the same commit** that makes them dead.  TODO.md holds open work only;
  conventions live here and must describe the code as it is.
* **before finishing a step**, check what else refers to what you changed (grep the names): lists, help text,
  docs, tests.
```

## 7. Second pass: names, landmarks, downloads, the rest of climbs (subagent review, key claims checked)

Correctness (checked by hand):
* **Climbs ignore timer segments.**  `climbs/work.nim:204-233` builds one profile from every point of the
  activity, though `buildProfile` (profile.nim:76) says its input is one timer segment and the `segment`
  table exists.  A ride with the timer stopped while the rider is moved (a car, a train) gets the gap as
  road: invented climbs, efforts across the gap.  A café stop is harmless.
* **One bad GPS fix can fetch every country**: `names/lookup.nim:66` falls back to `allCountries()` when the
  box has more than 4000 cells, and every country's GeoNames file is then downloaded (~250 zips).
* **No index on `effort(activity_id)`**: deleting activities and `activity_id in (...)` scan the table.

Correctness (reported, not yet checked):
* Case folding disagrees: SQL `lower()`/`trim()` are ASCII-only (ordinal.nim, landmarks.nim, suggest.nim) and
  `findShown` uses ASCII `toLower`, while `--name` uses `foldText`; so `--name ñuñoa` and `--edit Ñuñoa` match
  differently, and the numbering key can differ from the display key.
* `countries.nim ensureCountries` keeps `limit 1` outline per ISO (split or disputed countries lose parts;
  `ST_Union` would keep them); cells near a border are assigned by exact intersection with a generalised
  1:50m outline, so a neighbour can be missed and its names never loaded.
* A route that fails to parse gives an empty path, which is then stored as "nothing near": a parsing bug would
  mark a climb unnameable for good.  Several `except ValueError: discard` drop bad rows silently.
* Antimeridian is only half handled (BuildMbr boxes, projection, interpolation).  Low priority; document it.

Efficiency (SQL should do it):
* `duplicates.nim duplicateGroups` compares every pair of climbs in Nim; the spatial index should give the
  candidate pairs.
* `attempts.nim summaries`: three queries per climb and the ranking in Nim; one query with `rank() over`.
* `featuresNear` pulls every feature in a box (streams, farms...) and filters in Nim; filter by class and
  order by distance in SQL.  `countriesOfCell` inserts row by row without a transaction.
* `ensureCells` unzips and parses the whole country file again for each new 1-degree cell.
* Routes are read as WKT text (`AsText`) and parsed by three copies of the same parser
  (`work.parseLineString`, `duplicates.pathOf`, `naming.parseRoute`).

Duplication and dead code:
* GeoNames feature codes (PPLQ/PPLW/PPLH, parks, hills) are listed separately in `activity.destKind`,
  `activity.startText` and `climbpick.kindOf`: one `names/codes.nim` should own what a code means.
* `shape.nim:94-122` re-implements `geo.RouteGrid`.  `num` is in attempts.nim and report.nim; two table aligners.
* Test-only code: `profile.smoothed/filtered`, `Effort.startElev/finishElev/finishDist` (always NaN in use).
* Messages hard-code "80%" and "25 m" next to the constants they describe.
* Legacy steps for squashing: `names/002-country-cells.sql`'s `update country set geom = null`, the back-fill in
  `climbs/002-name-number.sql`; stale comments mentioning `nch sector` and "(n/m)".
* The SpatiaLite index sub-query is written out in five places; one helper.

Sentinels: a "near " prefix on a stored start place is both text and state (`nameFor` tests
`startsWith("near ")`); booleans read as `r[2] == "1"`; "" for "no name".

The cycles are smaller than they looked: `names → landmark` is a library import with no file cycle (fine);
`climbs ↔ selection` is only `selection/fold.nim`, a leaf that should move to a neutral place (`text/`).

Good: the pure modules (geo, shape, climbpick, match, ordinal) are small, documented and tested; `download/fetch`
is a model design (injected network and disk, size checks, atomic writes); spatial indexes are used where it
matters; climb work is one restartable transaction per activity; naming thresholds are measured on real rides.

## 8. Second pass: FIT decoder, profile, xlsx, zip, bundle (subagent review; key claims checked)

Correctness (checked by hand):
* **The zip size limit does not limit**: `zipbytes.nim:60` checks the *declared* size, then inflates
  everything and compares afterwards.  Inputs are GeoNames downloads and a profile file, so the risk is low,
  but the check promises what it does not do: cap the inflated output.
* **A bool field's invalid marker (0xFF) reads as true** (`fit/decode.nim:124-127`); every other type drops
  invalid values.

Reported, not yet checked:
* Corrupt input can crash rather than raise `FitError`: a huge `date_time` value overflows in
  `fromUnix(...)` when printed by `nch fit` (a Defect: `raises: []` does not cover it).
* Chained FIT files: the tokenizer keeps the previous file's timestamp across a new header.
* A 0xFFFFFFFF timestamp is accepted; a compressed timestamp with no base aborts the file instead of warning.
* Component scale 0 is not rejected (plain fields are); duplicate names in the profile silently overwrite.
* `bundle/unpack.nim` catches `Exception` (hides bugs) and uses a fixed `.part` name (two processes clash).

Complexity and duplication:
* `decode.nim`'s `decode` is ~180 lines with the plain/unknown dispatch written twice; procs of 12
  parameters (`emitPlain`, `decodeField`) want a context object; plan building is written twice.
* `BaseType` facts (size, signedness, invalid marker, name, FIT number by position only) are spread over
  five `case` statements: one table indexed by the enum.  `baseTypeOf` exists twice with different meanings.
* Type names (`"date_time"`, `"timestamp_16"`) are compared as strings though `TypeKind` has them.
* Dead or test-only: `basetype.decode/RawValues/checkBad`, `Tokenizer.bytes`, `readWorkbook`.
* Sentinels: -1 for "no number" (`FieldValue.number`, `timestampField`), "" for unknown names.
* The xlsx reader is justified (runtime `--profile`, nothing suitable in Nim); the three small XML files
  could use `std/xmltree`.  The override machinery in `bundle/` costs more than the reader; a plain
  `--profile PATH` might do.

Good: a strict tokenizer (every length checked before use, offsets in errors), real variant objects
(`Token`, `Event`, `FieldValue`), shared immutable `Meta`, pure/IO split in `unpack`.

## 9. Second pass: server, cache, map, ff, model, templating, ui (subagent review; key claims checked)

Correctness (checked by hand):
* **The server can hang**: `serve/server.nim:19-21` reads all of stdout, then all of stderr, then waits with a
  timeout; a hung worker is never timed out or killed, and a worker that fills the stderr pipe deadlocks.
  The server is single-threaded, so one slow `map` (first run works out climbs) blocks every request.
* **The map cache goes stale**: `map/command.nim:186-188` reuses an existing file; the key covers the
  activities only, not climb names or the detector, so a renamed climb keeps the old map until
  `nch cache --delete geojson`.

Reported, not yet checked:
* The map request uses `bits` as typed, not re-encoded from the ids: two spellings, two cache files.
* `validModelName` allows `--`, which `isCacheFileName` rejects: `ff` fails for such a model.
* The token cookie has no `Max-Age`, so bookmarks stop working when the browser closes (the docs say otherwise).
* `{{{style}}}` is raw JSON inside `<script>`: a `</script>` in the author's edited style breaks the page.
* `calc.nim:20-23`'s comment understates the hour-bucket error ~10x (0.3%, not 0.03%).
* Decay times are on `ff_model`, so changing them recomputes all impulses under a new model; they are curve
  parameters, not impulse parameters.

Complexity:
* `templating.nim` implements Mustache sections, inverted sections, lists and scopes, none used by any
  template (~60 lines would do; a runtime engine is justified because templates are edited in the cache).
* Two cache naming schemes (`ff` readable, `map` proquint) and two ways for the server to find the check;
  the proquint collision loop and the request stored in the file are more machinery than 48 bits need.
* Each web-able option is written in four places: `commandRules`, the command's params, its usage, `webQuery`.
* `ff` `Params` is a bag of output-mode booleans (`stdout`, `worker`, `serve`, `noOpen`...) with a
  `webProblem` to forbid combinations: an output-mode enum.
* The page's geometry JavaScript (offsets, smoothing, lanes) has no tests; moving it to a `map-geometry.js`
  testable under node is worth considering if it grows.

Good: request validation (whitelist routing, Host check, token compare in constant time, no shell, no path
traversal found), `bits.nim` bounds, analytic impulse integration, hourly impulse rows (the right design),
one palette for terminal and web.

## 10. Additions to the plan (after step 9)

10. **Bug fixes from the second pass**, each with a test: climbs per timer segment; cap the country fallback;
    index `effort(activity_id)`; bool invalid marker; cap inflated size; server reads both pipes, times out
    and kills, and stops blocking on one request; map cache key includes what the map shows (or the file is
    always remade: measure first); one Unicode folding everywhere (a registered SQL function).
11. **Shrink**: templating to what is used; one cache naming scheme; dead and test-only code from §7-9;
    `decode.nim` dispatch written once with a context object; `BaseType` facts in one table.
12. **Push work into SQL**: duplicate candidates from the spatial index, attempts and ranks with window
    functions, feature filtering by class in SQL, set-based `country_cell` inserts, one helper for the
    SpatiaLite index sub-query, routes read as numbers or blobs instead of WKT text.
13. **One owner per fact** (continued): GeoNames codes in `names/codes.nim`; web options generated from the
    command's spec (follows step 6).

## 11. Packages (agreed in discussion, 2026-11-08)

The aim: packages declare their dependencies; the build enforces a DAG; a package sees a database that already
has the tables of everything it depends on, and calls its dependencies' code directly.  A third party adds a
package by dropping a directory in and rebuilding (source drop-in, as Caddy does).  Considered and rejected:
loading shared libraries at run time (Nim has no stable ABI: fragile, and needs a rebuild anyway) and packages as
separate programs (more complex and slower; no function calls between packages).

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

* The registry is generated from the package directories (a macro or a nimble task), sorted topologically; a
  cycle or a missing dependency fails the build.  It replaces `modules.nim`, `dispatch`, `commandNames` and
  the usage list.
* Tests: a package imports only from itself, the framework and its declared dependencies; the tables named
  in its SQL strings belong to the same set (approximate: table names from the fragments, matched in the code).

### Extension points

An early package defines an extension point; later packages fill it.  This is how cycles are avoided without
merging packages that should be separate.  Known so far:

* **import steps** (exists: heart rate) — eager work on each imported activity;
* **on-demand activity work** — "each activity not yet done by version N of my method": today `climbs_done` and
  the impulses' "missing" query each do it by hand.  Derived data then never needs a migration: a change of
  method is a version bump and the work is redone;
* **activity criteria** — climbs adds `--climb` to `activities` (breaks `climbs ↔ selection`);
* **name sources, in priority order** — landmarks first, GeoNames after (breaks `names ↔ landmark`);
* **sector naming** — the package that made a sector says how it is named;
* **what will be deleted** — each package adds its line to the deletion message.

### Sectors

`sectors` becomes a package: the `sector` and `effort` tables, matching rides against sectors (most of
`match.nim`), retiring, duplicates, the kept numbering of shared names.  `climbs` depends on it: it detects
climbs, inserts them as sectors, and keeps `climb(sector_id, gain_m, gradient, category)` of its own.  A later
package that finds sectors by overlapping activities does the same with its own table.  No package alters
another's table.

### Samples

The importer owns the raw per-second data: one `sample` table with the common FIT channels (position,
altitude, heart rate, power, cadence, speed, temperature), nullable.  Packages own derived data.  (Replaces
`coords` + `heartrate`; the heart rate import step goes.)

### Cache

A package near the bottom, not framework: packages write to it, the loader does not.  It grows the manifest
`bundle/unpack.nim` keeps today into one for every file (detect and warn of edited files), with an area per
package.

### Database versions (fragments) with packages

The current mechanism stays, per package (`package/NNN-name.sql`, as recorded now).  Added rules:

* A fragment touches only its own package's tables.  A table rebuild keeps whatever dependents refer to.
* A new database applies fragments in DAG order; an old one gets later fragments of an early package after the
  fragments of packages that depend on it.  **A test builds the database by several valid orders and
  compares the schemas** (tables, columns, indexes, foreign keys): this automates the comparison CLAUDE.md asks
  for by hand before a squash.
* Fragments are for imported and hand-entered data (users, landmarks, names given by hand, models); derived data
  uses the version bump of on-demand work instead.
* A database with fragments from a package this build lacks is refused, naming the package ("this database has
  tables from package X, which this build does not include").  `nch db --drop PACKAGE` can come later.
* Squashing: as now, until anyone else has a database (a release: tie this to the version rules still open
  from Task 11).  After that, if the fragment lists grow long, the route is a per-package **baseline** (a
  squashed `001` for new databases, the old fragments kept for existing ones, the schema test proving both
  give the same result).  Not built now.

### Commits (replace plan steps 2 and 8; before step 6)

1. Move shared code out of the modules into packages of their own (time, the delete countdown, text folding,
   geo...); merge `fit` and `profile`.  Mechanical.
2. The framework: `Package`, the generated registry, the topological sort; fragments applied in DAG order;
   the "missing package" refusal.  Rebuild the database.
3. Each directory gets its `package.nim`.
4. The import and SQL-table tests.
5. Extension points, one commit each, each discussed first: on-demand activity work, activity criteria, name
   sources, deletion lines (import steps exist).  The cycles go.
6. The schema-by-several-orders test.
7. Later, separately: the `sectors` split, the `sample` table, the cache manifest.
