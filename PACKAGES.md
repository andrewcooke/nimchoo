# Packages

The design of packages, agreed in discussion on 2026-11-09 (it replaces the first sketch in REVIEW.md §6, which is
kept for the reasoning).  **Steps 8.1 to 8.4 are built** (the same day): `core`, the generated registry, the import
checker, inferred table ownership, every module a package, every command a package.  What is left is under "What is
built and what is left".  The text that describes how it works now is in CLAUDE.md ("general structure"); this file
keeps the design and the reasons.

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

(Built: `depends`, `fragments` and `commands` (a `CommandDecl`: name, summary, `run`; the registry's `commands` is what
`nch` dispatches on and prints in its usage).  `contributes` comes with the first extension point.  `fragments` is still
`@[]` in every package: the fragments are listed in each package's `ddl.nim` and joined by `modules.nim` (see "What is
left").  The module `core/package` is imported `as corePackage`, because the constant is also called `package`.)

The registry (below) reads it.  A package's own documentation (the feature detail now in CLAUDE.md) goes in a
`README.md` beside it.

### The registry

Generated from the package directories and sorted into dependency order (`nimble registry` runs `tools/genregistry.nim`
and writes `src/nimchoo/registry.nim`; the other nimble tasks run it first).  It fails the build on a cycle, a missing
dependency, a duplicate package name or a duplicate command name.  A compile-time scan of directories would not notice
a *new* directory, because Nim does not recompile a module whose files have not changed, hence the generator.  The
generated file **is checked in** (decided 2026-11-09), with a test that makes it again and fails if it differs, so plain
`nim c` works on a fresh clone and a stale registry cannot go unnoticed.  It replaced the dispatcher's table of
commands and the usage list; it has not yet replaced `modules.nim` (fragments, import steps).

## Layers: libraries below, commands above

Most of the cycles in the code come from a library and its *command* living in one directory.  So a package is
either a **library** (tables and functions) or a **command** package (the command, built on libraries); a library
never depends on a command package.  The cycles there were (all four broken on 2026-11-09):

| Cycle now | Cause | Resolved by |
|---|---|---|
| `cli` ↔ `ui` | `ui/logfile` needs `cli/catalog` (the list of commands) | **done (2026-11-09)**: the log (`Log`, `Level`, `LogEvent`) is `core/logfile.nim` and takes the command as a string; `ui` no longer imports `cli` |
| `fit` ↔ `profile` ↔ `xlsx` ↔ `zipbytes` | `profile` is part of `fit`; `zipbytes` needs `fit/bytes`, a general byte reader | **done (2026-11-09)**: `profile` is in the package `fit` (`default`, `load`, `model` keep their names); `bytes`, `zip`, `xlsx`, `bundle`, `cache`, `download` are packages below it; `fit/command.nim` stays in `src/nimchoo/fit/` until `fitcmd` |
| `db` ↔ `user` | `nch db` (in `db/`) uses the delete countdown (`user/wipe`) | **done**: `confirm` is a package; `dbcmd` is a command package |
| `climbs` ↔ `importer` ↔ `landmark` ↔ `names` | `landmark`'s command uses `climbs/report` and `names`; the importer's command names activities | **done**: libraries below, commands above; and `landmark` turned out to be part of `names` (see Decisions) |

(The list of the imports that made the cycles is in the git history of this file, at the commit before this one.  They
were found with a script that reads every `import`; SQL reads are not imports, see "What is built and what is left".)

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

## What is built and what is left (TODO.md step 8)

Built on 2026-11-09, in this order:

1. **Inventory** of packages and layers (settled with the author; the decisions are below).
2. **`core` and the registry**: `Package`, `CommandDecl`, the generated registry, the import checker
   (`tests/core/test_imports.nim`), table ownership inferred from the fragments and checked against SQLite
   (`core/ownership.nim`, `tests/core/test_ownership.nim`).
3. **The leaf libraries** moved into `packages/` (`util/`, `text/`, `geo`, ...).
4. **The four cycles broken** (libraries below, commands above), `ui`, `db`, `fit` (with `profile`), `names` (with
   `landmark`), `importer`, `climbs`, `selection` and the rest made packages; **every command is a package**
   (`packages/commands/*cmd`), and `nch.nim` dispatches on the registry; the `Command` enum and `cli/catalog` are gone.

Left:

5. **The extension points that remain**: import steps (heartrate adds work to every import; today
   `activitiescmd` reads them from `modules.allImportSteps`) and on-demand work (`climbs/work`).  And the question of
   how a later package adds criteria to `nch activities` (`--climb` is a direct dependency of `activities` on `climbs`
   for now): tags, or an extension point; TODO.md has both.  Each is discussed first.
6. **The access model**: SQLite's authorizer, report-only first, then writes, then reads.  The text scan of the SQL
   done by hand on 2026-11-09 (what each package reads and writes, against what it declares) found, besides the
   declarations that were then added: commands that write library tables themselves (`userscmd`, `activitiescmd`),
   `delete` writing `importer`'s tables, `user` writing the `user` table that `db` owns.  Step 6 makes this exact and
   forces the owners to do their own writes.
7. **The schema-by-several-orders test** and a `README.md` in each package (the feature detail now in CLAUDE.md).
   Together with it: the fragments to come from the registry (`Package.fragments`, in dependency order) instead of
   `modules.nim`, which then goes; and `allowLegacy` in the import checker goes (nothing in a package imports an old
   module any more except `activitiescmd` → `modules.nim`).

After this, TODO steps 9 (options carry their help) and later follow, each command being rewritten once in its final
home.

## The packages, as built

What each is for; what it depends on is in its `package.nim` (not repeated here, so that it cannot differ), and what
tables it owns is in its SQL.

* **`core/`** (not a package): `errors`, `ids`, the `Package`, `CommandDecl` and `Fragment` types, `Globals` and the exit
  codes, the log (`Log`, `Level`, `LogEvent`), table ownership, the dependency order and the usage list.
* **`util/`**: `args` (option parsing), `atomic` (files written whole), `bytes` (numbers out of bytes), `child` and
  `childasync` (child processes), `hashing`, `lookup` (`must`), `profiling`, `version`, `warnings`, `xlsx`, `zip`.
* **`text/`**: `fold` (text compared without case or accents), `proquint`, `templating`.
* **others**: `geo`; `ui` (looks, units, intervals, the live display, `columns`); `confirm` (the pause before a delete);
  `db` (SQL by name, statements, the `Store`, fragments; owns `user` and `fragment`); `cache`; `bundle` (files unpacked
  from the program); `download`; `fit` (FIT files and the profile); `names` (GeoNames features and the author's
  landmarks); `importer` (activities); `heartrate`; `model` (impulses); `user`; `climbs`; `selection` (the stored
  selection and its address); `delete`; `web` (the server `map` and `ff` use).
* **`commands/`**: `activitiescmd`, `cachecmd`, `climbscmd`, `dbcmd`, `ffcmd`, `fitcmd`, `landmarkscmd`, `logcmd`,
  `mapcmd`, `modelscmd`, `userscmd`: one command each (`activitiescmd` joins the listing, `--select`, `--import` and
  `--delete`).

## Decisions (the author, 2026-11-09)

* **Command packages end in `cmd`** (the nch command name is in `package.nim`), since a library and its command had the
  same name; and **a command is associated with one package**.
* **`core` holds `Globals`, the log and the exit codes** (G1, L1, S1 in the discussion): pluggable logs are not needed
  (the point of the packages is to extend with FIT-related functionality, not to support another platform); the
  import steps left `Globals`, and are read from `modules` until the extension point.  Commands name themselves with a
  string (`commandName`), not an enum, because they cannot import the registry.
* **`db`, not `store`**: the base fragment is recorded as `db/001-schema.sql`, and a package's fragments are named after
  its directory.
* **`landmark` is part of `names`.**  Landmarks are the author's own names for places and come before GeoNames when
  something is named, so `names` read the `landmark` table, while `landmark/suggest` read `names`' `feature` table by
  SQL: a cycle the imports did not show.  `names` is the fundamental package.  An extension point for "name sources"
  was considered and rejected until a second kind of own name exists.  The helper `columns` was a second accidental
  edge (`landmark/command` took it from `climbs/report`) and is `packages/ui/columns.nim`.
* **The selection** is two things: the stored selection (a table, the address bits, the content key; package
  `selection`, which `climbs`, `map` and `delete` use) and the search language of `nch activities` (`criteria`,
  `ranges`, which live with the command).  They were one package, and the pair made a loop: `climbs` reads the stored
  selection, and `--climb` reads `effort`.  `activities` now depends on `climbs` for `--climb`, which is not
  extensible; see TODO.md ("Criteria from other packages").
* `zip` and `xlsx` are small utility packages (`xlsx` has one user, `fit`'s profile; merging them is possible).
* `climbs` stays one package; splitting it into `sectors` and `climbs` is TODO step 14.  `selection/calendar` goes with
  the command for now and may be pulled out later.

**Lessons.**  Separating a command from its library can hide a cycle: look at what the command *needs* from other
packages and at what a library reads *by SQL*, not only at imports.  The import checker cannot see SQL; a text scan of
the SQL strings against `depends` can (it found three undeclared dependencies and one real loop), and step 6 makes the
check exact.  A name that is a module and a constant at once clashes in Nim (style insensitivity): `commandname` and
`commandName`.  Embedded files read with `staticRead` and a relative path (`NOTICE`, `data/Profile.xlsx`) break when
a package moves; `version` walks up to `nimchoo.nimble` instead.
