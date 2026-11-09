# Packages

The design of packages, agreed in discussion on 2026-11-09 (it replaces the first sketch in REVIEW.md §6, which is
kept for the reasoning).  Built so far (step 8.2, first commit): `core/package.nim`, the registry and its generator, and the package `fold`; the rest is the work of TODO.md step 8.  When something is built, the text
that describes it moves to CLAUDE.md, and this file keeps the reasons.

## What a package is, and what it is not

Nim has **modules** (one `.nim` file) and nothing larger.  A directory means nothing to the language; "package" in
Nim means a nimble package (a whole project), which is not what is meant here; nothing in Nim stops a module
importing any other, and the only visibility is the `*` on a name.  So a *package* in this project is our own
concept, made of three things:

1. a **directory** that holds the files (the only grouping Nim's file system gives);
2. a **declaration**, `package.nim`, an ordinary Nim value that says what the package needs and what it provides;
3. a **check**, because the language will not: the build reads the declarations and the code and fails when the
   rules below are broken.

The aim: packages declare their dependencies; the build enforces a DAG; a package sees a database that already has
the tables of everything it depends on and calls its dependencies' code directly; a third party adds a package by
dropping a directory in and rebuilding (source drop-in, as Caddy does).

Rejected: loading shared libraries at run time (Nim has no stable ABI, and a rebuild is needed anyway); packages as
separate programs (slower, and no function calls between them).

**Not a sandbox.**  A package is source compiled into the program, with the whole process and the database file at
its disposal.  The checks catch mistakes; they do not contain a hostile package.  Installing a package is trusting it.

## Layout and rules

```
src/nimchoo/
  core/                      the framework (not a package; has no package.nim)
  packages/
    text/                    a directory with no package.nim only groups
      fold/                  a package, called "fold"
        package.nim
        fold.nim             implementation files: internal, whatever they are called
      proquint/
        package.nim
        xyz.nim
    db/
      package.nim
      001-schema.sql
      pqr.nim
    spatial/
      climbs/  (package.nim, 001-schema.sql, foo.nim)
      sectors/ (package.nim, 001-schema.sql, bar.nim)
```

1. **A package is a directory that contains `package.nim`.**  Its **name is the name of that directory** (not the
   path), and it is unique among all packages (compared as Nim compares names: ignoring underscores and case except that of the first letter).  Directories
   above it only group; moving a package to another group changes nothing but import paths.
2. **No nesting**: a package directory contains no other `package.nim` anywhere below it.  It may have
   implementation subdirectories.  A grouping directory holds no code.
3. **A package may contain** SQL files (`NNN-description.sql`) and implementation files.
4. **Imports** (checked by a test, which reads every `import` line): a file imports only from its own package, from
   `core`, from standard libraries and third-party libraries, and from the files of packages listed in its
   package's `depends`.  Any file of a dependency may be imported: the language cannot hide the others, so the
   rule does not pretend to.  A test file may import the internals of the package it tests.  `core` imports no
   package.
5. **Fragments** are recorded as `<package name>/NNN-description.sql`, as they are now (`climbs/001-schema.sql`), so
   the database of the author is valid when the packages move.  The rules of CLAUDE.md ("never edit a fragment a
   database has had") stay.
6. **Table names are unique across all packages**, and the build says which two packages both make one.

### package.nim

An ordinary Nim value; the name is not in it (the directory gives it).

```nim
const package* = Package(
  depends: @["sectors", "importer", "names"],
  fragments: @[fragment("001-schema.sql")],
  commands: @[climbsCommand],
  contributes: @[],                 # see extension points
)
```

(Built so far: `depends`, `fragments` and `commands` (a `CommandDecl`: name, summary, `run`; the first command package is
`fitcmd`, 2026-11-09: the registry's `commands` is what `nch` dispatches on and prints in its usage, alongside the old
`Command` enum until the last command has moved); `contributes` comes with the first extension point.  The module `core/package` is imported `as corePackage`, because the constant is also
called `package`.)

The registry (below) reads it.  A package's own documentation (the feature detail now in CLAUDE.md) goes in a
`README.md` beside it.

### The registry

Generated from the package directories and sorted into dependency order.  It fails the build on a cycle, a
missing dependency, or a duplicate name.  It replaces `modules.nim`, the dispatcher's table of commands and the
usage list.  Generated by a nimble task that writes `registry.nim` (a compile-time scan of directories would not
notice a *new* directory, because Nim does not recompile a module whose files have not changed).  Open: whether
the generated file is checked in (stale risk) or ignored (a fresh clone needs `nimble` first).

## Layers: libraries below, commands above

Most of the cycles in the code come from a library and its *command* living in one directory.  So a package is
either a **library** (tables and functions) or a **command** package (the command, built on libraries); a library
never depends on a command package.  The commands of today:

| Cycle now | Cause | Resolved by |
|---|---|---|
| `cli` ↔ `ui` | `ui/logfile` needs `cli/catalog` (the list of commands) | **done (2026-11-09)**: the log (`Log`, `Level`, `LogEvent`) is `core/logfile.nim` and takes the command as a string; `ui` no longer imports `cli` |
| `fit` ↔ `profile` ↔ `xlsx` ↔ `zipbytes` | `profile` is part of `fit`; `zipbytes` needs `fit/bytes`, a general byte reader | **done (2026-11-09)**: `profile` is in the package `fit` (`default`, `load`, `model` keep their names); `bytes`, `zip`, `xlsx`, `bundle`, `cache`, `download` are packages below it; `fit/command.nim` stays in `src/nimchoo/fit/` until `fitcmd` |
| `db` ↔ `user` | `nch db` (in `db/`) uses the delete countdown (`user/wipe`) | the countdown is its own package; the `db` command leaves the framework |
| `climbs` ↔ `importer` ↔ `landmark` ↔ `names` | `landmark`'s command uses `climbs/report` and `names`; the importer's command names activities | libraries below (`landmark`, `names`, `importer`, `sectors`), commands above them |

The imports that make the cycles (2026-11-09, from the code; a file importing a file):

* `cli/common` → `ui/logfile`, and `ui/logfile` → `cli/catalog`.
* `fit/decode`, `fit/reader`, `fit/records`, `fit/command` → `profile/model`; `profile/load`, `profile/model` →
  `fit/basetype`; `profile/load` → `xlsx` → `zipbytes` → `fit/bytes`; `fit/decode`, `fit/records` → `lookup`;
  `profile/default` → `bundle/unpack`.
* `db/command` → `user/wipe` (and `download/fetch`, `cli`); `delete/run` → `user/wipe`; `user/ddl` → `db/fragment`;
  `db/channel` → `fit/time`.
* `landmark/command` → `climbs/report`; `names/activity`, `names/climb` → `landmark/landmarks`; `climbs/command`,
  `importer/run` → `names/open`; `climbs/attempts` → `importer/describe`; `climbs/profile` → `importer/extract`.
* Not a cycle, but upward: `selection/command` → `delete/run`.

Recompute with the import graph of `src/nimchoo` (directories as nodes) when starting: the code will have moved.

## Extension points

Where a *low* package must call code that it cannot know at run time.  Only two are real today:

* **import steps** (heart rate): work for each activity as it is written;
* **on-demand activity work**: "each activity not yet done by version N of my method" (climbs; impulses).

The package that defines the point owns its type, in its own files (`importer` defines `ImportStep`; `heartrate`
depends on `importer` anyway, so it sees it).  `core` has only a generic mechanism that knows no domain type:

```nim
# core
type ExtensionPoint*[T] = object  name*: string
proc contribute*[T](point: ExtensionPoint[T], value: T, priority = 0): Contribution
# registry: get(point): seq[T], in dependency order, then priority
```

A package lists `contributes: @[contribute(importStep, heartRateStep)]`.  The registry collects them; the library
receives the list as an argument (`runImport(g, targets, steps = registry.get(importStep))`), so there is no global
registry.  The type is checked when the list is read (type-erased store), and a test checks that every
contribution finds its point.

Other would-be points (activity criteria, name sources, deletion lines, sector naming) are solved by layering:
the command package depends on the libraries it joins.  A new point is added only when a second real case exists.

## The database

### Ownership is inferred

The package that makes a table owns it; nothing is listed in `package.nim`.

* (Built: `core/ownership.nim`, `tableOwners`/`ownerOf`, and `tests/core/test_ownership.nim` on today's modules, each module standing in for a package.)  At compile time the registry scans the package's fragments for `create [virtual] table NAME` and
  `alter table … rename to` (fragments are plain DDL by rule).
* A test checks it exactly with SQLite: apply the fragments package by package, in dependency order, and diff
  `sqlite_master` after each.  Anything that a text scan cannot see (SpatiaLite makes `idx_activity_start` when a
  function is called) shows up there, and a disagreement fails the test.
* An index belongs to the owner of its table; a SpatiaLite `idx_<table>_<column>` table belongs to the owner of
  `<table>`; SpatiaLite's own metadata tables and the `fragment` and `user` tables belong to `core`.

### The access model: dependencies are grants

SQLite has no users or `GRANT`.  It has `sqlite3_set_authorizer`: SQLite calls a function of ours for every table
and column a statement touches, as the statement is prepared, with the action (read, insert, update, delete); the
function answers allow or deny.  Used as the Postgres model would be:

| Postgres | here |
|---|---|
| a role for each package | an access profile for each package |
| `GRANT SELECT` on the tables of dependencies | may **read** tables owned by itself, by its `depends`, and by `core` |
| only the owner writes | may **write** only tables it owns |
| connect as the role | one shared connection; `query`, `scalar` and `execute` are macros that know the file they are called from, hence the package, and say so when the statement is prepared |
| the server refuses | a `StoreError` that names the package, the table and the statement |

So declaring a dependency *is* the grant, and a join across packages is now a dependency like an import.  What
remains true: the columns of a table are the API to everyone who reads it; changing them means touching the
readers.  They are now visible, acyclic and few, and the typed readers and the tests find a broken one.

Details: SQLite's own tables and functions are allowed to all; foreign-key cascades are not authorised statement by
statement, so `on delete cascade` is unaffected; the check costs nothing per row (it runs when a statement is
prepared); one connection stays because an import writes several packages' tables in one transaction (separate
connections or database files could not make that atomic, and foreign keys do not span files).

**Introduced in stages**: report-only first (a list of violations, to see how many there are), then the writes,
then the reads.  Tests run the program in-process, so the existing suite exercises it.  This is a check for
mistakes, not a security boundary (see above).

**Later, not now:** stable views.  An owner would publish a view over a table and dependents would read only the
view, so the owner could change the table.  The authorizer can allow "the base table, through a view of the same
package".  Spatial queries name the base table and could not use it.  Wanted only if a schema change starts to hurt.

### Fragments with packages

The mechanism stays (CLAUDE.md), per package.  Added:

* a fragment touches only its own package's tables (the authorizer checks it while the fragment runs);
* a new database applies fragments in dependency order; an old one gets later fragments of an early package after
  the fragments of the packages that depend on it.  **A test builds the database in several valid orders and
  compares the schemas** (tables, columns, indexes, foreign keys): this automates the comparison CLAUDE.md asks
  for by hand before a squash;
* a database with fragments from a package this build lacks is refused, naming the package;
* fragments are for imported and hand-entered data; derived data uses the version of its on-demand work.

## Tests

`tests/` mirrors the packages by name (`tests/<group>/<package>/test_*.nim`; `tests/core/` mirrors `core/`).  **When a
package moves, its tests move with it, in the same commit**, and `tests/all.nim` is updated.  Tests never touch the network or the
real cache.  A package's tests may import its internals.  Running only the tests of one package and of those that
depend on it becomes possible (the DAG says which) and is worth a nimble task: the suite is 45 seconds.

## Third parties

A contributor puts `fred/` under `packages/`, and the packages in it are named without the group (so they need
unique names; the build says when they are not).  A package's tables must be unique too.  The package list is
whatever the registry finds; nothing else needs editing.

## Order of work (TODO.md step 8)

1. **Inventory**: the packages and their layers, one table (draft below), settled with the author.
2. **`core` and the registry**: `Package`, `ExtensionPoint`, the generated registry, the import checker (at first
   allowing every existing import), ownership inferred and cross-checked.
3. **Move the leaf libraries** (time, text, geo, zip, process ...) into `packages/`; each move is mechanical.
4. **Break the four cycles** by moving shared code and splitting library from command (the table above).
5. **The extension points** that remain (import steps, on-demand work), each discussed first.
6. **The access model**: report-only, then writes, then reads.
7. **The schema-by-several-orders test**, and a `README.md` in each package (the detail now in CLAUDE.md).

After this, TODO steps 9 (options carry their help) and later follow, each command being rewritten once in its
final home.

## Open

* (Decided 2026-11-09) The generated `registry.nim` is checked in; a test makes it again and fails if it differs, and
  the nimble tasks regenerate it first (`nimble registry`).  `ExtensionPoint` is built with the first extension point
  (step 5), not in step 8.2.
* Import paths: plain (`import text/fold/fold`, so regrouping is a search-and-replace the compiler checks) or a
  generated search path for the parent of every package (`import fold/fold` whatever the grouping, but a generate
  step).  Start plain.
* What exactly `core` holds: `Package`, `ExtensionPoint`, the registry types, the database handle, `Sql`, fragments,
  `errors`, `ids`, and `Globals`/the command type (a command is `proc(g: Globals, args): int`).  Keep it small; each
  item needs a reason.
* The package list: see "Inventory" below (a draft, 2026-11-09, to be settled in step 1).

## Inventory (draft, 2026-11-09)

Made from the file-level import graph of `src/nimchoo` on 2026-11-09 (a script that reads every `import`; the
directory-level edges are in the "depends" column).  Layers run from the bottom: a package depends only on lower
layers.  "Today" says where the files are now.  Library packages never depend on a command package.

### Core (not a package)

`errors`, `ids`; the types `Package`, `ExtensionPoint`, `Fragment`, the command type, `Globals` and the exit codes
(`cli/common` without its imports of `db` and `ui`); the generated registry.  See question 1 for what else.

### Layer 0: leaf libraries (depend on core only)

| package | today | tables |
|---|---|---|
| `atomic`, `hashing`, `fold`, `lookup`, `proquint`, `geo`, `warnings`, `profiling`, `version`, `templating`, `child` | the loose modules of the same names | |
| `bytes` | `fit/bytes` (and `fit/crc` if it is general) | |
| `args` | `cli/args` (option parsing; rewritten by TODO step 9) | |
| `ui` | `ui/*` except `logfile`'s use of the catalogue, which becomes an argument | |

### Layer 1

| package | today | depends | tables |
|---|---|---|---|
| `childasync` | `childasync` | `child` | |
| `zip` | `zipbytes`, `zipchild` | `bytes`, `child` | |
| `xlsx` | `xlsx` | `zip`, `lookup` | |
| `cache` | `cache.nim`, `cache/files.nim` | `hashing`, `proquint`, `atomic` | |
| `db` (not `store`: the base fragment is recorded as `db/001-schema.sql`, and a package's fragments are named after its directory) | `db/` except `command` and `channel`: `Sql`, statements, `Store`, fragments, functions, multirow, checkpointer | `fold`, `hashing`, `lookup` | `fragment`, `user`, SpatiaLite's (owned by core, see Ownership) |
| `confirm` | the words and countdown of `user/wipe` (`describe`, `countdownLine`, `countdown`, `sayDeleted`) | `ui` | |

### Layer 2

| package | today | depends | tables |
|---|---|---|---|
| `bundle` | `bundle/unpack` | `cache`, `atomic`, `hashing` | |
| `download` | `download/*` | `ui`, `zip`, `lookup`, `atomic` | |
| `user` | `user/wipe` minus the words (`findUser`, `removeUser`, `userTables`), `user/ddl` | `store` | `user_profile` |
| `model` | `model/` minus `command`, `params`: `calc`, `impulses`, `models` | `store`, `hashing`, `fit` | `ff_model`, `impulse` |
| `web` | `serve/` minus the command: server, handler, workers, pages, request, token | `bundle`, `cache`, `childasync`, `templating`, `ui`, `store` | |

### Layer 3

| package | today | depends | tables |
|---|---|---|---|
| `fit` | `fit/` minus `command`, plus `profile/` (it is part of `fit`, see the cycle table) | `bytes`, `xlsx`, `bundle`, `lookup`, `warnings` | |
| `names` | `names/` and `landmark/` minus its command (merged 2026-11-09, see Decisions) | `download`, `cache`, `zip`, `geo`, `fold`, `db`, `ui` | `country`, `coverage`, `feature`, `country_cell*`, `landmark` |

(`fit` is placed above `bundle` because the default profile is unpacked from the bundle.)

### Layer 4

| package | today | depends | tables |
|---|---|---|---|
| `importer` | `importer/` minus `run`, `display`, `sinks`, `logsink`, plus `db/channel` (it defines `ImportStep`) | `fit`, `names`, `download`, `store`, `geo`, `hashing`, `warnings`, `profiling` | `file`, `activity`, `coords`, `segment`, `route`, `seen_file` |
| `heartrate` | `heartrate/` | `importer`, `fit`, `store` | `heartrate` |

### Layer 5

| package | today | depends | tables |
|---|---|---|---|
| `climbs` | `climbs/` minus `command`, `params` (one package for now; the `sectors` split is TODO step 14) | `importer`, `names`, `fit`, `user`, `store`, `geo` | `sector`, `effort`, `climbs_done` |
| `selection` | `selection/` minus `command`, `table`, `calendar` | `importer`, `climbs`, `fit`, `user`, `store` | `selection` |
| `delete` | `delete/remove` (the removal of activities and what is made from them) | `store` (and, after step 6, every package that makes per-activity tables) | |

### Layer 6: commands

A command package holds the command (`run`, its options, its output) and nothing else.

| package | command(s) | today | depends |
|---|---|---|---|
| `activitiescmd` | `activities` (list, `--select`, `--import`, `--delete`) | `selection/command`, `table`, `calendar`; `importer/run`, `display`, `sinks`, `logsink`; `delete/run` | `selection`, `importer`, `delete`, `confirm`, `args` |
| `climbscmd` | `climbs` | `climbs/command`, `params` | `climbs`, `selection`, `names`, `args` |
| `userscmd` | `users` | `user/command`, `params` | `user`, `confirm`, `args` |
| `modelscmd` | `models` | `model/command`, `params` | `model`, `args` |
| `landmarkscmd` | `landmarks` | `landmark/command`, `params` | `landmark`, `climbs`, `names`, `args` |
| `mapcmd` | `map` | `map/` | `selection`, `climbs`, `importer`, `web`, `bundle`, `cache`, `templating` |
| `ffcmd` | `ff` | `ff/` | `model`, `web`, `bundle`, `cache`, `templating` |
| `fitcmd` | `fit` | `fit/command` | `fit` |
| `logcmd` | `log` | `log/` | `ui` |
| `cachecmd` | `cache` | `cache/command` | `cache`, `download`, `confirm` |
| `dbcmd` | `db` | `db/command` | `store`, `download`, `confirm` |

### Changes this makes to today's code (the cycle table, made specific)

* `cli/common` is `core/globals.nim` (**done, 2026-11-09**): `Globals` (`dbPath`, `user`, `offline`, `fragments`, `log`), the exit codes, `say`, `usageError`, `failure`; `openStore(g)` is in `db/store.nim`; nothing in core imports `ui` or `db`.  `importSteps` left `Globals`; `selection/command` reads `modules.allImportSteps` until the extension point (step 5).
* `ui/logfile` stops importing `cli/catalog`: **done**; the log is `core/logfile.nim` (decided 2026-11-09: whole log code in `core`, pluggable logs are not needed; `Globals` in `core` too; `importSteps` leave `Globals`, and `selection/command` reads `modules.allImportSteps` until the extension point).
* `db/channel` (which imports `fit/time`) moves to `importer`, so `store` does not depend on `fit`.
* `user/wipe` splits in three: words and countdown (`confirm`), user lookup and removal (`user`), counting activities
  (the `activities` command, which knows about activities).
* `landmark/command` is the only thing that makes `landmark` depend on `climbs`: it moves to `landmarkscmd`.
* `climbs/attempts` → `importer/describe` and `climbs/profile` → `importer/extract` stay: `climbs` depends on
  `importer`, which is the right direction.
* `selection/command` → `delete/run`: both are inside `activitiescmd`.
* `serve` is the library package `web` (**done**): there is no `serve` command, so no `servecmd`; `ff` and `map` use it.

### Decisions (the author, 2026-11-09)

* **`landmark` is part of `names`** (later in the day, from the review of the cmd packages).  Landmarks are the author's
  own names for places and come before GeoNames when something is named, so `names` read the `landmark` table, while
  `landmark/suggest` read `names`' `feature` table through SQL: a cycle the imports did not show.  `names` is the
  fundamental package; the table, `landmarks.nim`, `suggest.nim` and the fragment (now `names/004-landmark.sql`) moved
  into it; `landmarkscmd` will depend on `names` only.  An extension point for "name sources" was considered and
  rejected as not worth it until a second kind of own name exists.  The helper `columns` (table cells in columns) was a
  second accidental edge (`landmark/command` imported it from `climbs/report`) and moved to `packages/ui/columns.nim`.
  Lesson: separating a command from its library can hide a cycle; check what the command *needs* from the other
  packages, and what the library reads by SQL.

* `store` is a package; `core` holds only types.  `Globals` still holds a `Log` and `importSteps`: the steps go with the
  extension point (step 5); where the `Log` goes is open.
* Command packages end in `cmd`; the nch command name is in `package.nim`.
* **A command is associated with one package**: `activities` (list, `--select`, `--import`, `--delete`) is one package,
  `activitiescmd`.
* `zip` (`zipbytes`, `zipchild`, 206 lines) and `xlsx` (322 lines) are small utility packages; `xlsx` has one user,
  `fit`'s profile.  Kept apart because they are different formats; merging `xlsx` into `fit` is possible.
* `climbs` stays one package in step 8; splitting it into `sectors` and `climbs` is part of TODO step 14.
* Files placed by reading them: `selection/table`, `selection/calendar` (only `selection/command` uses them) and
  `importer/sinks`, `logsink`, `display` (only `importer/run` uses them) are the presentation of `activities` and move to
  `activitiescmd`.  `importer/events` and `failure` stay in `importer` (the library emits events; the command shows them).
  `importer/naming` (names the activities at the end of an import, using `names`) and `climbs/work` (brings the climbs
  up to date; called on demand by `climbs`, `landmarks` via `report`, and `map`) stay in their libraries.  `climbs/work`
  is the on-demand work of the extension-point list.
* `selection/calendar` goes to `activitiescmd` for now; the author expects to pull it out later (like the `sectors` split).
* Still open: where the `Log` type goes (core, or out of `Globals`).
