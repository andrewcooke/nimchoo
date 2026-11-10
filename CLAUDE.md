
# nimchoo

this project is a reworking of choochoo (which can usually be found in
the choochoo directory parallel to this one).  what i want to do is:

* simplify choochoo hugely.  instead of a monolithic web service it
  will be a collection of lightweight tools.

* simplify the database schema (now i understand postgres better)

* simplify how data are displayed.

* move from python to a more modern, more powerful language (with an
  emphasis on functional programming).

* extend tests.

* use ai for development.

## TODO.md, HISTORY.md, REVIEW.md

* TODO.md holds **open work only**.  when something is done, delete it from TODO.md in the same commit.
* HISTORY.md holds finished tasks and the reasoning behind decisions (TODO.md until 2026-11-08).  read it for *why*
  something was decided; its names of commands and files are those of their time, so it is not current guidance.
* REVIEW.md is the second code review (2026-11-09: fuzzing, the access model, commands back into their packages,
  tools) and the plan that TODO.md follows; the first review (2026-11-08) is its appendix A.

## rules

a few rules to guide behavior:

* i will generally discuss a change before implementing it.  don't
  switch from discussion to implementation without my approval.

* while this account has sudo privileges you MUST NOT use sudo
  yourself.  instead, ask me to execute commands that require sudo
  access.

* we are working on a newly installed VM so common commands may be
  missing.  ask me if you want me to install anything.

## language choice

i would like to try using nim and have installed the compiler etc.

## general structure

nimchoo is a set of **packages** (built 2026-11-09; the design and its reasons are in PACKAGES.md).  the aim is that the
system can be extended with new fit-related functionality by adding a package, without editing the others.

* a package is a directory under `src/nimchoo/packages/` that contains a `package.nim`; its **name is its directory's
  name** (unique; compared as nim compares names).  directories without a `package.nim` only group (`text/`, `util/`,
  `commands/`).  `package.nim` has one constant, `package`, of type `Package`: `depends` (the packages it uses, by name),
  `fragments` (not used yet: see below) and `commands`.  inside the package the files are whatever they are called.
* `core/` is not a package: `errors`, `ids`, the `Package`, `CommandDecl` and `Fragment` types, `Globals` and the exit
  codes, the log, `ownership.nim` (which package owns which table) and `registry.nim` (the dependency order).
* **the registry**: `nimble registry` (run first by the other tasks) writes `src/nimchoo/registry.nim` from the
  packages found, in dependency order; it is checked in, and a test fails if it is stale.  a cycle, a missing
  dependency or a package or command name used twice stops the build.
* **libraries below, commands above.**  a command package (name ends in `cmd`, in `packages/commands/`) holds one
  command (`activitiescmd` joins the listing, `--select`, `--import` and `--delete`): `run`, its options, its output.
  `package.nim` declares it (`commands: @[CommandDecl(name:, summary:, run:)]`); `nch.nim` looks the command up by
  name in the registry and builds the usage text from it; there is no other list of commands.  no package depends on a
  command package, and only a `package.nim` imports a command (checked by a test).  the module that first introduces
  a concept owns it (eg `importer` owns activities) and later packages use its library files.
* **imports** (`tests/core/test_imports.nim`): a file imports only its own package, `core`, standard and third-party
  libraries, and the packages in its `depends`.  `depends` must also name the packages whose **tables** it reads in SQL
  (checked when the statement is prepared: the access model, below).
