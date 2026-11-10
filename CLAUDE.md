
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

nimchoo is a set of **packages**, so that the system can be extended with new fit-related functionality by adding a
package without editing the others (the design and its reasons: PACKAGES.md).  **what a package is for, what it owns and
its rules are in the `##` comment at the top of its `package.nim`** (not here): read it before working on a package, with
`nch packages NAME` or on the documentation site (`nimble docs`, published by github pages).  `nch packages` is the program
describing itself (packages, `--points`, `--tables`, `--graph`, `--config`); use it to see how things fit.

* a package is a directory under `src/nimchoo/packages/` that contains a `package.nim`; its **name is its directory's
  name** (unique; compared as nim compares names); directories without one only group (`text/`, `util/`).  `package.nim`
  starts with its documentation (a `##` comment: the first line is a summary of up to 100 characters; the registry
  generator refuses a package without one and says what to write) and has one constant, `package`, of type `Package`:
  `depends`, `fragments`, `commands`, `defines` (its extension points, each with a summary) and `contributes`.
* `core/` is not a package: `errors`, `ids`, the `Package`, `CommandDecl` and `Fragment` types, `Globals` and the exit
  codes, the log, `ownership.nim`, `registry.nim` (the dependency order) and `inventory.nim` (what `nch packages` shows).
* **the registry**: `nimble registry` (run first by the other tasks) writes `src/nimchoo/registry.nim` from the packages
  found, in dependency order, with their documentation; it is checked in, and a test fails if it is stale.  a cycle, a
  missing dependency, a package or command name used twice, or a contribution to a point nobody defines stops the build.
* **imports** (`tests/core/test_imports.nim`): a file imports only its own package, `core`, standard and third-party
  libraries, and the packages in its `depends`; `depends` must also name the packages whose **tables** it reads in SQL.
  only a `package.nim` imports a package's `command.nim`; its other files are libraries for the packages that depend on it.
  `db_connector` is imported by `db` (and `core/fragment.nim`) only.
* **tables** belong to the package whose fragments make them.  a package may write only its own tables and read those
  of its `depends` and of `db`; **enforced** by SQLite's authorizer when a statement is prepared (a `StoreError` names the
  package, the table and the sql).  a table is written by its owner's functions, so a command calls those.  the `db`
  package's documentation has the rest: fragments, **never edit a fragment that any database has had** (add a numbered
  file), squashing, `Sql`, the access model.
* **commands are in their packages**: a package may provide a command, in its `command.nim` (`run`, its options, its
  output; `params.nim` beside it), declared in `commands:` of its `package.nim` with a `commandName` constant; `nch.nim`
  builds the usage from the registry.  a **plural** command goes with the package that owns its type; a **singular** one
  is a package of its own unless it is plainly one package's interface.  **no command hides a cycle**: when a command
  would need a package above its own, that package defines an extension point and the higher one contributes to it.
* **extension points** (`core/extension.nim`) are for exactly that, and each package documents the ones it defines
  (`nch packages --points` lists them all with their contributors).  a command reads them with
  `g.extensions.get(point)` (it cannot import the registry).
* **tests mirror the packages**: `tests/<group>/<package>/test_*.nim` (`tests/core/` mirrors `core/`), all imported by
  `tests/all.nim`; when a package moves, its tests move with it.
* per-second data is stored per activity, as arrays; other data refers to it by time (never by array index), and the
  arrays are never changed once written (an alternative needs a reason).
* **adding a package**: make the directory, its `package.nim` (the `##` documentation, then `depends`), the files and
  tests; run `nimble registry`; if it adds tables, their fragments in `fragments:` (the package must depend on the
  packages whose tables they refer to: the build checks); if it is a command, `commands:` and a `commandName` constant.

## the shape of the commands (decided 2026-11-05)

* **a type that lives in the database has a plural command that manages the collection** (`activities`, `climbs`,
  `users`, `models`, `landmarks`): `TYPE [which ones] [action]`, with `--add NAME`, `--edit NAME ...`, `--delete NAME`.
  every `--delete` is confirmed with `-f` (with the countdown and the "would delete ..." message).  a named type takes a
  NAME; activities, which are too many to name, take criteria or the selection.
* **the selection** is what the commands that work on activities use by default (see `selection`).  **`--all` means
  everything, not just the selection**, wherever the default is the selection.  a selection belongs to one user.
* **commands about things outside the database are singular**: `map`, `fit`, `log`, `ff`, `cache`, `db`; and `import`,
  which reads files into it.
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
* **options describe themselves** (`util/args`: every option carries its names, value placeholder and help, which the compiler requires), and the option list of a command's usage is made from the descriptions (`util/args/usage.nim`, wrapped to the terminal's width, `ui/live.helpWidth`: 120 when piped), so it cannot differ from what the parser accepts.  a command's `parseArgs` gives a `Parsed[T]`: valid parameters (a variant on the action: a combination that means nothing cannot be represented), help asked for, or a problem.
* **printing uses `std/strformat`** (`fmt"climb {id} has {n} efforts"`, `fmt"{x:.1f}km"`): the whole sentence is seen at
  once and a name in the braces is checked when the program is compiled; `&` and `$` pieced together are easy to get
  wrong (a missing space, the wrong variable).  decided 2026-11-09.  the rule: **all new printing (messages, lines,
  table cells, file text) uses `fmt`**; **a file that imports `strformat` has all its existing printing converted to it**
  in the same commit (and, when the change is small, the other files of its module).  `&` stays for joining pieces that
  are actually built up (a list of parts, a path, a loop).  sql text is not printed: use `?` or an `Sql` (above).

### output

* how numbers, intervals and colours are written is in the `ui` package's documentation.  a table column carries its unit
  in its header; input never takes a unit for distance (decimal km), and `m` always means minutes.

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