* **tables** belong to the package whose fragments make them (read from the `create table` / `rename to` in the sql;
  `tests/core/test_ownership.nim` applies the fragments one at a time and checks that SQLite agrees).  a package may
  write only its own tables, and read those of its `depends` and of `db` (the `user` table and spatialite's metadata);
  **enforced** (`core/access.nim`, `packages/db/access.nim`; PACKAGES.md "The access model"): a statement is checked as
  the package of the file it is written in, and a breach is a `StoreError` naming the package, the table and the sql.  a
  query joining another package's tables must be run by a package that may read them.  a table is written by its owner's
  functions (`selection/replaceSelection`, `db/users`, `user/profile`, `importer/remove`), so a command calls those.
* **fragments** (see below): each package with tables keeps its sql in its own directory, listed in `fragments:` of its
  `package.nim`; the registry joins the lists, in dependency order, into `allFragments`.
* **extension points** are few, and there is one: the import steps (`core/extension.nim`; `importer/channel.nim` declares the
  point `importStep`, and `heartrate/package.nim` contributes its step with `contributes:`).  the registry collects the
  contributions in dependency order into `registry.extensions`, in memory; `nch.nim` puts them in `Globals.extensions`,
  and a command reads them with `g.extensions.get(importStep)` (a command cannot import the registry).  the other
  candidates are deferred until something needs them (PACKAGES.md "Extension points").
  how a later package adds criteria to `nch activities` is open (TODO.md, "Criteria from other packages").
* **tests mirror the packages**: `tests/<group>/<package>/test_*.nim` (`tests/core/` mirrors `core/`), all imported by
  `tests/all.nim`; when a package moves, its tests move with it.
* per-second data is stored per activity, as arrays; by default other data refers to it by time (never by array index),
  and the arrays are never changed once written (an alternative needs a reason; REVIEW.md §6 "Samples").
* **adding a package**: make the directory, its `package.nim` (with `depends`), the files and tests; run
  `nimble registry`; if it adds tables, their fragments in `fragments:` of its `package.nim` (the package must depend on the packages whose tables they refer to: the build checks); if it is a
  command, `commands:` in `package.nim` and a `commandName` constant in its `command.nim` (the log uses it).

## display

i imagine graphical display of data having two layers.  first layer
would be associated with a command and would generate output in a
suitable format (eg sgv or some mapping data format) suitable for
display by third parties.  this layer would write output to a standard
directory which would also serve as cache (file names might be named
after command invocation to aid detecting when cached results can be
used).  second layer would be a simple local web server that (1)
interprets the URL after "localhost" as a nimchoo command and (2)
displays the result of executing that command.  this could involve
generating an intermediate html file that would similarly be cached.

this approach, with a lightweight server that simply invokes commands
and displays results is just a rough sketch - i haven't worked
through the details yet.

## activity selection

i can imagine that often it's useful (eg for a map) to select data
according to certain criteria.  one solution is to develop a mini
language that is shared by many commands.  another is a selection task
that generates a list of "ids" given those criteria that other tasks
then take as input.  yet another is to have a scratchpad in the
database that is the "current selection".  currently i think i prefer
the last solution (obvs this scratchpad is defined by a command that
itself uses the mini language, but that language is not shared by many
commands).

NOTE: this conflicts with the caching in display because it adds
implicit state.  we might work around this by including a hash of the
select in names as necessary.

## the database: fragments (migrations)

the structure of the database is described by sql files, "fragments", not
made by hand.  when `nch` opens a database it makes sure the file matches
what the program expects, by running any fragments the database has not
had yet.

* each package with tables keeps its sql in its own directory, as
  `NNN-name.sql` (eg `packages/climbs/001-schema.sql`, recorded as `climbs/001-schema.sql`: the name is the
  package's).  the package's `package.nim` lists them in order (`fragments: @[fragment("001-schema.sql")]`);
  the registry joins the lists of all packages into `allFragments`, each package after those it depends on (a table that refers to a
  table of a package it does not depend on stops the build).  a test builds the schema in several valid orders, and from a database made before a
  package's later fragments, and compares them.
  the sql is read at compile time, so it is inside the `nch` binary.
  `packages/db/001-schema.sql` (the `user` table and spatialite's metadata) is
  applied first, always.  the numbers only order the files within a module.
* the database has a table `fragment` (name, applied_at, sha256 of the
  sql, seed_version).  on opening, for each fragment in the program: not
  recorded -> run its sql and record it, in one transaction; recorded with
  the same checksum -> nothing.  so a new database gets every fragment, an
  up to date one nothing, an old one only what was added since.
* two refusals: a recorded fragment whose checksum differs from the
  program's ("made by a different version of nch"), and a recorded
  fragment the program does not have ("from a newer version").  the
  messages say to `nch db --delete -f` (start again).
* so: **never edit a fragment that any database has had, and never delete
  one.**  to change a table, add a new numbered file (`alter table`,
  `update`, ...).  watch for sqlite limits: it cannot drop a column that
  has a foreign key, or one that an index uses, without rebuilding the
  table.  fragments are plain ddl; data is inserted from nim (a fragment
  may have a seed, `withSeed`: the model module puts in the default model).
* tests build their databases from scratch, so they do not care how many
  fragments there are; `tests/db/test_store.nim` lists the fragment names
  and counts them, and must be updated whenever a fragment is added or removed.

### squashing (decided 2026-11-05)

while only the author has a database we may, at a milestone, **squash**:
merge each module's fragments into its `001-schema.sql` (the final
schema), delete the later files and any retired module, and rebuild the
database (`nch db --delete -f`, then import again).  the cache survives
(downloads, settings), so nothing is fetched again.  rules:

* **once anyone else has a database, never squash again**: append only.
* before deleting the old fragments, compare the schema they make with the
  squashed one (every table, column, index and foreign key, from a fresh
  database each way), and keep a copy of the old database file until the
  author is happy with the new one.
* what a rebuild loses that cannot be made again from the fit files: the
  users and their fthr, models, the saved selection, the landmarks, and names
  given by hand (`nch climbs --edit`).  the author chose to start from zero
  at the first squash; a save-and-restore of those few tables is a possible
  one-off script if it is ever wanted.
* the first squash (2026-11-05) removed: the `places` module (the embedded
  list of towns, `place` table, `activity.place_id`), `name_source`,
  `sector.kind`, `sector.name_checked`, and the one-off "forget the names"
  steps.
* the second squash (2026-11-05) made every table `strict` (a text
  value in an integer column is an error) and merged
  `climbs/002-retired.sql` into `001-schema.sql`.  SpatiaLite's
  `AddGeometryColumn` does not work on a strict table (it declares the
  column with the type "POINT"), so a geometry column is declared
  `blob` in the table and registered with
  `RecoverGeometryColumn(table, column, 4326, 'POINT', 'XY')`: the
  same constraints and spatial index.  A new file is also made with
  `auto_vacuum = incremental`; `reclaim` (in `packages/db/store.nim`) gives the
  space back after a big delete.  Every new table must say `strict`.

### other decisions to remember (details in HISTORY.md)

* names (climbs, activities, starts) come from GeoNames files downloaded on
  demand, read by one-degree cells into `feature`/`coverage`; every feature is
  kept and the rules choose.  a name is decided in the run that needs it, or the
  command stops with the reason (`DownloadError`); `--offline` answers
  "nothing" everywhere (names stay "" for good).  do not build lazy
  back-filling for a bad connection: need the internet and say so.
* tests must never use the network or the real cache: every `Globals` in a
  test says `offline: true`.
* landmarks (`nch landmark`) are the author's own names for places, shared
  by all users, and come before every other name.

## describing things: one standard way (decided 2026-11-05)

an activity and a climb are said the same way wherever they appear (the list, `nch climbs`, the sector
commands, messages), like `__str__` in python.  **each module says its own things, in its own `describe.nim`**:
the importer owns activities (`packages/importer/describe.nim`: `activityLine` / `activityCells`), the climbs package owns
climbs (`packages/climbs/describe.nim`: `climbLine` / `climbCells`).  a new module that has things to show adds a
`describe.nim` of its own; a command that shows an activity or a climb uses the owner's, and does not make its
own format.  the number formats every one of them needs (`km`, the dash for not recorded) are in `packages/ui/units.nim`
(and the active time in `packages/ui/interval.nim`).

* an activity:  `2020-08-14 06:01  cycling  36.7km 1h41m  Providencia / Lo Barnechea and back`
  (start, sport, distance, active time, then the place it started and what it is called, joined by " / ").
  verbose adds the sub-sport (`cycling/road`) and, last, the path of the file.
* a climb:  `Cerro San Luis₄  4 0.5km +89m 17.8%`  (name, category, length, gain, gradient).  a name shared by several climbs
  carries a **kept number as a subscript** (`sector.name_n`, given when the climb gets its name, never renumbered; no "of m"); typed as
  `Cerro San Luis₄`, `Cerro San Luis 4` or `Cerro San Luis4` (`packages/climbs/display.nim`, `ordinalForms`).  in
  `nch climbs` the summary follows: how many attempts, best, latest (with its date) and its **personal rank** (`3 of 12`: among the
  user's own attempts); `--everyone` swaps it for the **leaderboard** (riders, fastest and who, your best's place among each
  person's best: `4 of 6`).  The two ranks are never shown together, are worked out when asked for, and are never stored; `-v`
  lists the attempts (or each person's best).  The selection chooses the climbs, never the attempts; `--name TEXT` chooses climbs by name.
* **no space between a number and its unit** (`36.7km`, `+89m`, `17.8%`, `1h41m`).
* in a table the parts are cells lined up in columns (padded, numbers to the right), headed `start`, `sport`,
  `distance`, `active`, `place / name` (and `path`); the one-line form is for headings and sentences.
* not recorded is `-` (dim); an activity with no positions says `no GPS` where the place and name would be (-v only).

## the shape of the commands (decided 2026-11-05)

a theory of the commands, to keep the interface consistent.  the work of getting there is in HISTORY.md (finished).

* **a type that lives in the database has a plural command that manages the collection**: `activities`, `climbs`,
  `users`, `models`, `landmarks`.  the plural is a reminder that it works on a collection of instances.  the grammar
  is the same for all: `TYPE [which ones] [action]`, with the actions `--add NAME`, `--edit NAME ...`, `--delete NAME`
  (and `--import PATH...` for activities, `--retire` / `--unretire` for climbs).  every `--delete` is confirmed with
  `-f` (with the countdown and the "would delete ..." message).  the parameters both say what to do and pick the
  instances it is done to.
* **which ones**: a named type takes a NAME (`users --edit NAME`).  activities, which are what everything is about and
  are too many to name, take criteria (`--sport`, `--climb`, `--from` ...) or the selection.
* **the selection**: the activities that commands which work on activities use by default.  `activities` with no
  arguments shows it; with criteria (or `--all`) it searches all the activities, and `--select` keeps what is listed
  as the selection.  `climbs` with no arguments shows the climbs of the selected activities, and `--all` shows every
  climb.  **`--all` means everything, not just the selection**, wherever the default is the selection.
  a selection belongs to one user (there is no `--users`).
* **commands about things outside the database are singular**: `map`, `fit`, `log`, `ff` (which is both, and can
  wait).  `cache` (the files outside: downloads, generated files; with no arguments it says what is there and how big,
  `cache --delete KIND` deletes) and `db` (the database file: no arguments says where and how big, `db --delete`
  deletes it) are of this kind too.
* so there is no `list`, `import`, `delete`, `empty`, `sector`, `user`, `model` or `landmark` command: they are
  `activities` (with `--select`, `--import`, `--delete`), `climbs`, `users`, `models`, `landmarks`, `cache` and `db`.
  `empty --user NAME` is `activities --all --delete` for that user; `user --remove` is `users --delete NAME`;
  `empty --sectors` is `climbs --delete --all` (a reset: climbs are retired, never deleted one at a time);
  `empty --all` is `db --delete -f`; `empty --downloads` / `--cache` are `cache --delete downloads` / `geojson csv html` (also `system`, or `all`; no -f: the cache is made again).
* nothing is kept for backward compatibility: there is one user.

## choosing resources and libraries: take the time (decided 2026-11-06)

the author is slower than the assistant and does not follow all of its work, so a workaround can go unnoticed
(the GeoNames country outlines were "invalid" for GEOS, so point-in-polygon was written by hand in nim, and only
later did a better data source turn up).  the rule:

* it is fine to spend extra time finding a good resource (a data source, a library, a format).  this is a personal
  project, not a commercial one, and there is no time pressure.
* **having to work round errors in other people's work is a negative.**  if a data source or a library has
  problems (invalid data, wrong answers, a missing feature), do not quietly build a workaround: **stop and tell the
  author**, and look at the alternatives together.  say what is wrong, what the workaround would be, and what the
  alternatives are.
* prefer resources with clean licences (public domain over attribution), small size, and that let the work be done in
  the database (sql, spatialite) rather than in hand-written code.

## the map and its addresses (decided 2026-11-06)

* `heatmap` is `map`: the routes of the selected activities and the climbs they went up, in one GeoJSON file whose features
  say what they are (`kind`: route, climb) and nothing about how they look; the page (Leaflet) decides the look.  `map`
  makes everything itself: no layer commands, no layer index (see MAP-LAYERS.md for what was considered and why not).
* **The address carries the activities**: `/map?bits=LIST&check=HASH`.  `LIST` is the set of activity ids as a short string
  (`packages/selection/bits.nim`: runs or a bitmap, bit-level codes, URL-safe base64, one ride is 5 characters, a date range 5 to 8).
  `HASH` is the first 6 hex digits of the content key of those activities (`packages/selection/selection.nim`, `checkOf`): after a
  database rebuild the ids mean other activities, and the check refuses the old address.  So addresses work until the
  database is rebuilt.  The address is a readable interface and may grow parameters.
* **`--check` means check** (verification, never choice): in `ff` it is a hash of the data the curves are made from.
  `ff` is not about the selection: it always uses all the activities.
* **Cache file names are not the address**: `map-lusab-babad-fuzoh.geojson` is the command and 48 bits of the hash of the
  request as proquints (`packages/text/proquint`, `cache.nim` `requestStem`).  The request is written into the file (`nch.request`)
  and checked when the file is found, so a clash of names cannot show the wrong map.
  The key of everything else the file is made from (the data of the packages it reads, and the build) is written too
  (`nch.inputs`, `cache.inputsKey`); if it differs the file is made again, in place.

## no past to protect: choose what is better, not what is the same (the author, 2026-11-06, said again, firmly)

there are no users, no deployments and no permanent data.  the database is rebuilt from the fit files at will; the
cache can be deleted; nothing outside the author's machine depends on anything here.  so:

* **"it keeps the results the same / closest to what we have" is not a reason, for or against.**  never offer it as a
  justification.  decide by which option is *better*: more correct, simpler, faster, clearer, better looking.  results
  that change because something was improved are the point, not a cost.
* **do not keep things for compatibility**: no aliases, no migration of old stored forms, no "unless it breaks X" for
  anything that exists only on the author's machine.  rebuild instead.
* what is still worth saying about a change: *what* will be different, and *how to rebuild*.  say that in a line; do not
  weigh it.
* when there is no ground truth for "better" (a detection setting, say), say so, and propose how to judge: look at
  examples together, compare against what the old choochoo did, measure.
* **The page is three templates**, each built in and unpacked to the cache's `system/templates/` where the author edits it
  (never overwritten once changed; delete a file to get the built-in one): `map.html` (the page and its script),
  `map.css` (the look of the page) and `map-style.json` (how routes and climbs are drawn).  The css and the style are
  filled in first, with the palette's colours as tags (`{{blue}}`), then put into the page.  The look: routes are thin
  red threads, each offset sideways by an amount of its own (`spread_m`); climbs are thick transparent grey lines beside
  the road, in lanes alternating sides so that climbs on the same stretch do not overlap, offset in pixels (recomputed on
  zoom, simplified first so that hairpins do not loop); corner cutting (`smooth_rounds`) rounds the lines.  A comment in
  these templates must not contain a tag (the engine ends a comment at the first closing braces).

## working practice (decided 2026-11-08, after the review)

* the author is exact about what is seen (output, behaviour, limits); how the code does it is for you to choose,
  with the whole program in mind.  at a design point, offer two or three options and a recommendation rather
  than one design.
* when a feature fits badly on what exists, say so and propose changing what exists (within the package rules)
  rather than working round it.
* **a step is done when**: its tests pass (with a test for the class of bug, where there is one); what refers to
  it is updated (help text, CLAUDE.md, TODO.md: grep the names you changed); the code it made dead is deleted.
* a claim that something is faster, smaller or better comes with a measurement, or with before-and-after
  examples where there is no ground truth.
* suggest a whole-system review at milestones (every several features, before a squash), in a fresh session:
  each step can be right while the whole drifts.

## guidelines for writing code (from the review of 2026-11-08)

* **one fact, one place.**  a list of names, options, kinds or help texts is written once and everything
  else is made from it (a table indexed by an enum, generated usage).  never keep two lists in step by hand.
* **parse, don't validate.**  input (the command line, rows from the database, files) is turned into a type
  that can only hold valid values (variant objects, enums, distinct types, `Option`).  no bags of booleans
  checked afterwards; no "" or -1 meaning "none" or "ok".
* **a missing abstraction is the bug.**  when fixing a bug, ask what class it belongs to and fix the class (one
  loader, one helper, one table), with a test that would catch the next instance.
* **packages declare what they use.**  a package imports only its declared dependencies (checked by a test);
  shared code is a package of its own, not part of the module that needed it first.
* **let the database do database work.**  values are bound, never put into sql text; rows are read into typed
  tuples or objects; filtering, joining, ranking and spatial search are sql, not loops in nim.
  values are given by **name**: `db.scalar(int, "select count(*) from sector where gain_m > :gain", gain = 100.0)`.  a `?` is
  a compile error, and so are a `:name` with no value and a value with no `:name` (checked when the text is a
  literal; at run time otherwise).  a query built from pieces is an `Sql` (`packages/db/sqltext.nim`: text with `:names`,
  values by name, pieces joined with `&`), so that no value can fall out of step.  the prepared statements that are
  run many times (`prepareStmt`, the importer's inserts) bind by position: they are for loops over thousands of rows.
* **a failure is never stored as a result**: raise, or warn and leave the work undone.
* **delete dead code and stale docs in the same commit** that makes them dead.

## conventions

(moved from the old TODO.md on 2026-11-08 and corrected by hand; checking them against the code is TODO step 5.)

### error handling

four kinds of things go wrong, and each has one mechanism:

1. **bugs are Defects.**  a violated precondition or a "can't happen" case uses `doAssert`/`raiseAssert` (or the
   built-in bounds checks).  never caught, never turned into a warning.  a table lookup that must succeed uses
   `must`/`mustMut` (`packages/util/lookup`), which asserts instead of raising `KeyError`.
2. **input we cannot use is an exception**: a corrupt FIT file, a bad profile, a file that is not an xlsx.  all are
   subtypes of `NchError` (`core/errors.nim`), raised with the `raiseFit` / `raiseProfile` / ... helpers and listed in
   `{.raises.}`.  corrupt input must never reach a Defect (a fuzzer is to check this for FIT files: TODO step 2).
3. **ordinary absence is an `Option`**.  no sentinel values.
4. **oddities we can recover from are warnings**, collected (`packages/util/warnings`, each with a `WarningKind`), never
   logged or printed by library code.

* `try` only at boundaries: the commands, and where a third-party or `std` call is wrapped into one of our errors.
  never `except CatchableError`/`Exception` (except at the top of a thread or server loop, said so in a comment).
* every module starts with `{.push raises: [].}` after its imports, so a proc raises nothing unless it says so.
  (the exceptions are the two async modules, `childasync.nim` and `packages/web/workers.nim`: async code is not `raises: []`.)
* **commands** (`core/globals.nim`): `run(globals, args): int` is `{.raises: [].}`; 0 for success, 1 when the work
  failed (one line on stderr, no trace), 2 for a usage error.

### style

* Nim 2.2 or later; the standard library first.  third-party: zippy (inflate), db_connector, checksums; C:
  SQLite, with SpatiaLite loaded as an extension.  compiler-checked is better than convention (`raises`, `case`
  over enums with no `else`, distinct types).
* formatted with `nph`.  every module opens with a `##` comment saying what it is for, and `##` documents each
  exported thing (not the borrowed operators of a distinct type).  comments say *why*, not what the next line does.
* `camelCase` for procs, variables, fields and constants; `PascalCase` for types; lower-case one-word module
  names.  enum members carry a short tag of their type (`wkDataSize`, `vkInt`).
* export with `*` only what other modules need.  `std/` imports first, as one bracketed list, then project
  modules: relative inside `src/`, `nimchoo/...` in tests.
* `func` for pure functions, `proc` for anything with effects.  results are returned, not written to out
  parameters (except `var` collectors and iterators).  plain value objects; kinds are variant objects.  `let` by
  default.  no module-level mutable state (exceptions today: `packages/util/profiling`, and the stop flag of `packages/db/checkpointer.nim`, an atomic).
* templates only where a proc cannot do it; no macros unless they remove real repetition.
* **printing uses `std/strformat`** (`fmt"climb {id} has {n} efforts"`, `fmt"{x:.1f}km"`): the whole sentence is seen at
  once and a name in the braces is checked when the program is compiled; `&` and `$` pieced together are easy to get
  wrong (a missing space, the wrong variable).  decided 2026-11-09.  the rule: **all new printing (messages, lines,
  table cells, file text) uses `fmt`**; **a file that imports `strformat` has all its existing printing converted to it**
  in the same commit (and, when the change is small, the other files of its module).  `&` stays for joining pieces that
  are actually built up (a list of parts, a path, a loop).  sql text is not printed: use `?` or an `Sql` (above).

### output

* a table column carries its unit in its header; in a sentence the unit is attached with no space (`842.2km`,
  `4h41m`).  input never takes a unit for distance (decimal km), and `m` always means minutes.
* intervals of time (`packages/ui/interval.nim`): units `d h m s`, no leading zero unit, the first unpadded and later ones
  two digits (`45s`, `22m05s`, `4h41m`, `2d03h07m`); seconds only under an hour, minutes from an hour; rounding
  carries.
* the words and looks for what happened are in `packages/ui/vocabulary.nim`; colour only where it means something, and the
  status colours (green done, red failed or deleted, yellow advisory, blue the selection) for nothing else.

### tests

* `std/unittest`, mirroring the source tree (`tests/<dir>/test_<file>.nim`, all imported by `tests/all.nim`; **when source moves, its tests move with it in the same commit**; a test file may cover its neighbouring files, and a
  module that only wires others together (`package.nim`, a command that is tested through its parts) may have none);
  test names are plain sentences.  `nimble test` (optimised, with run-time checks) is the one to run often;
  `nimble testdebug` for tracking down a failure.
* small cases are built by hand (`tests/support/`); behaviour that must match the FIT SDK uses real files
  (`../choochoo/data/test`; `nimble csvreport` compares our CSV with the SDK's).  error paths are tested; a bug fix
  comes with a test.
* tests never use the network or the real cache: every `Globals` in a test says `offline: true`.
* one logical step per commit, tests passing in each; the message has a summary line and a short paragraph on why.
