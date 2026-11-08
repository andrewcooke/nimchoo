# HISTORY

The finished tasks and the reasoning behind decisions, as TODO.md held them until 2026-11-08 (when TODO.md
became open work only).  **Not current guidance**: names of commands, files and modules here are those of their
time, and the "Conventions" below were superseded by CLAUDE.md.  Read it for *why* something was decided.

## Conventions

* **No compiler warnings** (checked 2026-11-04 with Nim 2.4.0, building everything from scratch with `-f`: the
  program, the debug build, the tools, the tests and `csvreport`).  Keep it so: a new warning is fixed when it
  appears (an unused import is removed; an import for its side effect is made explicit, as `useTestCache()`).
  `nimble csvreport` no longer hides warnings.

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

## Nim 2.4.0 (checked 2026-11-04; the author asked whether to upgrade from 2.2.12)

Tried without touching the installed Nim: the official `nim-2.4.0-linux_x64.tar.xz` (its published SHA-256 matched)
unpacked in a scratch folder, and a scratch git worktree of the commit built and tested with it.  **Everything
passes:** it builds with no errors and no new warnings; all 841 tests pass (the run takes 12.5 s, as with 2.2.12);
the SDK CSV comparison is 26 of 26 identical; the import of the 300-file sample takes the same time (3.8 s with
1 thread, 2.3 s with 2); and the channel close/reopen bug is gone (the nine-line program is clean under the
sanitizer).  The dependencies (zippy 0.10.20, db_connector 0.1.0, checksums 0.2.2) compile unchanged.  To
upgrade: `choosenim 2.4.0`, then `nimble setup` (to remake `nimble.paths`), `nimble prod`, `nimble test`.  The
code still works on 2.2 (`nimchoo.nimble` says `nim >= 2.2.0`) and "open the channels once" is right on both.

## Task 11: a version (done 2026-11-04)

`nch --version` prints `nch 0.1.0 (a1b2c3d)`: the number from `nimchoo.nimble` and the short git commit the
program was built from (`-dirty` if tracked files had uncommitted changes; `unknown` outside a git checkout),
both found at compile time (`version.nim`).  Nim does not recompile a module because the repository moved on,
so `nimble prod` uses `--forceBuild`.  The log's `run` line starts with `[commit]`.  Not done: the cache manifest
does not record the build; rules for when the number changes (a schema change = a new minor version?) are still
to be agreed.

## Task 10: more idiomatic Nim (a review, 2026-11-04; each item is done only when the author agrees)

Asked for: "making this more idiomatic Nim is excellent, especially if it helps; consider where else, even if
it is not performance related."  Found by reading the code (counts are from grep).  Ordered by how much each
helps; the first is done as part of Task 9.

1. **(done) Shared, immutable descriptions instead of copied strings** (decoder).  Every decoded `FieldValue` copies
   its name, units and type name; a `Spec` / field description made once per message definition and pointed at
   (`ref`, `{.acyclic.}`) is the Nim way, and removes most of the 207 million allocations.  Records are
   borrowed (`lent`, templates) not copied (`let rec = ev.record` copies a whole record per message).
2. **(done 2026-11-04)** **Cleanup by destructor, not by hand.**  `Stmt` is a ref-counted handle that finalizes itself; `Store` shares a
   connection object that closes when the last copy goes (`close` stays for an early, idempotent close, used by `destroy`).
   `MultiInsert.release` and the `Option[Stmt]`s are gone.  A statement must not outlive its connection: make it in a
   narrower scope than the store.  (AddressSanitizer: no leak or error from this; a small leak of 73 bytes per
   `openStore` from `bundle/unpack.nim` `resolve` was there before: fixed, see below.)  Old text:  25 places call `finalize`/`close` by hand, and the importer keeps
   five `Option[Stmt]` with a `try/finally` to finalize them.  Giving `Stmt` (and `Store`) a `=destroy` hook,
   and no copying, makes cleanup automatic and removes the `Option`s and the `finally` blocks.
3. **(dropped 2026-11-04: complex for no real gain)** **Names as symbols, not strings, in the hot and the branching code.**  Messages and fields are compared by
   name (`case rec.name of "record"`) and found in tables keyed by string (`hash` is 4.7% of the decode time);
   the profile could hand out small integer ids (or enums for the few we use) once, and the code compare
   those.  The same for command names (`nch.nim` dispatches on strings, `commandRules`) -> an enum.
4. **(done 2026-11-04)** **Distinct types for numbers that must not be mixed**: FIT seconds and Unix seconds (an off-by-631,065,600
   bug waiting), metres and kilometres, activity/file/user ids (139 uses of `int64`).  `type UnixTime =
   distinct int64` and the like cost nothing at run time.  Done: `FitTime` and `UnixTime` (`fit/time.nim`):
   the tokenizer, `Record.timestamp`, the extracted activities, segments, coordinates and samples use them;
   only `fitToUnix` converts, and the database is bound with an explicit `int64(...)`.  Differences are plain
   `int64` seconds.  Ids too (`ids.nim`: `UserId`, `ActivityId`, `FileId`, `ModelId`; `bindInt` takes them), and `UnixTime` for the
   listing, the heatmap, the criteria and the heart-rate readings.  Left as plain `int64` on purpose: the
   `ff` curves (arithmetic on a grid of hours, and calendar days held as UTC midnight, a third kind of seconds),
   place ids, sizes and distances.
5. **(done 2026-11-04)** **One argument parser.**  `cli/args.nim`: a command lists its options (`flag`, `text`,
   `number`, `whole`, `custom`, `listOption`) and `parseOptions` walks the arguments (`--name=value` works for every
   option; `parseLeading` stops at the command name for the options before it).  Every command uses it: ff, heatmap,
   model, user, list, log, import, fit, destroy and `nch` itself; the web options are one shared list.  Messages are as
   before except: `unexpected option/argument` everywhere, `-n` of `log` without a value says `needs a value`.  Old text:  Five commands each hand-roll the same loop (`template value(name)`, `fail`, the
   web options now shared).  A small declarative parser (options, flags, values with checks, the messages) in
   `cli/` would remove the repetition and make help and errors uniform; `std/parseopt` tokenises but does not
   do this.
6. **(reviewed 2026-11-04, not done)** **SQL with bound parameters.**  Every value put into SQL text is a number we format (typed ids, times, limits, coordinates) except the sport names, which `inValues` quotes (and has tests).  `db_sqlite` binds every parameter as text, which SpatiaLite functions (`MakePoint`, `BuildMbr`) reject where they want a number, so the places that matter cannot be bound; real binding would need `Stmt` to read rows, a big change for little gain.  Old text:  `matchSql` and friends build SQL by concatenation and quote values by
   hand (7 builders); ids are numbers so it is safe today, but parameters are the idiom (and let SQLite
   cache the statements).
7. **(reviewed 2026-11-04, no change)** **`must` (29 uses)**  All are keys that have to be there (a missing one is a bug); the places that check `in` and then `must` are in the decoder's hot paths, where `lent`/`{.cursor.}` were chosen on purpose.  Old text: works around `Table[]` raising `KeyError`.  `getOrDefault` / `withValue` / `hasKey`
   are the idiom where a default makes sense; keep `must` where a missing key is a bug.
8. **Global state in `profiling.nim`** is cast to gcsafe; fine for one thread, but threads (Task 9, step 4)
   want thread-local accumulators merged at the end.
9. **(done 2026-11-04)** **Smaller:**  the decoder already uses iterators; the one enum `case` that ended in `else: discard` over a real enum (`reader.nim`) is exhaustive now; 8 procs in the pure modules were `func`s the compiler accepts (`ff/curve`, `heatmap/lines`, `selection/ranges`...).  Old text: `iterator`s instead of building a `seq` and returning it where the caller only loops
   (`walkDirRec` results, `rows`); `func` where nothing has a side effect (the compiler checks); `case` on
   enums with no `else` so a new value is a compile error (done for events, not everywhere).

## Task 9: profile a large import and make it faster (done; added 2026-11-04)

Asked for by the author, who suspects the database more than the Nim code.  **Measure first**, then change
the biggest cost, one thing at a time, keeping the numbers in this file.

### What is known (from reading the code, not yet measured)

* **One transaction per file already** (`importFileWith` begins and commits per file: not per row).  So
  "a single commit after writing a whole file" is how it works.  The cost is what each commit does.
* **No pragmas are set** except `foreign_keys` and `trusted_schema`: the journal is SQLite's default
  (rollback journal, `synchronous = FULL`), so **every commit waits for the disk twice or more**, for each
  of thousands of files.  **WAL with `synchronous = NORMAL`** commits without waiting for the disk each time
  (it is still safe against corruption; a power cut can lose the last commits, which a re-import repeats).
  WAL adds transient `-wal`/`-shm` files next to the database (`nch destroy` already removes them).
* **Which build is being used?**  A debug build is about 5 times slower than `-d:release` (see the note on
  the test task).  The `nch` that `nimble build` makes is a debug build unless asked: check this first.
* Other suspects: SHA-256 of every file in pure Nim (`checksums`); decoding; the nearest-place search
  (a SpatiaLite query, with a widening box, per activity); the spatial indexes (`route`, `activity.start`)
  updated on each insert; the heart-rate rows (about as many as the coordinates); `seen_file` batches.

### Plan

* **Measurements (2026-11-04).**  Sample: every 13th of the author's `.fit` files in `~/fit`: 300 files, 19 MB
  (129 of them are monitor files with no activity; 167 import).  Release build; `NCH_PROFILE=1 nch import ...`
  prints the table (the timers are `profiling.nim`, `timed "phase": ...`).  /tmp is tmpfs here, where fsync
  is free, so the database must be on the real disk (btrfs) to see commits.

      phase (ms)          journal (default)   WAL + synchronous=normal
      decode                    5033                  4777
      commit                    2988                   595
      route: insert              ~2300                1943     (GeomFromText + the R-tree index)
      insert coords               541                   521
      step: heart-rate            488                   445
      route: text                 ~350                  348
      hash                        124                   117
      nearest place                91                    87
      total                     11799                 ~9000

  **WAL is done** (`store.openStore`): commits fell from 25% to 6% of the time.  What is left is the
  decoder (53%: gprof says about 30% of the whole run is the allocator: 207 million allocations for 19 MB,
  because every decoded value copies its name, units and type name as strings and records are copied),
  and putting the route in (21%).
* **More detail (same sample, WAL, real disk; two runs gave 8.9 and 9.0 s).**  Per call: decoding a file takes
  16 ms on average (the event loop 14.5 ms and putting the activities together 1.7 ms), the route insert
  11.5 ms, a commit 3.5 ms, the coordinates 3.1 ms, the heart-rate rows 2.6 ms, hashing 0.4 ms.  By size of
  file (the 171 that reached the database; the 129 monitor files fail after decoding and are in the phase
  table only):

      files by size       files   imported        MB      ms   ms/file    ms/MB
      under 10 KB            11         11       0.1      86         7     1277
      10 - 50 KB             71         68       1.7     819        11      470
      50 - 200 KB            54         53       4.8    2078        38      432
      over 200 KB            35         35      11.6    5589       159      481

  So cost goes with size, about 430-480 ms per MB (2 MB/s) once a file is over 10 KB, and a small file costs
  about 7 ms whatever its size.  The full 3,909 files (320 MB) would take about 150 s now.
* **Decoder allocations (2026-11-04): done.**  A value now points at one shared `FieldMeta` (name, units, type
  name, kind, base: `{.acyclic.}` ref, made once per field of a message when a definition is first seen) instead
  of carrying copies; `interpret` and `decodeField` add to a `seq` they are given (no `Option`, no `seq` per
  value); the per-record tables (references for dynamic fields, the names for removing duplicates) are made
  only when the definition needs them (`hasDynamic`, `mayDup`); `extract` borrows the record (`template`) and
  does not copy it.  Same sample, WAL, real disk:

      phase (ms)            before   after
      decode                  4779    1873      (the event loop 4280 -> 1453)
      route: insert           1923    1869
      commit                   583     585
      insert coords            520     507
      step: heart-rate         438     427
      total                   8886    5870

  Cost by size is now about 275-325 ms/MB (was 430-480).  Checked: the 824 tests, the SDK CSV comparison
  (26 of 26 identical), and the CSV and warnings of 60 of the author's own files from `nch fit` (old and
  new builds: 0 differ).  Next in the table: putting the route in (31%).
* **Route as bytes (2026-11-04): done.**  Measured in SQL first: SpatiaLite takes 1,890 ms to parse the text
  of 166 routes (668,000 points) and 20 ms to read the same as WKB; the spatial index costs little.  The
  importer now builds the route as OGC **well-known binary** (`route.routeWkb`: byte order, type, counts,
  doubles; not SpatiaLite's own blob format) and the database reads it with `GeomFromWKB`
  (`statement.bindBlob`).  Points keep full precision (the text rounded to 7 decimals).  Same sample:
  route 2,200 -> 51 ms (insert 1,869 -> 31, the building 333 -> 20); **total 5,870 -> 3,898 ms** (8,886
  at the start; about 65 s for the 3,909 files).  Now: decode 51%, commit 14%, coordinates 13%, heart rate
  11%.
* **WAL checkpoint interval (2026-11-04).**  Commit time on the sample, by `wal_autocheckpoint` (pages): 1,000
  (default) 597 ms, 10,000 364, 100,000 216, never 211; a bigger page cache changed nothing.  Set to **20,000**
  (an 80 MB log at most).  **What the decoder still costs (gprof):** 48 million allocations for the 300 files
  (207 million before), about 7 for each of the 7 million field values: `basetype.decode` returns an `Option`
  holding a `seq`, `interpret` copies it into `vals` and again into the value.  Next: decode in place into the
  value (1-2 allocations a field), and find why 700,000 of the 766,000 records take the duplicate-name path
  (`mayDup`).
* **Decoder, second pass (2026-11-04).**  Read the numbers straight into the value (`basetype.readInt/readFloat`,
  no `Option`/copy chain); the field-name accessors return `lent` (they copied the name on every comparison:
  12.7 million copies a run); the plan no longer copies the profile's message and fields for every definition
  (`Slot` holds the few scalars the plain path needs, `withValue`/`{.cursor.}` look at fields in place, and the
  shared descriptions are cached per decoder); `extract` gives each session its samples as one slice (it hashed
  "heart_rate" for every sample); the duplicate-name check allocates nothing when there is no duplicate.
  Decode 1,908 -> 1,510 ms, total 3,380 -> ~3,000 ms; string copies per run 42 -> ~15 million, allocations
  48 -> ~30 million.  Checked as before (827 tests, the SDK comparison, and now 100 of the author's files
  through `nch fit`: 0 differ).  The decoder is now at the point of small returns; what is left is mostly the
  cost of a function call and a few lookups for each of 7 million fields.
  **Threads (the target machine has 16 cores)**: decoding is 50% of the run and independent per file; the
  writer (coordinates 17%, heart rate 14%, commit 7%, hash, nearest place) is then the limit, so the next
  steps are a pool of decoders + one writer, with the hashing, the route bytes and the nearest-place query
  (WAL allows readers) moved out of the writer, and then batching the row inserts.
* **Threads: the design (proposed 2026-11-04, agreed in outline).**  Target machine: 16 cores (this VM has 4).
  Only one thread (the main one, the writer) ever touches the database.  Workers take numbered jobs and do
  everything that needs no database: read, hash, decode, assemble the activities, build the route bytes; each
  loads its own copy of the profile (no objects shared) and sends back one result (the activities, or the
  failure with its kind and message, and the warnings).  The writer takes results in file order (a reorder
  buffer, with a bounded number of files in flight) and does what `importFileWith` does now: the "known?" check,
  one transaction, the inserts, the events -- so output and log are unchanged and `--jobs 1` and `--jobs 8`
  give the same database and events (a test).  `nch import --jobs N` / `-j N` (default: the number of cores,
  capped at 8 at first; `--jobs 1` runs the same code without threads).  Workers get the file hashes already in
  the database, loaded once, and skip decoding a known one.  Ctrl-C: the writer finishes its file, workers stop
  at their next, the seen-files record is saved.  `NCH_PROFILE` keeps a table per thread and merges them.
  Dependency: `threading`'s `Chan`, or the built-in `Channel` (deprecated) if a spike shows it works under ORC.
  Steps: (1) split the importer into a pure `decodeFile` and a `writeDecoded`, still single-threaded
  (no change in behaviour); (2) the worker pool with the ordered hand-back and `--jobs`, with the equality tests,
  a bad file in the middle, the same file twice, an interrupt, and a file that changes during the run;
  (3) per-thread timers, measure on 1, 2 and 4 cores; (4) if the writer is then the limit: the nearest-place
  query out of it, and batched row inserts.
  **Step 4, first part (2026-11-04): many rows to a statement.**  `db/multirow.nim` (`MultiInsert`: statements of 128
  rows, made once for each size) is used for the coordinates and the heart-rate rows.  Coordinates 507 -> 296 ms,
  heart rate 432 -> 220 ms on the sample; wall time, 1 thread 3.84 -> 3.34 s, 2 threads 2.4 -> 1.96 s.  The size
  was tried: 32 and 128 rows are alike, 512 and 1000 are slower (more to prepare and bind at once).  Tests:
  `tests/db/test_multirow.nim` (0, 1, 127, 128, 129, 255, 256, 257 and 1000 rows, NULLs, an error), and the
  threads-equal-sequential tests cover the rest.
  **Step 2 done (2026-11-04):** `importer/work.nim` (`prepareFile`: read, hash, decode, a failure is data),
  `importer/pool.nim` (the workers, two channels, results taken back in file order), `batch.nim` uses them,
  `nch import -j N` (default: processors, at most 8; 1 = no threads), per-thread timers (`takePhases`).
  `tests/importer/test_pool.nim`: the same database (ids included) and events for 1, 2, 3, 4, 8 and 16 threads
  with many files, real files, duplicates, bad and unreadable files.  Sample (300 files) on this 4-core VM:
  3.85 s with 1 thread, 2.5 s with 2, 2.6 s with 4 (the writer is then the limit).
  **The cost of keeping file order (measured, 300 files):** the writer waits for the next file in order, while others
  are ready, about 10% of the clocked time with a window of `2n+2` files and about 4% with 64 (0.1 s of wall time
  at best); it is never starved (no wait with nothing ready), so the **writer is the limit** and writing in the
  order of arrival would not help.  Kept the order; window now `4n+8`.  Timers `wait: order` and `wait: workers
  busy` stay in the `NCH_PROFILE` table.  Checkpoint interval re-checked in wall time (1 thread): 1,000 pages
  4.4 s, 20,000 pages 3.9 s, 100,000 pages 3.9 s.  Outside the profile's clock a run spends 0.22 s closing the
  database (the last checkpoint); a benchmark that makes a fresh database also spends 0.54 s on the places.
  **Lessons:** (1) Nim's built-in `Channel` frees its buffer on `close` but keeps the pointer, so opening it again
  frees it twice (a nine-line program shows it under `-d:useMalloc -fsanitize=address`; silent in a normal
  build): the pool opens the channels once and never closes them.  **Already fixed upstream** (nim-lang/Nim
  #26230, 2026-09-15; in Nim 2.4.0 of 2026-10-27, not in 2.2.14): no report needed; we run 2.2.12, and
  "open once, never close" is right on both.  Run threaded code under the sanitizer
  (`nim c -d:useMalloc --debugger:native --passC:-fsanitize=address --passL:-fsanitize=address`).
  (2) A refactor made a duplicate file (same content as one imported earlier in the run) get decoded and report
  its warnings: the sequential path asks the database before decoding, and duplicates report no warnings.
  (3) Tests run with a time limit; `NCH_TEST_TIMES=1 ./tests/all` lists the slowest tests.
  **Step 1 done:** `importer.nim` has `decodeFile` (no database; raises as before; warnings in `ws`; builds the
  route bytes), `knownFile` (the hash check) and `writeDecoded` (one transaction), and `importFileWith` is
  their composition (so nothing else changed).  Timing unchanged (about 3.0 s on the sample).
* **Step 1: a way to measure.**

  Phase timers in the importer (read and hash, decode, each table's inserts,
  nearest place, commit), switched on by an environment variable and written to the log or stderr; a
  repeatable benchmark (a directory of real files into a fresh database, several runs) as a nimble task.
  Record the first numbers here.
* **Step 2: the cheap, large things**, each measured alone: release build (and `-d:danger`), WAL plus
  `synchronous = NORMAL`, `cache_size`, `temp_store = memory`.
* **Step 3: transactions.**  Several files per commit, using a savepoint per file so a bad file still
  rolls back alone; commit every N files or every few seconds (and at the end and on Ctrl-C).
* **Step 4: whatever the numbers then show** (hashing, the nearest-place query, bulk inserts and the order
  of index creation, decoding on several threads).
* **Decisions (2026-11-04):** WAL with `synchronous = NORMAL` is fine (it is hidden from the user anyway; the
  author has found it helps before).  Several files per commit may be tried but is expected not to help much
  (one file is already a big chunk): only if it measurably helps, and not if it is messy.  **Data types may be
  changed; changing tables is discouraged and needs discussion** (the modular, incremental approach is worth
  keeping) -- but changes that **normalise or remove duplication are welcome** (candidates: the `route`
  geometry repeats the points of `coords`; `coords.alt` is always empty).  **Threads are fine** (WAL makes
  SQLite and threads safer).  **For later, in space management of the cache: include database clean-up**
  (`VACUUM`, a WAL checkpoint, and the like) beside the clean-up of old files in `user/`.
* **Data for profiling:** the author's own FIT files in `~/fit` (3,909 files, 320 MB; median 15 KB, largest
  728 KB): read only, imported into scratch databases and a scratch cache under `/tmp`, never into the
  author's database or cache, and never copied into the project.

## Task 8: one palette, the selection in the list, a calendar view, the cache split and templates (done)

Asked for on 2026-11-04 as a batch of independent ideas; questions answered the same day.  Each step is
done only when the author confirms it.

### Decisions

**A. One palette.**  The TUI uses five colours: **white** (the default text colour), **grey**, **red**,
**green**, **yellow** (an ANSI yellow, which some terminals draw as orange).  They are named in one
module (`ui/palette.nim`) and everything else says "green", never a terminal code, so a palette can be
replaced in one place.  (Different backgrounds are not wanted, but the abstraction should allow them.)
* The same palette gives the hex values the web pages use (fitness green and fatigue red in the chart are
  the TUI's green and red).
* Grey stays the terminal's "dim" attribute for now (an explicit grey may be tried later).  Bold stays a
  modifier.  The unused blue, magenta and cyan go.  The palette is code only, not a file.

**B. The selection in the list.**  A row of the list display that is also in the selection is **yellow**
(the whole row); with `--show` or `--save` every row is.  Otherwise rows are white.  Yellow already marks
a zero distance or active time (a warning): that dual use stays, deliberately (yellow is the colour that
stands out from both white and grey).  Transition (dim) rows stay dim.

**C. A calendar view** of the list (`nch list ... --calendar`; the criteria and `--save` work as now).
* One row per month: the month's 3-letter name, then the days `01`..`31`, each in a 3-character cell, set
  in the column of its weekday, so days line up vertically.  **Weeks start on Monday.**  A header of 3-letter
  weekday names is repeated across the top (a month can need 37 cells, so the header repeats 5 and a
  third times; about 111 columns with the month name and the year).  The **year is at the right end of
  every row**.
* Colours: **white** = a day with a matched activity (matched by the criteria); **yellow** = matched **and**
  in the selection (if any activity of the day is selected, the day is selected); **grey** = a day with no
  matched activity.  Several activities on a day are just a day with data.
* Days are the **user's local timezone** (everything displayed is local; UTC is only internal).
* Only months with data are shown; **`--verbose`** shows every month from the first to the last.
* Too narrow a terminal: print a warning (in yellow) and truncate each line.
* Without colour (a pipe, `NO_COLOR`): the cells are **5 wide** and carry marks so nothing is lost: a day with
  data `"  12 "`, a selected day `" [34]"`, a day with none `"  -- "` (each with its leading space).  With
  colour they are 3 wide (the 2 digits and a space).  So the width differs: about 111 columns with colour,
  about 185 without.

**D. The cache is split, bundled files are unpacked, pages come from templates.**
* `<cache>/user/` holds what commands generate (GeoJSON, CSV, pages); `<cache>/system/` holds what is
  unpacked from the executable.  `server-token` stays at the top, and so does the **manifest** (below).
  Files already in the cache root are ignored (a clean-up command comes later).  The server serves only
  `user/`.
* **Bundled files unpacked into `system/`:** `Profile.xlsx` (the FIT SDK profile), the cities list, the
  `NOTICE` text, the page **templates**, and a small file of the **library versions** (Leaflet, d3, Plot,
  tile URL, with their integrity hashes), so a library is upgraded by editing one file.  Not the SQL
  schema (it must match the code; its checksum is checked).  Leaflet, d3 and Plot themselves still come
  from the CDN.
* **Replaced files are noticed and used:** the manifest records the hash of each file as it was unpacked.
  A file that still matches is untouched, so a newer bundled version replaces it silently; a file that
  differs was changed by the author (say, a newer SDK profile) and is **used as it is and never
  overwritten**.  A missing file is unpacked again, so `system/` can be deleted safely.
* **Templates:** the pages (heat map, chart) become template files in the source, packed in the binary,
  unpacked to `system/templates/`, and filled in at run time from the cache.  The engine is our own, a
  mustache-compatible subset (`{{name}}` escaped, `{{{name}}}` or `{{&name}}` raw, `{{#flag}}..{{/flag}}`
  and `{{^flag}}..{{/flag}}`), about 80 lines; a library with more (conditionals, loops) may be wanted in
  the long term.  The values are the user's preferences, the data file's name, and the library versions.
* **Places are informational, so a changed cities list reloads them without destroying anything** (the author's
  reasoning: they are not needed for integrity, and others agree): the
  hash of the list loaded is kept in the database; when the list in use (embedded, or a replaced file)
  has another hash, the places are replaced and every activity's nearest place is worked out again.
  This takes the cities data out of the places fragment's checksum.

### Plan

* **Step A: the palette** -- built.  `ui/palette.nim` has `Color` = `white, grey, red, green, yellow`, with
  `terminalCode` (white none, grey `ESC[2m`, then `31`, `32`, `33`), `resetCode` and `hex` (for pages).  A
  `Look` is now `(colour, bold)`; there is no separate `dim` (grey is it) and no `cNone`/`cRed`... (they
  are `white`, `red`...).  `span(text, colour = white, bold = false)`.  `style.nim` re-exports the palette
  and draws lines from it; `ff/page.nim` takes the fitness and fatigue colours from `hex(green)` and
  `hex(red)`.  The heat map's route colour (`#c2185b`) is not a TUI colour and was left.
* **Step B: the selection in the list** -- built.  `ListRow.selected` (from `rowColumns`: the activity is in the
  current user's selection); a selected row is yellow all through (unrecorded `-` cells too), a transition
  row stays grey, the header stays white.  After `--save` every row is selected, so every row is yellow.
  The last line says why: `done: 1112 of 1112 activities, 35 match selected, 57,529.0km, 114d08h22m`, the
  ", 35 match selected" in yellow, when any row is selected (`footerLine`).  The final report line of a command
  starts `done: ` (as the end of an import does): `nch list`'s last line and `nch destroy`'s `done: deleted ...`.
* **The `nch` the author runs is a release build** (`nimble prod`: `nim c -d:release -o:nch src/nch.nim`);
  build that one for use.  `nimble build` and plain `nim c` make a debug build, which is about 5 times slower.
* **Step C: the calendar view** -- built.  `selection/calendar.nim` (pure: rows, zone, screen in; styled lines out),
  `nch list --calendar` (a display option that goes with `--save`, `--show` and any criteria; `-v` shows
  every month from the first to the last).  As asked, with these details: the weekday header is **two
  letters** (`Mo Tu ...`; a three-letter name does not fit a 3-character cell), the **year is on every
  row**, 37 cells a row; the same last line (`done: ...`) follows.  `Screen` (colour, width) is passed down
  from `run` (`isatty` and `terminalWidth`); a width of 0 means no limit (a pipe).  Tested with fixed dates
  and fixed-offset zones (`tests/support/zones.nim`).
  **Changed after trying it (2026-11-04):** green and red were tried for the days and given up: they are **white**
  (listed) and **yellow** (also selected), grey if none (`calendar.dataColour`, `selectedColour`); the footer's
  ", N match selected" takes the colour the selected ones have in that display; a
  **last line warns** when months were left out: `warning: 37 months with no activity not shown; use
  --verbose to show them` (yellow; `skippedMonths`).  The names of the months either side of a gap are yellow (a `*` after them without colour).
  **Grey is now a fixed dark grey, 256-colour 240 (`ESC[38;5;240m`)**, not the terminal's "dim", in the
  palette (`terminalCode(grey)`; 238 is darker, 242 lighter, `ESC[90m` is the theme's bright black).
* **Step D: the cache split, system files and templates** (the largest), in sub-steps, each a commit:
  D1 `user/` and `system/` directories (`cache.nim`, the server, the commands) -- built: `userDir`/`systemDir`
  (pure, in `cache.nim`), `makeCacheDirs` (in `serve/pages.nim`) makes both; `heatmap` and `ff` write into
  `user/`; the server serves only `user/` (`ServerConfig.cacheDir` is that directory) and keeps `server-token`
  at the top; nothing is written to `system/` yet (D2).  Old files in the cache root are ignored;
  D2 the manifest and unpacking of `Profile.xlsx`, the cities list and `NOTICE`, with replaced files used --
  built: `bundle/unpack.nim` (`Bundle{name, data}`; `decide` and the manifest are pure; `resolve(top, bundle)`
  or `resolve(bundle)` for the environment's cache; the manifest is `<cache>/manifest`, lines `hash  name`).
  A missing file is unpacked; one as unpacked is replaced by a newer built-in; one that differs (or has
  nothing recorded and is not the built-in) is the author's: used as it is, never overwritten; an unusable
  cache falls back to the built-in copy.  Used by: the default profile (`profile/default.nim`:
  `defaultProfile()` gives a note when the author's is in use, or falls back to the built-in with a note when
  it cannot be read; `nch import` says the note at the end, `nch fit` on stderr), the places list
  (`places/data.nim`: `placesList()`, gzipped or plain, an error naming the file if it cannot be read;
  used when a database is made), and `NOTICE` (`unpack.noticeBundle`: unpacked whenever anything else is, and by
  `makeCacheDirs`).  A changed
  places list is not noticed by a database that exists (D5).  **Tests must not touch the author's cache:** `tests/support/env.nim` points `NCH_CACHE` at a temporary
  directory, and a test that changes it calls `useTestCache()` afterwards (never `delEnv`): a first run without that
  left `cities-test.tsv` in the real `system/` (removed by hand).  `hashing.nim` replaced five copies of the hex
  SHA-256.  `tests/support/env.nim` gives the tests a cache directory of their own;
  D3 the template engine (pure, tested) -- built: `templating.nim`, a Mustache subset: `{{name}}` (HTML-escaped),
  `{{{name}}}` / `{{&name}}` (raw), `{{#name}}..{{/name}}` (shown for true, a non-empty text, or once per item
  of a list, whose items have values of their own and see the values around them), `{{^name}}..{{/name}}`,
  `{{! comment }}`; a section tag or comment on a line of its own takes the line with it.  Values are
  `text()`, `flag()`, `list()` in a `context()`.  A name nothing has, a tag not closed, sections that do not
  match: `TemplateError` with the line (a kind of `NchError`).  Parsed once (`parse`), filled in with
  `render`.  `htmlEscape` now lives here (`serve/pages` re-exports it);
  D4 the heat map and chart pages as templates, with the library versions file -- built: `heatmap/page.html` and
  `ff/page.html` (Mustache, see D3) are built in and kept as `system/templates/heatmap.html` and `ff.html`;
  `serve/libraries.txt` (`name = value` lines: the CDN addresses and integrity hashes of Leaflet, d3 and
  Plot, and the tile address) is kept as `system/libraries.txt`, and every name in it is a value in every
  template (`{{leaflet-js}}`).  `pageHtml` resolves both through the bundle (the author's files win);
  `renderPage` is the pure form.  Other values: `title`, `data`, and for the chart `hourly`, `green`, `red`
  (the palette's).  A mistake in an edited template is reported by the command with the line, and says
  which files to delete to go back.  The server's content-security policy is still fixed (unpkg.com for
  scripts and styles, tile.openstreetmap.org for tiles), so a library from another host needs it changed in
  `serve/handler.nim`.  (This also removed a stale second copy of the chart's script, left in the page by the
  zoom edit; it did nothing.)  `serve/pages.nim` no longer has `fill`/`replaceAll`;
  D5 reload the places when the list changes, and repoint the activities -- built.  A fragment can now have
  **replaceable data** (`Fragment.version`, `reseed`, `withReseed`): the data are not in its checksum; the
  database records which version it has (`fragment.seed_version`, a column added to old databases) and when
  the version wanted (a proc, worked out at each open) differs, `reseed` runs in a transaction, or the open
  fails naming the cause and the database is as it was.  For the places, the version is the SHA-256 of the
  list in use (`placesVersion`, from `resolve(...).hash`), and `reloadPlaces` drops and remakes the places and
  their spatial index and points every activity with a start at its nearest place again (nothing else is
  touched).  **Databases made before this are accepted** (`withLegacy`: the checksum that included the
  list, taken to have the program's own list): tried on a copy of the author's 475 MB database, it opened
  in 34 ms and migrated its record with no reload.  Opening a database now resolves the places list (about
  10 ms: it reads and hashes the file), and unpacks the cache's `system/` files the first time.

## Task 3: `nch heatmap` (GeoJSON) and a local web viewer (done)

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

## Task 7: training impulse, fitness and fatigue (done; the findings and plan are kept below)

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
  days (the day-end values from the first day with an impulse) on which it was higher, in one line:
  `2026-11-03 15:00  fitness: 71.5 (top 4%),  fatigue: 18.5 (top 56%)`, the number and the "top" part
  coloured (fitness green, fatigue red; `ff/stats.nim` and `curve.standingAt`, pure); "top 4%" means 4%
  of earlier days were higher.  "Latest" is the last whole hour for today (labelled with the date and
  time), or the end of the last day if `--to` is earlier (labelled with the date).  The value is scaled by the scale options; the share is not.  This
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
      nch user --add NAME [--fthr N]     make a user (never implicit: a typo must not make one)
      nch [--user NAME] user --fthr 154     set FTHR (of the current user)
      nch [--user NAME] user --clear-fthr
      nch [--user NAME] user --rename NEW

  Names: 1-32 characters, letters, digits, `_`, `.`, `-` (not first): they appear in `--user` and
  in comma-separated lists (`--users a,b`).  The `default` user cannot be renamed (it is made again
  whenever a database is opened).  FTHR is a whole number of bpm, 80 to 230.  `nch destroy --user`
  already removes a user.  Changes are logged (event `saved`).

  **As built** (`user/`: `001-schema.sql`, `ddl.nim`, `params.nim` pure, `command.nim`): exactly the
  above.  `nch user` lists `user fthr activities` (activities counted per user, with commas;
  FTHR `-` if not set); `--add NAME [--fthr N]` makes a user; `--fthr N`, `--clear-fthr`,
  `--rename NEW` act on the user given by `--user` (the default user if none) and may be
  combined; a bare `NAME` is refused and the message says to use `--add NAME` or `--user NAME`.
  A user is refused if the name is taken; `default` cannot be renamed; `nch --user nobody user ...`
  says there is no such user and makes nothing.  Names and FTHR are checked before the database is
  opened.  The FTHR change that must clear impulses is not there yet because there are no
  impulses: it goes in with step 3.

**Default user, changed after step 1:** `user.is_default` (a partial unique index: at most one is 1)
marks the user commands work on without `--user`.  An empty database gets one called `default`,
flagged; if the flagged user is deleted and others remain, the oldest becomes the default.  So the
default can be renamed.  `nch [--user NAME] user --default` moves the flag (`--add NAME --default`
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

## Task 4: one vocabulary for the log and the screen, and `nch log` (done)

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

### Ideas, and what became of them (checked 2026-11-04)

Built:

* Read the data back: `nch list` (the table, `-v`, `--calendar`, the selection); no separate `nch activities`.
* Channel modules: heart rate (`heartrate/`, through the importer's step list).
* `nch log`: the log, coloured like the screen, filtered by word, `--last`, `-n`.
* Maps: `nch heatmap` (GeoJSON and a Leaflet page), with the web viewer.
* Training load: `nch model`, `nch user --edit NAME --fthr`, `nch ff` (fitness and fatigue).

Still open, roughly in the order they would help:

1. **Named places** (high priority): `nch place add home LAT LON`, then `list --near home`; later perhaps
   looked up by name over HTTPS (OpenStreetMap's Nominatim: needs OpenSSL, a polite user-agent and at
   most one request a second; cache the answer in the database).
2. **`nch model`**: `--edit NAME` and `--remove NAME`, in the pattern of `nch user` (the target after
   the command, never a guess).
3. **More channels**: cadence, power, distance as `(activity_id, t)` tables, then laps and events, each a
   module with its own `sql/` and an `ImportStep`.
4. **More exporters**: GPX (a `<trkseg>` per segment) and the like, for external mapping and plotting
   services (preference: do not plot locally; generate input files).
5. **`nch ff`**: a fitness-minus-fatigue column; FTHR and models per sport.
6. **`nch log`**: a filter by level (INFO / WARN / ERROR).
7. **Look**: a light and a dark theme.

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

### Import "chunking" (numbers update, pause, update...)
Cause (full `~/fit`, `-j 4`): the writer stopped for SQLite's own WAL checkpoint every 80 MB (longest
commit 352 ms), and the window of `4n+8` files was too small for many tiny files behind a big one.
Fix: a second connection on its own thread (`db/checkpointer.nim`) does passive checkpoints once the
log passes 8 MB (the writer's autocheckpoint is off during an import); the window is bounded by
bytes (48 MB, 256 files) not file count.  Result: longest commit 352 -> 65 ms, longest order wait
44 ms; total time unchanged (22.6 s: the writer is the limit).

## Monitor files in `nch import` (2026-11-04)

A file that has no session and whose `file_id` type is not `activity` (monitoring_a/b, and types the profile
lacks, like Garmin's 44) is a **monitor** file: counted on its own (`11709 monitor`, grey in the live display),
not a failure, nothing printed per file, not logged one by one (the `done` line has the count), remembered in
`seen_file` as kind `monitor` so a re-run skips it, and the exit status ignores it.  Files that do not say what
they are (no `file_id`, or type `activity`) and have no session are still `no activity` failures.  Rows from
before are labelled `no activity` until a `--slow` run reads them again.  `nch user --create` is now `--add`.

## `nch empty` and `nch user --remove` (2026-11-04)

`nch destroy` is gone.  `nch [--user NAME] empty -f` deletes all the data of a user (the default user without
`--user`): their files, activities, selection and everything under them; the user and their FTHR stay.
`nch empty --all -f` deletes the database file (every user), and cannot be combined with `--user`.
`nch --user NAME user --remove -f` deletes the user and everything they have (acts on the current user, like
`--rename`); if it was the default another user becomes it.  Both need `-f` and count down 5 s on a terminal.
The code is `user/wipe.nim`; `userTables` lists the tables that `empty` clears, and a test fails if a new table
with a `user_id` is left out of it.  Two schema comments (`importer/001-schema.sql`, `places/001-schema.sql`)
still say `destroy`: they are not edited because a fragment's checksum covers its comments.

## Management commands name their target (2026-11-04)

`nch --user NAME` is for the commands that work on a user's data (list, import, ff, heatmap).  The management
commands take their target after the command and never guess: `nch user --add NAME`, `--edit NAME` (with
`--fthr`, `--clear-fthr`, `--rename`, `--default`), `--remove NAME -f`; `nch empty --user NAME -f` (the data,
the user stays), `empty --all -f` (the database file), `empty --cache` (the generated files in `user/` of the
cache; needs no `-f`: they are made again).  `--user` before either command is an error that says where it
goes.  `model` should follow the same pattern when it gets `--remove` and `--edit`.

## The leak in `bundle/unpack.nim` (fixed 2026-11-04)

`resolve` made its result from the program's copy at the top and then `return`ed a different value on
most paths; the hash string (64 characters, 73 bytes with Nim's header) of the first value was never freed,
once for each time a database was opened (found by AddressSanitizer: 59 leaks in the store tests, 0 now).
`resolve` now keeps the program's copy in a separate variable and only ever returns a value.  Lesson: in
`{.gcsafe.}` procs with many early returns, do not fill in `result` first and then return something else.

## Task 12: altitude and climb detection (planned 2026-11-04, from reading choochoo)

### What choochoo does (py/ch2/data/climb.py, data/elevation.py, pipeline/calculate/{elevation,climb}.py, srtm/)

* **Elevation per point.**  Three sources: the device's barometric altitude; an SRTM1 terrain model (30 m
  tiles `N45W123.hgt`, bilinear interpolation, tiles downloaded by hand from NASA/USGS: a login is needed
  and automating it failed); the raw GPS altitude.  With SRTM the elevation is the terrain smoothed along
  the route by a smoothing spline (scipy `UnivariateSpline`, `s = n * 3`), and the gradient is its
  derivative (median of 5).  With a barometer (special-cased for the Edge 130) the altitude is used and
  shifted by the difference of the medians from SRTM; if the SD of the difference is over 10 m the SRTM
  data replace it.  GPS-only altitude is the last resort.
* **Climb detection** (`find_climbs`), on distance and elevation:
  1. resample to even steps of distance (the median step);
  2. score of a candidate (start, end) = `gain / (distance_m ** phi)` (phi 0.7 in the code, 0.6 in the
     docs: 0 is pure gain, 1 is pure gradient); a candidate needs gain >= `min_elevation` (80 m) and
     gradient >= `min_gradient` (3 %);
  3. greedy: take the best candidate in the data (O(n^2); for long rides first search every 10th point,
     then refine around the hit), then recurse on the part before and the part after;
  4. a found climb is checked for a **reversal**: if the biggest descent inside it exceeds `max_reversal`
     (10 %) of the gain it is split either side of the descent and each part searched again; climbs
     steeper than `max_gradient` (40 %) are dropped as errors;
  5. a climb is its end time, gain, distance, duration, gradient, and a category from the gain
     (80 m: 4, 160: 3, 320: 2, 640: 1, 800: HC).
* **Sectors** (later addition): climbs are made global.  A climb found on one ride is a `SectorClimb` with
  its route; a climb on a later ride that mostly overlaps an earlier one (under half of its length is
  outside the other's hull, both ways) is dropped as the same climb, so "my climbs" are a catalogue and
  each ride gets a journal row per climb it covers (time, power...).  This needs PostGIS functions.

### What nimchoo has

`coords.alt` (metres, `enhanced_altitude` else `altitude`, nullable), `lon`, `lat`, `t`; the activity's total
distance; no per-point distance, no smoothing, no terrain model.  In the 300-file sample 150 of 167 activities
(90 %) and 83 % of the points have an altitude, ranging 37 to 2444 m.  SpatiaLite has the spatial functions the
sector step needs.  No SRTM tiles are on this computer.

### Decisions so far (author, 2026-11-04)

* Start with the device's altitude (the early data from a low-spec watch may lack it: those activities simply
  have no climbs); a terrain model comes later (Copernicus GLO-30, see step 8).
* Climbs **persist** and form a **catalogue** used to compare times across rides; this is the start of
  "segment time management", so the catalogue is general (a climb is one kind of sector).
* Detection does **not** cross a timer pause: a climb lies inside one `segment` (timer stretch), because the
  time over it must be continuous.

### How choochoo matches a ride to a stored climb (data/sector.py), which we copy

A sector has a route, a **hull** (the route buffered by 25 m with flat ends) and **gates**: a start line and a
finish line, 25 m each side, across the route at its ends.  A ride matches if it passes through the hull; its
start and finish times are where it crosses the gates (the position along the ride is found, and the time
interpolated); of the possible pairs of crossings the shortest is taken, and it counts only if the ground
distance between them is within 5 % of the sector's length (so a shortcut or a detour does not match, nor a
ride the other way).  A new climb found on a ride is dropped if an older sector already covers it: less than
half of its length lies outside the older one's hull and the other way round (`DISTINCT_CLIMB = 0.5`).  When
a sector is added, the earlier rides near it are matched against it as well.

### Steps (each a commit; the pure parts first, with tests on made-up profiles and routes)

1. **A clean profile** (`climbs/profile.nim`, pure): for one timer segment, the cumulative distance along
   the coordinates (haversine; no per-point distance is stored), resampled to even steps of distance, the
   altitude despiked and smoothed (there is no scipy: a median, then a moving average or a small cubic
   smoothing spline), the gradient.  Tested with synthetic ramps and noise.
2. **The detector** (`climbs/detect.nim`, pure): the score `gain / distance^phi`, the greedy recursion with
   the coarse-then-fine search, reversals, the gradient limits, categories; the parameters as an object with
   choochoo's defaults.  Tested on made-up profiles (one hill, two hills with a dip, a big dip splits a climb,
   a plateau, a short steep ramp ignored) and against the Python output on the `../choochoo` test rides, to
   settle phi (0.6 or 0.7) and the smoothing.
3. **Geometry and matching** (`climbs/match.nim`, pure): a local flat projection in metres, the hull test, the
   gates, crossing a gate between two consecutive points, the shortest start/finish pair within 5 % of the
   length, the time interpolated; and the overlap rule for new climbs.  Tested with straight and looping
   routes, a ride the wrong way, GPS offsets inside 25 m, laps over the same climb (each is an effort).
4. **Tables** (`climbs/001-schema.sql`, `ddl.nim`, registered in `modules`): `sector` (id, kind, route as
   geometry with a spatial index, length, gain, gradient, category, the activity it was found on, an optional
   name), `effort` (sector, activity, segment, start and finish time, elapsed seconds, start and finish
   distance and elevation; primary key by sector, activity and start), and a record of which activities were
   worked out with which parameters.  The name `segment` is taken by the timer stretches, so the catalogue's
   word is **sector**, as in choochoo.
5. **Working them out** (`climbs/work.nim`): like the impulses, done when asked for (`calculateMissing`
   pattern: activities not yet worked out, in time order, each against the catalogue so far, so the result
   does not depend on the order of import or the number of threads); new sectors are matched against the
   earlier rides near them.  `nch climbs --rebuild` throws the catalogue away and starts again (needed when
   the parameters change).
6. **`nch climbs`**: the climbs of the selected activities with their efforts and ranking ("3rd of 12 on
   this climb, best 8:41"); `--sectors` for the catalogue; `--csv`, and `--web` like the other commands.
7. **Show them**: an elevation profile with the climbs marked, and the sectors on the heat map, as input for
   external viewers (no local plotting).
8. **Better elevation** (only if the barometer data prove poor): see the note on Copernicus GLO-30 above.

### Settled (author, 2026-11-04)

* The work is **lazy and kept**: a command that needs climbs first brings the tables up to date (activities not yet
  worked out, in time order, each against the catalogue so far; a new sector is matched against the earlier rides
  near it), then answers from the tables.  Nothing is worked out at import.  (`ff` does the same with impulses.)
* **The parameters are constants**, those of the Python code: phi 0.7, minimum gain 80 m, minimum gradient 3 %,
  maximum gradient 40 %, maximum reversal 10 % of the gain, categories by gain (80 m: 4, 160: 3, 320: 2, 640: 1,
  800: HC), hull and gates 25 m, a match within 5 % of the sector's length, a repeat if under half of each
  climb lies outside the other's hull.  No options.  An algorithm version is stored with the record of what was
  worked out, so a change of the algorithm shows up.
* **A sector** is a stretch of road or track that can be ridden again (a climb, for now; later a stretch the
  author picks).  It is a **copy**: its own polyline (lon, lat, elevation; a spatial geometry with an index) and
  summary numbers (length, gain, gradient, category), and a plain note of the ride it was first found on
  (not a link), so it survives deleting or re-importing that ride.  Hull and gates are worked out when matching.
* **Sectors are shared** by all users of the database (people may compare and compete); **efforts are personal**
  (they belong to a ride, and go with it).  The catalogue is built from every user's rides in one global order of
  start time, so it does not depend on whose rides were worked out first.
* `nch empty --user NAME` leaves the sectors alone.  **`nch empty --sectors -f`** clears the catalogue, with
  every user's efforts and the record of what was worked out (so the next `nch climbs` starts again: this is the
  rebuild); it says how many sectors and efforts of how many users it deletes, and has the countdown.

### Still to settle

* The names (`sector`, `effort`) and whether `climbs` is the module (the rest is general).

### Steps 1 to 3 are built (2026-11-04): `climbs/{geo,profile,detect,match}.nim`, pure, 32 tests

* `geo.nim`: the flat projection (metres round a reference point), haversine, point-to-line distances, segment
  crossings, points along a line.
* `profile.nim`: distance from the positions (haversine), samples every **10 m** (fixed), altitude only where
  recorded (NaN otherwise; a gap between two altitudes is bridged, as pandas did), then a median of 5 and a
  mean of 5 (instead of the spline; a climb is 80 m or more so this is plenty).  A climb never crosses a stretch
  with no altitude (`findClimbs(profile)` works on each stretch).
* `detect.nim`: choochoo's detector as it is: score `gain / distance^0.7`, greedy recursion, coarse search every
  10th sample above 1000 samples then fine, reversals (10 %), gradient limits, categories.  Ends are brought in by
  a sample, as there.  3 ms for a 143 km ride.
* `match.nim`: gates 25 m, the shortest crossing pair within 5 % of the length, times interpolated; **laps are
  separate efforts** (choochoo kept one per ride); a hull with flat ends for the repeat rule (more than half of
  each inside the other's hull).
* Not compared with the Python output: numpy, pandas and scipy are not installed here (ask before installing);
  checked on made-up profiles with known answers and on real rides instead (a 4.8 % climb of 1.9 km, +93 m, and
  a 3.9 % one of 3.2 km, +124 m, in two of the author's rides).

### Settled: timer segments (author, 2026-11-04)

The 167 activities of the sample have **50 timer segments on average** (up to 327; a typical ride has a dozen or
more, the longest 20 to 60 minutes), because the device pauses the timer whenever the rider stops.  So climbs are
**detected on the whole route** (the profile is by distance and ignores pauses), and an effort is **ranked by its
total time**, gate to gate, stops included.  (Moving time and the seconds paused are not stored; they could be
added to `effort` later from the activity's segments.)  The earlier "a climb lies inside a timer segment" rule is
dropped.

### Step 4 is built (2026-11-04): `climbs/001-schema.sql`, `climbs/ddl.nim`, registered after `importer`

`sector` (id, kind, length_m, gain_m, gradient, category, found_at, route: XYZ linestring with a spatial index),
`effort` (sector_id, activity_id, start_t, finish_t, elapsed_s, start_m; primary key sector, activity, start_t),
`climbs_done` (activity_id, version).  Distances are metres in the database and kilometres on the screen.  No
altitude at the gates and no finish distance (dropped by the author).  Efforts go with their activity or their
sector; sectors refer to no ride.  Tested: the route and its index, the cascades, laps, the duplicate pass.

### Step 5 is built (2026-11-04): `climbs/work.nim`, `nch empty --sectors`

`ensureClimbs(store)` brings the tables up to date as planned (activities not in `climbs_done`, in start order, all
users; efforts on the sectors near the ride; new sectors from its climbs unless they repeat one; a new sector
matched against its own ride and the earlier rides near it; one transaction per activity; a method version).
`clearClimbs` and `nch empty --sectors -f` start again.  Real data: the 300-file sample (167 activities) takes
2.4 s (43 sectors, 220 efforts); the whole library (1,986 activities) takes 56 s once (161 sectors, 3,635 efforts:
117 of category 4, 30 of 3, 12 of 2, 1 HC), and a second pass 0 ms.  Reading coordinates was half the time, so the
rides read recently are kept (up to 3 million points); the profile shows `climbs: ...` phases.  Not yet:
`nch climbs` (step 6).

### Naming climbs (asked 2026-11-04): GeoNames, measured on Chile

What we carry: `cities5000`, about 70,000 populated places of 5,000 people or more (247 in Chile).  The full
GeoNames dump (`allCountries.zip`, 422 MB to download) has a feature class and code for each entry; one
country's file is small (Chile: `CL.zip` 1.4 MB, 46,467 features: 15,955 terrain, 12,426 water, 8,483 spots, 6,967
populated, only 34 roads).  Terrain in Chile: 5,354 mountains, 1,763 hills, 800 ranges, 569 passes, 229 peaks.
Against the 43 climbs of the sample (all in Chile): only 309 features (0.7 %) lie within 2 km of them, so filtering
by place helps a great deal; every climb has a terrain feature within 3 km, but only 8 within 1 km; the nearest
is mostly a "Cerro ..." hill or mountain (Cerro San Cristobal, Cerro Calan), not the name of the climb, and
GeoNames has almost no roads, so road names ("Camino a Farellones") would need OpenStreetMap.  The nearest
populated place (what we have now) is 3 to 15 km from a climb's start: it says where, not what.
Idea: fetch the country files on demand into the cache (like the terrain tiles), keep the best name on
`sector.name` (a pass or saddle near the top, else a peak or mountain within ~1.5 km, else "near <town>").

### Where we are (saved 2026-11-04) and what comes next

Built and committed: steps 1 to 5 of task 12 (profile, detector, matching, tables, the lazy work pass, `nch empty
--sectors`).  Not yet: `nch climbs` (step 6), the elevation profile chart (7), the terrain model (8), names.

Next, in this order:

1. **`nch climbs`** (to design with the author; proposed): `nch climbs` lists the climbs of the selected activities (or
   all of the user's: to settle), a block for each activity: sector id, start km, length, gain, gradient,
   category, the time, the rank of this effort among the efforts on that sector ("3rd of 12") and the best time;
   `nch climbs --sectors` lists the catalogue: id, length, gain, gradient, category, number of efforts, best time and
   whose.  Both call `ensureClimbs` first.  Distances are metres in the database and kilometres on the screen.
2. **Names for sectors** from GeoNames country files, fetched when wanted into `<cache>/data/` (left alone by
   `empty --cache`) with Nim's own HTTPS client (`-d:ssl`; OpenSSL 3.5 is installed here, and a test fetched
   `CL.zip` from geonames.org).  The countries are those of the few nearest places in the embedded list (a border
   can be near).  A nullable `sector.name`: a pass or saddle near the top, else a peak or mountain within about
   1.5 km of the route, else "near <town>".  Without a network the names fall back to "near <town>", once told.
   `-d:ssl` has to be added to the builds.  Later: the same files could name the starts of activities (6,967
   populated places in Chile against the 247 we carry), which needs per-country sources in the `place` table and a
   refresh of the stored place ids.
3. **Terrain model** (Copernicus GLO-30 from the AWS bucket) to correct a barometer's drift; only if the
   device altitude proves poor.
4. **Elevation profile chart** and the sectors on the heat map.

Also to remember: the full library's first pass takes 56 s (reading coordinates is the largest part, then
detection); a second pass is instant.

### Step 6 is built (2026-11-04): `nch climbs`

`nch climbs` shows, for each selected activity (see `nch list --save`; an empty selection is an error that says
so), the climbs it went up: sector id, where (km along the ride), length, gain, gradient, category, the time
(gate to gate, stops included), the rank among everyone's efforts on that sector ("3 of 12") and the best time.
`nch climbs --sectors` lists the catalogue, the biggest first: length, gain, gradient, category, efforts, the best
time and whose it is, and the user's own best.  Both first call `ensureClimbs` (a progress line on a terminal;
the work is logged as `done`).  `climbs/report.nim` has the queries and the (pure) formatting; the output is
plain text, to be tweaked once it has been used (the author's words).  Shown on the 4 newest rides of the sample:
`#42  at 30.5 km  7.6 km  +505 m  6.7 %  cat 2  56:46  5 of 6  best 48:41`.

## Task 13: names for places and climbs (plan, 2026-11-04; nothing built yet)

Aim: `lon, lat -> a name`, for climbs first ("Cerro San Cristobal", "Paso Los Libertadores", else "near Lo Barnechea") and
later for the starts of activities.  From outside it is one call; underneath it uses tables, a file cache and the
network.

### Country: outlines, not cities

GeoNames publishes simplified country outlines (`shapes_simplified_low.json.zip`, 1.3 MB zipped, 4.6 MB of GeoJSON,
247 countries as 28,198 polygons with 270,203 vertices; each keyed by `geoNameId`, which `countryInfo.txt` (32 KB, 252
countries) maps to the ISO code and name).  Tried on real points: Santiago CL, Mendoza AR, Lisbon PT, Bristol GB,
the pass on the Chile/Argentina border CL, and all 608 sampled points of the author's 43 climbs CL.  It lacks tiny
territories (Curacao gave nothing) and the sea, so a point with no polygon takes the country of the nearest place in
the embedded list.  Licence CC BY 4.0, as the places (NOTICE).  This replaces the earlier idea of finding the
country from the nearest town (wrong across a border) and makes a smaller embedded city list pointless.
**Fetched, not embedded** (the author's suggestion, adopted): the outlines are downloaded on first use and cached, like
the country files; naming needs the network anyway, and afterwards works offline from the cache.

### Shape (a functional shell over a mutable core)

* **Pure**: `pickName(candidates, route)`: the rules, tested on made-up features; the SQL queries are reads.
* **The handle** `Names` holds the store, the data directory and a `Fetcher` (a closure: url -> bytes or an error), so
  a test serves a made-up zip and no test touches the network.
* **One call**: `nameOfClimb(names, route)` -> `Option[string]` (and later `placeNear(names, lon, lat)`): find the
  country (polygon), make sure its names are loaded (download, import: the side effect), query the nearest
  features, pick.  The library never prints: it returns notes ("cannot reach geonames.org: ...") for the
  command to say once.
* **Offline**: nothing is marked as looked at, the name stays unset and is tried again next time; no crash.

### Tables (module `names/`, after `places`, before `climbs`)

* `country(iso primary key, name, geoname_id)` + `geom MULTIPOLYGON` with a spatial index; seeded from the embedded
  outlines (a small set for the tests, as `nchSmallPlaces` does).
* `name_source(country references country, loaded_at, features)`: which country files are in.
* `feature(id = geonameid, country references country, name, class, code, population, lon/lat as a POINT with a
  spatial index)`: the terrain features (class T: mountains, hills, peaks, passes, saddles, ridges, spurs, valleys,
  canyons) and the populated places (P) of the countries loaded: about 20,000 rows for Chile; the other classes
  (water, spots, roads: only 34 in Chile) are left out.
* `climbs/002-name.sql`: `sector.name` and `sector.name_checked` (unset and 0: not looked at; set: the name; 0 name and 1:
  looked and nothing near).  A sector is still a copy: the name is text, not a link.

### Data files

`<cache>/data/geonames/CL.zip` etc., fetched when a name is wanted (`std/httpclient` with `-d:ssl`: OpenSSL 3.5 is
installed and a test fetched `CL.zip`); `empty --cache` leaves them (they are downloads, not generated), a new
`empty --names` clears the `feature` and `name_source` tables.  Sizes: Chile 1.4 MB, Spain 3.3, Italy 4.4, Brazil 7.2,
France 7.3, Russia 15, China 32, the United States 71 (the largest, one-off).  The zip is checked (a zip, holding
`XX.txt`) before it is used.

### The rules for a climb's name (to tune on the 43 sectors of the sample)

1. a pass or saddle (PASS, SDL) within 400 m of the top of the climb;
2. else a peak or mountain (PK, PKS, MT, MTS) within 1 km of the top, else a hill or ridge (HLL, HLLS, RDGE, SPUR)
   within 1.5 km of the route; the nearest of the best kind;
3. else "near <the nearest populated place within 5 km>"; else none.
On the sample every climb has a terrain feature within 3 km but only 8 of 43 within 1 km: expect "near ..." and
loose names; they are labels, not facts.

### A download module first (the author's suggestion, adopted)

Bundle only what must travel with the program or be pinned: `Profile.xlsx` (restricted), `NOTICE` (the licences),
the page templates and `libraries.txt` (whose integrity hashes mean nothing if fetched).  Everything else that is
data is downloaded and cached: the country outlines, the country files, later more.  The embedded city list stays
as the offline fallback (and keeps `nch import` self-contained) until the names module has replaced it.
`download/` (a library, no command) is the one place that:

* fetches a URL (`std/httpclient`, `-d:ssl`, a timeout, a polite user-agent) through an injectable `Fetcher`, so
  tests serve made-up bytes and never touch the network;
* checks what came back (a zip with the entry that was expected, a size that is not zero) before it is used;
* writes it atomically into `<cache>/data/<source>/`;
* knows every source in one list (name, URL pattern, expected content, attribution), so there is no URL
  scattered through the code;
* **reports what happened as events to a sink** (as the import does), never prints: `downloaded` (url, file, bytes),
  `failed` (url, why: cannot reach, status, not a zip), `note`.  A command passes a sink that writes the events to
  the log (a new event word `downloaded`, green; failures are the existing `failed`, red) and says them once on the
  screen, so every download, from any command, is logged and reported in the same way.

### Steps (each a commit)

1. `download/`: the sources list, the `Fetcher`, the checks, the atomic cache files, the events and sinks (to the log and
   the screen), `-d:ssl` in the nimble tasks; tests with a made-up fetcher and a made-up zip; a manual check
   with the real `CL.zip`.
2. `names/` countries: fetch the outlines on first use (a small made-up set in the tests), fill the `country` table,
   `countryAt` (polygon, then the nearest embedded place), tests on known points.  The binary stays as it is.
3. Loading a country: the zip (through `download/`), the parser (tab-separated GeoNames lines), the import of T and P
   features, `name_source`; tests with a made-up zip; a manual check with the real Chile file.
4. Candidates near a route and `pickName` (pure), tests; run on the 43 sectors and look at the names with the author.
5. `climbs/002-name.sql`, `ensureNames` after `ensureClimbs`, the name shown in `nch climbs` and `--sectors`,
   `empty --names` and `empty --data` (the downloaded files), the NOTICE.
6. Later: the starts of activities named from the same features (6,967 populated places in Chile against the 247
   in the embedded list), which needs the `place` table and the stored place ids reworked; then the embedded city
   list can go or shrink to a fallback.

### To settle with the author

* Import every populated place and terrain feature of a country (about 20,000 rows for Chile, perhaps 600,000 for the
  United States), or only those near a climb?  Recommended: whole country, once.
* The rules above, and what to show when there is only "near <town>".

## Task 14: a calendar of fitness (idea, 2026-11-04; not planned in detail)

`nch list --calendar` (the day grid, a row per month) with the **background colour** showing fitness (or fatigue, or
form = fitness - fatigue) and the day numbers kept as they are (white listed, yellow selected, grey none).  The
author's detail: a day is three characters wide, and the background **varies across the three**, so each character
shows an 8-hour third of the day (the value at the end of 00:00-08:00, 08:00-16:00, 16:00-24:00 local; the hourly
curves of `nch ff` already have them).  Parts:
1. colour support in `ui/palette` + `ui/style`: background colours and RGB (truecolor where `COLORTERM` says
   `truecolor`/`24bit`, else the 256-colour cube, else 16 colours), `NO_COLOR` and pipes as now.  Common
   terminals: truecolor on GNOME (VTE), KDE (Konsole), kitty, Alacritty, WezTerm, iTerm2, Windows Terminal and the
   Windows 10+ console; Terminal.app only from macOS Tahoe (26); tmux needs a setting; the Linux text console
   is 16 colours.  Brightness is not a separate setting: 8 bits per channel (a grey is R = G = B, 256 levels), 24
   greys in the 256-colour mode, one bright bit in the 16-colour mode.
2. a pure scale value -> colour (one hue, light to dark, for fitness and fatigue; diverging for form), with a text
   colour that stays readable (light or dark by the brightness of the background); relative to the user's own
   maximum, or absolute (to settle).
3. the series per day-third from `ff` (needs the threshold heart rate, as `nch ff` does; days before the first
   heart-rate activity have no background; every day after it has one, since the curves decay), a one-line legend
   (a colour bar and the range), options `--fitness`, `--fatigue`, `--form`; the calendar shows every month in the
   range (as `-v` does) when a background is asked for.
Roughly a third of the size of the names work.

### Task 13, step 1 is built (2026-11-04): `download/`, and `zipbytes.nim`

* `zipbytes.nim`: reading a zip from bytes (the central directory, stored or deflated entries), moved out of
  `xlsx.nim` (which uses it and turns `ZipError` into `XlsxError`); `ZipError` in `errors.nim`.
* `download/sources.nim`: the list of what is downloaded (the GeoNames country files, the simplified outlines, countryInfo),
  with the address, the file, the zip entry expected, the largest size allowed and the credit.
* `download/fetch.nim`: `fetchSource(env, sink, dataDir, source, arg)` -> the path in `<cache>/data/<source>/`.  It returns
  a file already there without a word; otherwise it asks the server how big (HEAD), refuses what is over the source's
  limit, **checks the room on the disk** (the file three times over, for what is made from it, plus **500 MB kept
  free**; if the server does not say how big, the source's largest size is assumed; if the disk cannot be asked, it goes
  on), fetches, checks the content (a zip must be one and hold the entry expected; nothing empty), and writes
  atomically (`.part`, then rename).  `Env` holds the network and the disk, so tests serve made-up bytes and room.
  `dataUsage` and `clearData` say what the downloads take and delete them.
* `download/sinks.nim`: events (`downloaded`, `failed`) go to a `Sink`; `logSink` writes them to the log (`downloaded`, a new
  green log word, at info; `failed` at error) as the command that asked; `screenSink` says a line each; `fanOut`.
* `-d:ssl` is in the nimble tasks.  Checked against geonames.org: CL.zip (1.4 MB), the outlines (1.3 MB), countryInfo
  (32 kB), the cache hit, a 404 for a country that does not exist, 7.8 GB free reported.
* Not yet: `empty --data` (to clear the downloads), the names module (step 2 onwards).

### Task 13, step 2 is built (2026-11-04): `names/` countries

* `names/001-schema.sql` (`country`, `name_source`, `feature`; the last two for step 3), `names/ddl.nim`, registered after `places`.
* `names/outlines.nim` (pure): reads `countryInfo.txt` and the outlines GeoJSON into well-known text; reads that text back into
  polygons and answers "is this point inside" by **counting crossings (even-odd)**.
* `names/countries.nim`: the `Names` handle (store, data directory, network and disk, sink) and `countryAt(names, lon, lat)`:
  fetches the outlines and the list of countries the first time (1.6 s for the real ones), fills `country` (252 countries, 247
  with an outline), picks the candidates by the spatial index (bounding boxes), then decides with the crossing count; a point in
  no outline takes the country of the nearest place carried in the program if that is within 300 km, else none.  Without the
  network it still answers from the places and tries again next time; a file that cannot be read is said, deleted and fetched again.
* **Why not SpatiaLite's `Contains`**: GEOS calls **137 of the 247** GeoNames outlines invalid (they are coarse, about 100 m, with tiny
  rings and touching parts); `Contains` then threw topology errors and gave wrong answers (Santiago in Argentina, Lisbon in
  Spain), and `MakeValid` failed too.  A source of valid outlines (Natural Earth) would let SQL do it all.
* Checked on the real outlines: Santiago CL, Mendoza AR, Lisbon PT, Bristol GB, the Los Libertadores pass CL, Tokyo JP, Willemstad CW.

### Task 13, step 3 is built (2026-11-04): `names/features.nim`

`ensureNames(names, iso)`: makes sure the country's names are in `feature` (fetching `<ISO>.zip` through `download/` and the
outlines first if need be), once: it reads the GeoNames file, keeps class T of the codes MT MTS PK PKS PASS SDL HLL HLLS RDGE SPUR VAL
CNYN and all class P (villages and neighbourhoods too), inserts them in one transaction with a point geometry and its index, and
records the country in `name_source`.  A cached file that cannot be read is said, deleted and fetched again next time.  `parseFeature`
reads a line without making a string for each of the 19 columns.  The zip reader takes a size limit (the United States file unzips
to about 300 MB; the limit here is 1 GB; the whole text is held in memory, so very big countries are heavy: streaming is a later job).
Real Chile file: 16,223 features in about 1 s after the outlines (MT 5,354; PPLX 4,018; PPL 2,786; HLL 1,763; MTS 800; PASS 569; SPUR 291; PK 229);
a box round the Los Libertadores pass finds Portezuelo Navarro, Paso de la Iglesia and others.  Next: step 4, the candidates near a
route and the pure `pickName`.

### Task 13, step 4 is built (2026-11-04): `names/pick.nim`, `names/naming.nim`; `geo.nim` moved up from `climbs/`

* `pickName` (pure): a pass or saddle within 400 m of the top; else a peak or mountain within 1 km of the top; else a hill, ridge or spur
  within 1.5 km of the route; else the nearest populated place within 5 km as "near <place>".  **A feature more than 1 km away is shown as
  "near <name>"** (the author's suggestion).  The nearest wins within a kind.
* `nameRoute(names, lons, lats)` -> named / nothing / later: the country of the top (outlines), its names loaded (fetched the first time),
  the features near the route (spatial index, distances in a flat projection), `pickName`.  "Later" means the network stopped it: nothing is
  decided, ask again.  The library never prints.
* On the 43 climbs of the author's sample (Chile): 20 named for a hill, 20 "near <place>", 3 nothing, none for a pass or peak (they are
  city-edge climbs).  Good where the distance is small (Cerro San Cristobal at 155 m, Cerro Calan 242 m; the HC climb is "near Farellones",
  240 m); weak at 1 to 1.5 km, now shown as "near".
* **Settled (author)**: terrain (pass, peak, hill) is measured from the **top** only ("the climb ends at the mountain, it does not start
  there"); a place for "near <town>" is measured from the **middle** of the climb (half way along it), since it says where the climb is
  as a whole.  On the 43 climbs: 16 hills, 23 "near <place>", 4 nothing (the HC climb is "near Farellones").
  Not yet done: step 5, `sector.name`,
  the name in `nch climbs`, `empty --names` and `--data`.

### Task 13, step 5 is built (2026-11-04): names on sectors, in `nch climbs`, `empty --names`/`--data`, `--offline`

* `climbs/002-name.sql`: `sector.name` and `sector.name_checked` (0 until looked at, 1 after, with or without a name).
* `climbs/naming.nim`: `ensureSectorNames(store, names)` names the sectors not yet looked at; if the names cannot be had (no network)
  nothing is marked and the rest wait ("pending").  `nch climbs` calls it after `ensureClimbs`: downloads are logged (`downloaded`, `failed`)
  and said once on stderr; the name is shown last on each line of `nch climbs` and in `--sectors`.
* `nch --offline` (a global option, `Globals.offline`): nothing is downloaded; climbs are named another time.  Every test uses it.
* `cache.dataDir` (`<cache>/data`, downloads); `empty --names` empties `feature`, `name_source` and `country` (the files stay; names already given
  to climbs stay); `empty --data -f` deletes the downloaded files.  Both need `-f`.
* Real run (scratch cache): the 43 climbs of the sample named in about 15 s including three downloads (outlines 1.3 MB, countries 32 kB,
  Chile 1.4 MB): 39 named, 4 with nothing near; the second run takes 30 ms.  E.g. the HC climb is "near Farellones", #29 "Morro La Cabra",
  #3 "Cerro San Cristobal".
* Not done: a way to name again (`name_checked = 0`), the starts of activities named from the same features (task 13, step 6), streaming for
  the very big country files, the licence and README work.

### The display of `nch climbs` and the explanation of downloads (2026-11-04)

* While the climbs are worked out, two lines follow the work, in green (the word "climbing" in bold): `climbing 120 / 1,986 activities` and
  `climbs 12 · efforts 40`; the last frame is left on the screen, in white.  Only on a terminal; nothing if there is no work to do.
* Every download is preceded by a line that says why it is wanted (`Source.why`, a `starting` event): "need country shapes, to infer country from
  position", "need the list of countries, for their names and codes", "need names of places and mountains in CL, to name climbs"; then the
  `downloaded` line.  In the log the "need" line is a `note`.

### The cache directory (what is where)

* `user/`: made by commands (maps, CSV, pages); disposable; the web server serves only this; `empty --cache` clears it.
* `system/`: unpacked from the program (the profile, the cities list, the page templates, `libraries.txt`, `NOTICE`); the author may edit them
  (an edited file is never overwritten); unpacked again if deleted; no `empty` target touches it.
* `data/`: downloaded from the network (GeoNames); neither made by a command nor carried by the program; losing it costs a download;
  `empty --data` clears it.  `empty --cache` leaves it on purpose.
* Top level: `server-token` and `manifest`.
* To go back to before the climbs: `empty --sectors -f` (the climbs, their efforts and names, and the record of what was looked at);
  as well, `empty --names -f` (the tables of countries and place names, read again from the files in 2 s) and `empty --data -f` (the downloaded
  files) for a start with nothing fetched.  (A single `empty --climbs` that does all three is possible: to ask the author.)

### Resetting (2026-11-05): `empty --names` takes the files too; no `--data`, no `--climbs`

* `nch empty --names -f` deletes the place names and countries: the three tables **and** the GeoNames files downloaded for them
  (`<cache>/data/geonames/`: each source has a directory of its own, so a later source gets its own target, not a catch-all).  The names
  already given to climbs stay (copies).  `empty --data` is gone (it sounded like deleting the database).
* To go back to before the climbs: `empty --sectors -f` (the climbs, efforts, names, record) and `empty --names -f` (the tables and files);
  the next `nch climbs` works everything out and downloads again.  No `empty --climbs` (the author: sectors will become more general).
* `nch climbs` with an empty selection says so (what to do: `nch list ... --save`, or `nch climbs --sectors`) and exits normally.
* To compare with the import's display (the author felt they differ): import's first line is white (`importing` bold, the counts plain,
  the current file grey), the second line has coloured parts (imported green, the others grey/red/yellow) joined by grey dots, and a plain
  `done: ...` summary line follows the left-on-screen frame; climbs' first line is green throughout, its second line is green, and there
  is no `done:` line.  To be settled after the author has looked at both.

### `empty` with several targets, and the climbs display like the import's (2026-11-05)

* `nch empty --user NAME --sectors --names -f` (any of `--user`, `--sectors`, `--names`, `--cache`) is one run: **one** "would delete A; B; C; use
  -f to do it" message (the parts apart by semicolons), **one** countdown, one `done:` line and one log line; an unknown user fails before
  anything is done.  `--all` includes the user data and the climbs, so it stands alone, or with `--names` and `--cache` (the downloaded and the
  generated files, which are outside the database).  `--cache` alone still needs no `-f`.  With no database the files can still be emptied.
* `nch climbs` shows what the import shows: a plain first line (`climbing` in bold), a second line of counts in green joined by grey dots
  (`climbs 12 · efforts 40`), the same frame left on the screen, and a `done: 1,650 activities: 138 new climbs, 2,661 efforts` line
  after it (on stderr, so that `nch climbs --sectors | ...` stays clean).

## Task 15: climbs are known by name (DONE 2026-11-05; the first plan below was replaced by "REVISED PLAN" further down)

**In short, as built**: a climb's name comes from GeoNames by tiers (within 1 km of the end; within 1.5 km of the middle, "near ..." from 1 km; a populated place
within 5 km of the middle) with the kinds in strict order (pass, peak, hill, town, neighbourhood); climbs sharing a name are shown "name (n/m)" by gain, worked
out when shown; names may be given by hand (`nch sector --edit NAME --rename NEW`, `--auto` to hand back) and are then never changed; `empty --sectors` says how
many hand-given names it would lose; `--offline` names from what is already loaded.  Steps 1 to 6 are described below; no further work is planned.  Everything
under "Agreed" and the other sections of the first plan that mentions difficulty, phi, stored numbers or unique names is history.

### Agreed

* `nch climbs` shows **names, not `#n`**; the ids stay inside the database.
* Names are **unique** (compared without regard to case).  Climbs with the same base name are ordered by **difficulty**, the hardest
  first (ties by id): the hardest has the plain name, the next gets " (2)", then " (3)" and so on ("near La Florida (2)").
* **Difficulty = `gain_m × length_m ^ (1 - phi)`**, that is `gain × length^0.3` (phi 0.7), which is `length × the detection score`
  (`gain / length^phi`; the exponent applies to the length only).  It is stored on the sector.  The detection score stays what it is: it
  favours short steep climbs and is only used to choose where a climb starts and ends; difficulty is only for ranking finished climbs
  (HC near Farellones 19,800; the 400 m ramp 808; Cerro Calan 700).  It needs phi to stay as it is; a change of phi is a change of method
  version, which means `empty --sectors` and a rebuild.
* **Hand renames** are allowed.  A name set by hand is never overwritten.

### How (the proposal; the single-name version, the author's choice 2026-11-05)

Store the facts and **work the names out whenever they are shown**, instead of rewriting stored names when a harder sibling arrives:
* on each sector: `name` (the automatic base name, or the name the author set), `renamed` (0 or 1: set by hand) and `difficulty`; no second
  column for the old automatic name;
* a pure function from (name, renamed, difficulty, id) of all sectors to unique names: the names set by hand are reserved first and shown as
  they are; the others are grouped by base name, ordered by difficulty, and take the plain name and then " (2)", " (3)"..., **skipping any
  name already taken**.  A climb that is renamed leaves its group, so the rest close up: if "Foo" is renamed "Bar", "Foo (2)" becomes "Foo"
  (and the base name is free for the others); gaps filled by themselves; numbers shift when a harder climb is found;
* a name given as an argument (a rename) is looked up among the names as they are now; a name that is shown already is refused;
* undoing a rename sets `renamed` to 0 and `name_checked` to 0, so the next `nch climbs` works the automatic name out again from the places
  tables (offline if they are loaded; it waits otherwise).

### Steps (each a commit)

1. `climbs/003-difficulty.sql`: `difficulty real` and `renamed integer not null default 0`; difficulty filled in when a sector is made and,
   once, for the sectors already there (in code: SQLite may not have `pow`).  Sectors with nothing near them get the base name **"unnamed"**
   (stored in `name`: "unnamed", "unnamed (2)"...).
2. The pure function (`climbs/naming.nim` or a new file) with tests: groups, ties, case, a name set by hand that clashes with an automatic
   one, the group closing up after a rename, gaps.
3. `nch climbs` and `nch climbs --sectors` show the names (an aligned left column; a very long name is cut); `--sectors` sorted by
   difficulty.
4. **A `sector` command** (a new module `sector/` whose `command.nim` uses the climbs library files; the table stays with climbs), in the style
   of `user`: the target is named after the command, never `--user` before it (shared by all users).
   * `nch sector`: lists the catalogue (as `climbs --sectors` does);
   * `nch sector --edit NAME --rename NEW`: sets the name (`renamed` = 1); NAME is looked up among the names as they are now (without regard
     to case); NEW is trimmed, may not be empty or already shown by another climb;
   * `nch sector --edit NAME --auto`: the way back to the automatic name (`renamed` = 0, `name_checked` = 0);
   * logged (`saved`); room for `--remove` and `--add` (sectors the author defines) later.
5. `empty --sectors` says how many hand-renamed climbs it would lose.
6. Tests and docs.

### Settled by the author (2026-11-05)

* **A.** Nothing near a climb: the base name is "unnamed".  **B.** A `sector` command (`--edit NAME --rename NEW`).
* Small defaults (unless the author says otherwise): numbers freed by renames may be reused; `--sectors` is sorted by difficulty; the names
  of the 138 existing sectors stay as they are (they are the base names).

### Latest comments (2026-11-05, end of day) and what to settle tomorrow

* **Difficulty is written in terms of phi**: one function `difficulty(gain, length) = gain × length^(1 - phi)` using the same `phi` as the detector
  (one definition, in `detect.nim`; never a literal 0.3), so editing the parameter changes it.
* The flag is called **`immutable`** (not `renamed`): a name the system never changes.  A rename sets it; locking a name without changing it
  (`nch sector --edit NAME --lock`, `--unlock`) is possible and cheap.  The names of climbs that are not immutable may change when new sectors
  are found (the numbers shift).
* **Stored or computed numbers: to discuss.**  The author prefers the number **stored** (perhaps as a separate integer column, with `name` the
  base name), suspecting there is an advantage the assistant's preference for computing misses.  For: the database can enforce uniqueness
  (`unique (name collate nocase, number)`), the full name is visible to SQL, exports and other tools, and a name stays what it was between runs
  until something changes it on purpose.  Against: the numbers must be rewritten when a sibling is found, renamed, locked or removed (a rewrite
  pass in the same transaction as the change), and values can only go stale if that pass is skipped.  Either way the visible behaviour is the same.
  The same question for **difficulty**: stored (sortable in SQL; recomputed when the method version changes) or computed from gain and length
  (cannot go stale).  The author prefers stored.
* Everything else in the plan above stands (names not ids, the `sector` command, "unnamed", the steps).  Nothing is built yet.

### Resumed 2026-11-05: the naming reconsidered (the author), with numbers from the 138 real climbs

The author's new rules (to confirm, see the questions below; nothing is built):
* a name comes first from a feature **within 1 km of the end** (the top), **the closer the better**; else from one **within 1.5 km of the middle**,
  shown as "near <name>" when 1 km or more away;
* climbs that end up with the same name are shown with **"(n/m)"**, n from ranking by **length**, **worked out when shown, never stored**;
* **manual naming** is allowed.  (This drops the stored difficulty and phi coupling, the stored numbers and the unique-name constraint.)

Simulated on a copy of the real database (138 climbs, Chile names loaded): end within 1 km 52 (38 %); middle within 1 km 19; middle "near"
(1 to 1.5 km) 23; **unnamed 44 (32 %)**.  Terrain features only (no places): 26 / 6 / 12 and **94 unnamed (68 %)**.  The rule now in the code (up to 5 km
from the middle as "near <town>", kinds in a fixed order) leaves 12 of 138 unnamed.  "The closest of anything" often picks a neighbourhood
(Lo Contador, Monserrat) where a hill is also within 1 km (Cerro San Cristobal).

Questions: (1) kind priority inside the 1 km of the end (terrain, then places) or purely the closest?  (2) keep the 5 km "near <town>" fallback after
the 1.5 km tier?  (3) (n/m): the longest is 1?  shown only when m > 1?  ties by id?  (4) manual names: duplicates allowed (the suffix tells
them apart) and `nch sector --edit NAME --rename NEW` with NAME as shown, "(n/m)" included?  (5) drop the difficulty column and phi coupling?

### The kind of feature in the naming (recommendation, 2026-11-05; the author asked; not built)

Keep the author's tiers (tier 1: within 1 km of the end; tier 2: within 1.5 km of the middle, "near ..." from 1 km; tier 3: a populated place within
5 km of the middle as "near <place>"), but inside each tier take the **kinds in order**: pass or saddle, peak or mountain, hill / ridge / spur,
village or town, neighbourhood (GeoNames `PPLX`), the closest within a kind.  Tried on the 138 real climbs: chosen kind 4 / 9 / 30 / 42 / 45, **8 unnamed**
(against 44 for "the closest of anything" without tier 3); 42 names differ (Cerro San Cristobal instead of Lo Contador or Monserrat; Las Perdices
instead of Lo Canas).  Softer alternative if strict order proves too strong (a far hill beating a near village such as Farellones): scale the distances
by kind (pass x0.5, peak x0.75, hill x1, village x1.5, neighbourhood x2.5) and take the smallest.  Start strict, look at the names, change if needed.

### Task 15, REVISED PLAN (2026-11-05, after the author's answers; it replaces the difficulty, phi, stored number and unique-name parts above)

**Settled**
* Names, not ids, in `nch climbs` and `--sectors`.  Names need not be unique: climbs that share a name are shown **"name (n/m)"**, n the rank by
  **gain** (the biggest is 1; ties by id), only when m > 1, worked out when shown and never stored; the group is the name without regard to case.
* No difficulty, no phi coupling, no stored numbers (the ranking is by length).
* **Manual naming**: `nch sector --edit NAME --rename NEW`, NAME as shown ("(n/m)" included); duplicates allowed; `nch sector --edit NAME --auto`
  goes back to the automatic name; `nch sector` lists the catalogue; sectors are shared, so `--user` before the command is refused with a hint.
  A manual name is `manual = 1` and is never changed by the system.
* Climbs with nothing near them are called "unnamed" ("unnamed (n/m)" by length).

**The rules for the automatic name** (the author's tiers, with the kind of feature taken into account; strict order first, to be looked at on the real names):
* tier 1: within 1 km of the end (the top); tier 2: within 1.5 km of the middle ("near ..." from 1 km); tier 3: a populated place within 5 km of the
  middle, "near <place>";
* inside a tier the kinds in order: pass or saddle, peak or mountain, hill / ridge / spur, village or town, neighbourhood; the closest within a kind.

**Stored on a sector**: `name` (automatic or manual) and `manual`.  Nothing else new.

**Steps (each a commit)**
1. `climbs/003-names.sql`: `manual integer not null default 0`; every existing sector is marked not yet named (`name_checked = 0`, `name = null`), so the next
   `nch climbs` names the 138 again with the new rules (offline, from the loaded tables).
2. The rules in `names/pick.nim` (pure; the neighbourhood kind needs the GeoNames code), tests, and `nameRoute` passing both distances.
3. The pure display-name function (id, name, length -> "name (n/m)"), tests: groups, case, ties, m = 1, the group closing up after a rename.
4. `nch climbs` and `--sectors` show the names (an aligned left column; a very long name is cut).
5. The `sector` command (new module `sector/`): list, `--edit NAME --rename NEW`, `--edit NAME --auto`; looks the name up as shown; refuses an empty name and
   one that looks like a suffix ("... (2/3)").
6. `empty --sectors` says how many manually named climbs it would lose.
7. Tests and docs.

**Settled later the same day (the author)**: (a) **strict kind order, the first kind that matches wins** (no scaling of distances by kind); (b) tier 3 (the 5 km
"near <place>" fallback) stays; (c) **"(n/m)" is ranked by GAIN, not length** (the biggest gain is 1; ties by id), and `--sectors` stays sorted by gain, biggest
first; (d) the **categories stay by gain** (80, 160, 320, 640, 800 m).  Where this file says "length" above for the ranking, read gain.  Nothing is open;
nothing is built.

**Step 1 is built (2026-11-05)**: `climbs/003-names.sql` adds `sector.manual` (0 or 1) and, once, forgets the automatic names (`name = null`,
`name_checked = 0`) so that the next `nch climbs` makes them again.  It runs when a database is next opened, so on the author's 138 sectors it will:
until step 2 is built they are named again by the rules of that day, so nothing visible changes.  Tests: the column, the one-time reset, and that
names given afterwards survive the next opening.

**Step 2 is built (2026-11-05)**: `names/pick.nim` has the rules (tiers 1 to 3, kinds in strict order, the first kind that has anything in range wins; "near" from
1 km in tier 2 and always in tier 3; abandoned, destroyed and historical places are never used; saddle with the passes, ranges with the mountains, ridge / spur /
valley / canyon with the hills; `Pick` carries the tier and the kind).  `nameRoute` is unchanged (it already gave both distances).  On a copy of the author's real
database (138 climbs, through the real code path, offline): 52 named in tier 1, 42 in tier 2, 36 in tier 3, **8 unnamed**; by kind: 4 pass, 9 peak, 30 hill, 42 town,
45 neighbourhood.  The next `nch climbs` names the author's 138 again with these rules.  Next: step 3, the display-name function ("name (n/m)").

**Step 3 is built (2026-11-05)**: `climbs/display.nim`, pure: `displayNames(openArray[Shown]) -> seq[string]` (`Shown` = id, name, gainM), one text per climb
in the order given.  The group is the name without regard to case (each climb keeps its own spelling); n is the rank by gain (biggest 1, ties by id); the
suffix only when m > 1; no name (or blanks) is "unnamed".  Tests in `tests/climbs/test_display.nim` (8).  Next: step 4, showing the names.

**Step 4 is built (2026-11-05)**: `nch climbs` and `--sectors` lead each line with the name as shown (no more `#id`), in a column lined up by
characters (not bytes, so accents are fine); the old trailing name column is gone.  `report.shownNames` works the "(n/m)" over ALL sectors (a group
is global, not just the selected rides); a name over 30 characters is cut with "..." but keeps its " (n/m)".  `--sectors` is still biggest gain first.
On a copy of the real database: "Farellones", "Cuesta de Chacabuco", "Morro La Cabra (1/3)", "near El Arrayán (1/4)", "unnamed (1/8)", ...
**Noticed**: `nch --offline climbs` skips naming altogether, although the names can be made from the tables already loaded (`nameRoute` already says
"later" when data is missing); worth letting `--offline` name from what is loaded.  **Fixed (2026-11-05)**: `--offline` is now `Env.offline`, honoured in `download/fetchSource`: a file already in the cache is used, anything else is
refused silently (no request, no event), so the names are still made from what is loaded and `nch climbs` says "N climbs could not be named now (offline ...)".
Every download goes through `fetchSource`, so anything added later (the height correction) obeys `--offline` for free.  The pages of `--web` still load
Leaflet, d3 and the map tiles from the internet in the BROWSER; that is not `nch` using the network and `--offline` does not change it (open question).
Decided: `--web` is left alone under `--offline` (browsers keep the pinned libraries for a year: unpkg sends `max-age=31536000`; tiles need the network).

**Step 5 is built (2026-11-05)**: new module `sector/` (`params.nim`, `edit.nim`, `command.nim`; no tables of its own).  `nch sector` lists the climbs (biggest gain
first, "manual" against hand-given names); `--edit NAME --rename NEW` (NAME as shown, case ignored; a shared name needs its number, and the error lists them;
NEW at most 60 characters, no control characters, not ending in "(n/m)"; sets `manual = 1`, `name_checked = 1`); `--edit NAME --auto` (forgets the name,
`manual = 0`, `name_checked = 0`: the next `nch climbs` names it again).  `--user` before it is refused.  Logged as `saved`.  Tests: `tests/sector/`.
**`sector.kind` removed (2026-11-05)**: `climbs/004-no-kind.sql` drops it (it was written, never read).  Open for when a second kind of sector
(segments from overlapping activities) arrives: a type column (a CHECK, or a lookup table with a foreign key; SQLite has no enums) or a table for each kind
(a subclass-in-SQL question); every query of the climbs must then keep to its own kind so that other sectors do not appear in `nch climbs`.  Tried on a copy
of the real database: the migration runs.
**Step 6 is built (2026-11-05)**: `climbs/work.Counts` has `manual` (sectors with `manual = 1`); `describe` adds "; 2 names given by hand are lost" when there
are any, so `nch empty --sectors` (the message before the countdown) says it.  `--help` says so too.  (`--all` deletes the whole database; it says nothing new.)
Next: step 7 (docs; the tests came with each step).

**Idea (the author, 2026-11-05)**: `nch empty` with no arguments should show resource use (database size, cache size by part, ...), like `--offline` it gives
the user information and control over resources.  Today it is a usage error.  Fits the `cache.nim` convention (each module's `usage`).  Not built.

**Convention to consider (the author, 2026-11-05)**: a `cache.nim` in each module that keeps something to be emptied, so that what a module stores and how to
reset it is in one standard place and `empty` asks the modules instead of knowing them.  It covers modules that download (names now; the height correction
later) and those that only empty (each `empty` target: sectors, names, ...).  Likely shape: what it keeps (tables, folders under the cache), a `usage`, a
`clear`, and for downloaders the list of sources (the fetching stays in `download/`).  Not built; do it when the second kind appears, or as a refactor of `empty`.

## Where to read the code (a guide, 2026-11-05)

* **Climbs** (`src/nimchoo/climbs/`): `profile.nim` (positions to altitude every 10 m, smoothed) -> `detect.nim` (choochoo's detector; the
  score, the greedy search, reversals) -> `match.nim` (gates, a ride over a stored climb, "the same climb again") -> `work.nim` (the lazy
  pass: activities not yet looked at, in start order; efforts; new sectors; the version check) -> `naming.nim` (names for sectors) ->
  `display.nim` ("name (n/m)", pure) -> `report.nim` (the queries and the lines, pure formatting) -> `command.nim` (`nch climbs`); `001` to `004` `.sql`, `ddl.nim`.
* **Sector** (`sector/`): `params.nim` (the command line; which names are allowed), `edit.nim` (find a climb by the name shown, rename, hand back, the list), `command.nim` (`nch sector`).
* **Names** (`names/`): `outlines.nim` (GeoNames files, point-in-polygon), `countries.nim` (country of a position; the `Names` handle),
  `features.nim` (a country's file into the table), `lookup.nim` (generic: `prepare` a place's country and names, `featuresNear` a route),
  `climbpick.nim` (the rules for a climb, pure), `climb.nim` (`nameClimb`: lookup, distances from the top and middle, pick),
  `open.nim` (`openNames(g, st, command, say)`: cache, `--offline`, log and screen sinks; callers know nothing of downloads).
  Naming an activity will be a policy of its own beside `climb.nim`.
* **Downloads** (`download/`): `sources.nim` (the list), `fetch.nim` (room, checks, atomic write, events), `sinks.nim` (log and screen).
* **Other new parts**: `geo.nim` (flat geometry), `zipbytes.nim` (a zip from bytes), `cli/args.nim` (the one argument parser),
  `empty/command.nim` and `user/wipe.nim` (what `empty` and `user --remove` delete), `empty/cachefiles.nim`.
* Tests mirror the source tree under `tests/`; `tests/support/` has the made-up rides, zips and GeoNames data.
* The history of what was decided and measured is in this file, task by task (tasks 12 to 15 are the newest).

## Names refactor and activity naming (2026-11-05)

**Done**: `names/` split into the generic part (`lookup.nim`, `open.nim`) and the climb policy (`climb.nim`, `climbpick.nim`; `nameRoute` is now `nameClimb`,
`pickName` is `pickClimbName`); `nch climbs` uses `openNames`.  Next: the `cache.nim` convention and the height service (the author, in parallel).

**Activity naming (an idea of the author, to be designed)**: today the import names an activity from the nearest city (embedded list) to its FIRST point.
Three patterns to tell apart: A out and back (same route both ways; "<destination> and back"); B a loop (back at the start after a long way; "via <the most
significant feature along it that is also fairly far from the start>"); C one place to another ("<start> to <end>" or "to <end>").

**Decided (the author, 2026-11-05)**: an activity has a START (a place, standing alone: for finding rides from somewhere; today `activity.place_id`) and a NAME
(which need not repeat the start): A "<destination> and back", B "loop via <feature>", C "to <destination>"; no name when nothing fits.
**Order**: (1) `names/shape.nim`, a pure classifier (done), surveyed on the real rides; (2) the place service: `placeAt(names, lon, lat)` (GeoNames when the
country's names are loaded, the embedded list otherwise) and the import's start lookup moved behind it, `places/` becoming internal to `names/`;
(3) the naming rules and a lazy pass that fills the name (not at import: the names need downloads); the embedded city stays as the start until then.

**Step 1 is built (2026-11-05)**: `names/shape.nim`: `shapeOf(lons, lats)` -> local (never 1.5 km from the start), out and back, loop, one way; the route taken
every 50 m; the turning point is the furthest from the start; closed if the end is within 0.25 of that distance of the start; of the way back, the share within
50 m of the way out is `retraced`, out and back from 0.7.  Survey of the author's 1,650 activities with positions (1,123 cycling, 357 swimming, 170 training;
4.7 s): 546 local, 645 loop, 383 out and back, 76 one way.  Closed or not is clean (of 1,103 rides that go 1.5 km out, 961 end within a tenth of the way out,
about 60 are one way, few between).  Out and back or loop is NOT clean: `retraced` of the closed rides by tenths is 305, 62, 62, 52, 60, 65, 39, 67, 81, 186, 49
(a peak below 0.1 for loops, one above 0.9 for out and back, and about 440 in between: loops that share a road out, or out and backs with a detour).
Open: where to cut, or whether a middle class ("out and back with a loop") helps; to be looked at with the author on real rides.

**Decided (the author, 2026-11-05, after the survey)**: the shapes and their names: local "at <start>" (swimming and training too); A out and back
"<destination> and back"; B loop "loop via <feature>"; C one way "to <destination>"; **mixed** (a new class: closed, neither of the above) "around <feature>".
Thresholds on the share of the way back over the way out: under 0.1 loop, 0.9 or more out and back, between mixed (on the real rides 305, 235 and 488 of
1,028 closed ones).  `shapeOf` has them (`skMixed`, `loopBelow`, `outAndBackFrom`).
**The feature or destination**: something with spatial extent that the rider explores (a town, a valley, a range, a park, a lake), not a point (a pass, a bridge,
a peak).  Looked for within HALF the distance from the start to the furthest point, round the furthest point (for A and C the destination; for B and "around" the
features along the route, at least a third of the way out).  **Option 2**: kinds in a fixed order, the first kind with anything in range wins, the closest within a
kind (towns, then parks and reserves, then lakes, then ranges and valleys; to be settled on real picks).  The features table has only populated places and the
terrain subset: parks, reserves, lakes need more GeoNames codes loaded (class L `PRK` `RES` `RGN` `AREA`, class H `LK` `RSV`, and ranges/valleys/plains/plateaus in T; check the code list)
and the table rebuilt once.

**Step 2, first half, is built (2026-11-05)**: `names/place.nim`: `placeAt(st, lon, lat) -> Option[Place]` (name, country, distanceM, id), the one way to ask "which
place is near this position".  The import's start lookup and the country fallback in `countries.nim` both call it; `places/` (schema, the carried list, `nearestPlace`)
is now read only through it.  Behaviour unchanged: the answer is still the nearest town or city of the list carried in the program.
**Second half, to decide**: GeoNames in front of the list when a country's names are loaded.  `activity.place_id` points at the carried list's `place` table, so a
GeoNames start cannot be stored there.  Options: (a) keep `place_id` (offline, at import) and add a text `start_place` (name, country) that the lazy pass upgrades
from GeoNames, `nch list` showing it when there; (b) one text column only, filled at import from the list and replaced later; (c) leave the start as it is.

**Decided (the author, 2026-11-05)**: the built-in list of towns and cities (`places/`, 64,000 rows) is to go.  Starts and country come from the downloaded GeoNames
files only.  `activity.place_id` goes; the start becomes text on the activity, filled in later (the nearest populated place within 5 km, "near ..." further out,
nothing if none), the 1,650 existing starts being made again when the names are loaded.  Sea positions get no country.
**Principle (the author)**: do not work around a bad connection.  Code that needs the internet and refuses, with a clear message, when there is none is
fine, and simpler than code full of "later" and null cases.  **Simplifications this allows, to do when `places/` goes**: no `nsLater`/`rdLater`, no
`pending` count and "could not be named now" note, no `name_checked` half-states (a sector is named or has been looked at); `--offline` may go (the tests
already inject a fake network, which stays); download failures stop the command with the reason.  Names that really are absent (nothing near) stay null.

**Cleanup done (2026-11-05)**: no more back-filling when the internet returns.  A name is decided in the run that needs it, or the command stops with the reason
(`DownloadError`, new in `errors.nim`; `ensureCountries`/`ensureNames`/`prepare`/`countryAt` raise it, `Names.couldNot` builds the message from the last failed
download).  `--offline` (`Names.offline`, set by `openNames`): every question is answered "nothing", no fetch, no error; climbs found then are "" (shown "unnamed") and
stay so.  Gone: `nsLater`/`rdLater`, `NameResult`/`NameStatus` (`nameClimb` returns an `Option[Pick]`), `Named.pending` and its note, `Env.offline`, and the column
`sector.name_checked` (`climbs/005-names-now.sql`: name null = not named yet, which the next `nch climbs` does; "" = nothing near / offline).  `nch sector --edit NAME
--auto` forgets the name and names the climb at once (if the names cannot be had it says so, and the next `nch climbs` does it).  **Care**: running `nch --offline
climbs` on a database with unnamed (null) climbs gives them "" for good; use it for tests and trips, not before the names are first loaded.
**Left from this principle**: `places/` and `activity.place_id` still exist (the start and the sea fallback), and `countryAt` still falls back to them.

**More kinds of feature loaded (2026-11-05)**: `names/features.nim` keeps, besides all of class P, codes of class T (now also valleys, plains, plateaus, volcanoes,
deserts, gorges, peninsulas, islands), class L (`PRK`, the `RES*` reserves, `AREA`, `RGN`) and class H (`LK`, `LKS`, `RSV`, `BAY`, `GULF`, `FJD`, `GLCR`): the places
with an extent that an activity can be named for.  `names/002-more-kinds.sql` forgets the loaded features once, so each country is read again from its cached file
(no download; Chile took 1.5 s on the real database).  The climb names are unchanged (the climb rules ignore the new codes): 8 unnamed as before.
Next: the rules for naming an activity (the extent features: kinds in a fixed order, within half the distance to the furthest point), then the start from the
downloaded names and `places/` going.

**Shape rule changed, farms and bridges loaded (2026-11-05)**: `shapeOf` now measures `retracedNear`, the share of the FIRST THIRD of the way back over the way out; out
and back is 0.9 of either that or the whole way back; loop is under 0.1 of the whole; the rest mixed.  Reason: the author's many "El Toyo and back" rides come home another
way for the last stretch (whole-way share 0.37) but retrace the first part exactly (0.98+); `retracedNear` over the author's closed rides is bimodal (394 under 0.1,
462 at 0.9 or more).  Counts: out and back 460, loop 305, mixed 252, one way 76.  `names/003-spots.sql` + class S codes `FRM` `FRMS` `BDG` (El Toyo is a farm;
there is no bridge of that name in GeoNames) loaded, the countries read again from the cache.
**The destination rule tried in the survey (not yet in the code)**: anything within 1 km of the turning point first (kinds in order: town, section, park, lake,
range, spot), else within half the distance out (at least 1.5 km), kinds in the same order, the closest within a kind.  Result: "El Toyo and back" 35, "Farellones
and back" 42, "Corral Quemado and back" 72, "Lo Barnechea" 49, "El Arrayán" 30, "San José de Maipo" 23.  Open: the 72 rides that turn at the Estero de la Yerba Loca
(a stream, class H `STM`, 0.3 km from the turning point) are named Corral Quemado (a section, 0.6 km); streams are not loaded.

**Names by cells (2026-11-05)**: `names/features.nim` reads a country's GeoNames file by CELLS (one degree by one, named by the south-west corner as SRTM tiles are,
`floor` not truncation; longitude wraps at the date line, latitude clamps at the poles) when a name is wanted in them, and records each in `coverage`
(`names/004-cells.sql` drops `name_source`).  EVERY feature in a cell is kept, of every class and code: no filter, so no more reload migrations; the rules (`climbpick`,
the activity rules) choose.  `lookup.prepare(lons, lats, marginM)` takes the box round the positions (a margin in METRES, so wider in degrees of longitude towards the
poles), finds the countries it touches (the middle, corners and edge middles; so a border is covered) and `ensureCells` each; `featuresNear` has no country.
On the author's real database: 3 cells, 5,229 features (the whole of Chile is 46,467), the climb names unchanged (8 unnamed), 0.8 s.  The same cell function is
the SRTM tile of the height service (choochoo's `srtm/file.py` uses `floor` and the south-west corner too; its tiles overlap by one sample at each edge); to be
extracted when that is built.  Next: the 0.7 km first tier and the own-names command with suggestions (a query on the table), then the activity naming rules.

**Landmarks, `nch landmark` (2026-11-05)**: new module `landmark/` (`001-schema.sql`: `landmark(name unique, lon, lat, radius_m)`; `landmarks.nim` the library: add, remove,
list, `landmarkAt`; `suggest.nim`: `searchByName` and `featuresAround` on the `feature` table, every kind, so streams, farms ... appear; `params.nim`; `command.nim`).
`nch landmark` lists; `--search TEXT` and `--near LON,LAT` list numbered suggestions; `--add NAME --search/--near ... --pick N [--radius M]` or `--add NAME --at LON,LAT`;
`--remove NAME`.  **Shared by all users** (the climbs are shared, so a personal landmark could not name a shared climb).  `nameClimb` checks `landmarkAt` the top FIRST
(`pkLandmark`, tier 0), even offline.  Only places whose cells are read can be found by `--search`; `--near` reads (fetches) the cells round the position first.  The name of
the command avoids `places/`, which is to go.  Activity naming (tier 1 at 0.7 km and the shapes) is next and will use `landmarkAt` the turning point the same way.
On the author's database (a copy): `--near -70.364,-33.344` lists "Estero de la Yerba Loca" first; as a landmark it names 3 climbs whose tops are within 1 km.

**Activities are named (2026-11-05)**: `names/activity.nim` (rules, pure pieces tested apart; `nameActivity(names, lons, lats)` -> start place and name),
`importer/002-names.sql` (`activity.start_place`, `activity.name`: null = not named yet, "" = nothing to say / `--offline`), `importer/naming.nim`
(`ensureActivityNames`: every activity with a null name, in start order) run at the END of every `nch import` (so the names are decided in the run that imports;
a DownloadError says why and the activities are named by the next import).  Forms: "<dest> and back", "to <dest>", "loop via <feature>", "around <feature>",
"at <start>" for a local ride; the start place is the nearest populated place within 5 km, "near ..." to 20 km.  Landmarks first, then anything within 700 m of the
turning point, then within half the distance out (at least 1.5 km), kinds in order (town, section, park, lake, range, farm/bridge).  `nch list -v` shows `place`
(the start) and `name`.  On the author's real database (a copy): 1,650 activities, 1,115 with positions; the rest ("" start and name) have none; "Providencia" is the
start of 1,051; "Corral Quemado and back" 72, "Farellones and back" 42, "El Toyo and back" 35; 21 s the first time (Argentina and Britain fetched).
**Mistake caught**: the import command tests built `Globals` without `offline`, so the new naming step fetched `US.zip` (71 MB) into the real cache; removed; every
Globals in the tests now says `offline: true`.  **Left**: `places/`, `activity.place_id` and the importer's call to `placeAt` are unused by the display now; remove them
(and the country fallback in `countryAt`) next.

**`places/` is gone (2026-11-05)**: the carried list of towns and cities (`cities.tsv.gz`, `data.nim`, `seed.nim`, `tools/makecities.nim`, `names/place.nim`, the `nchSmallPlaces`
test flag, the tests of the list, the country fallback for the sea in `countryAt`, the import's `placeAt`/`place_id`) is deleted.  Starts and names come from the downloaded
GeoNames cells only.  The `place` table and `activity.place_id` STAY in the schema, empty and unused (`places/002-empty.sql` deletes the rows from databases that had them):
`place_id` has a foreign key and SQLite cannot drop such a column without rebuilding `activity`; both can go with the next rebuild of that table.  NOTICE now says GeoNames data
are downloaded.  Sea positions have no country.

**First squash of the schema (2026-11-05)**: every module's fragments are now one `001-schema.sql` with the final schema (see "squashing" in AGENTS.md for the rule: only while
the author alone has a database).  Gone: the `places` module (list, `place` table, `activity.place_id` and its index), `names/002` to `004` (`name_source` never exists),
`climbs/002` to `005` (`kind` and `name_checked` never exist), `importer/002`.  `activity` has `start_place` and `name`; `sector` has `name` and `manual`
(`manual in (0, 1)` now checked).  Checked first: a database built from the old fragments and one from the squashed files have the same tables, columns, indexes and foreign keys
except `place`, `activity.place_id`, its foreign key and `activity_place` (52 of 54 tables identical, the 2 differ only in those).  The author starts from zero:
`nch empty --all -f` (a copy of the old database file kept first), then `nch user --edit default --fthr N`, the models, and `nch import`.  An old database is refused with
"run `nch empty --all -f` and import again".  The test migrations of the old fragments are gone (nothing to migrate); the fragment names and count are in `tests/db/test_store.nim`.

**`empty --downloads` replaces `empty --names` (2026-11-05)**: it deletes the downloaded files (the whole `data/` part of the cache) and nothing in the database: the
tables read from them (`country`, `coverage`, `feature`) stay, and so do the names on climbs and activities, because those are copies, not links.  It needs no -f (the files
are fetched again when a new cell needs them), like `--cache`; it combines with the others (`--all` stands alone or with `--downloads` and `--cache`).  Reason: the files are
the only big part; deleting the tables too would gain nothing, as the copied names would not change; to make everything again from newer GeoNames data, `empty --all -f` and
import again (about 1.5 minutes).  `--downloads` also covers the height tiles when they come.  `countNames`, `clearNames` and `NameCounts` are gone (nothing used them).

**`nch list --name` and `--start` (2026-11-05)**: criteria on the text made at import.  `--name TEXT...` finds the text anywhere in `activity.name`, `--start TEXT...` in
`activity.start_place`; several words (or comma-separated) are alternatives; "none" is no name/start (null or ""); `latest` / `previous` mean the same WHOLE name/start place
as that activity (resolved in `resolve`, like `--sport`).  Case and accents are ignored in SQL by turning the typed text into a `glob` pattern in which each letter is a class
of its forms (`selection/fold.nim`: "arrayan" finds "El Arrayán", "ñuñoa" finds "Nunoa"); no schema change.  Nim 2.4 quirk met: `runes` on a constant string crashes (copy it to a
`let` first).  `-v` help now says it shows the start place and the name.  Not done: the same filters for the other commands that take criteria (none do yet).

**`nch list --path`, and the `file` column is `path` (2026-11-05)**: `--path TEXT...` finds the text (case and accents ignored, as `--name`) in the file's name or in ANY path the
file was seen at (`seen_file`; a copy has two); alternatives, commas; no `none`/`latest`/`previous` for it.  `-v` calls the last column `path`.

**`nch list --invert` (2026-11-05)**: the activities that do NOT meet the criteria taken together (not (a and b and c)), including those where a value is not recorded (the SQL
is `not coalesce((1 and ...), 0)`, so an unknown counts as no match).  `latest` and `previous` are found before inverting (`withoutLatest` clears `invert`); `--newest` and `--oldest`
apply after; it needs a real criterion to invert (`hasFilter`: not the users, the limits or the display); counts as a criterion for `--show`.  A per-criterion `--not` was the
alternative (kept out: "not this OR that" cannot be said with it, and "everything except X" is `--name X --invert`).

**OPEN QUESTION (the author, 2026-11-05): should `nch list --users A B C` exist?**  The global `--user NAME` already says whose data a command works on.  `--users` lets one listing (and so
one selection) hold activities of several users, which is why a selection can point at other users' activities, and every command that works on "the selection" has to decide
what to do with those that are not the current user's (`delete` deletes only the current user's and says how many it left; `climbs` shows the ranks among everyone anyway).  Keeping
it costs that complication; removing it makes a selection one user's, and comparing users would be done another way (the climbs already rank everyone's efforts).  Not decided.

**`nch delete` (2026-11-05)**: new module `delete/` (`remove.nim`: `planDelete`, `deleteActivities`; `command.nim`).  Deletes the CURRENT USER's activities in the selection (others' in the selection
are left alone and counted in the message), with everything that hangs off them (cascade: coords, route, segments, heart rate, impulses, efforts, climbs_done, the selection rows); the
climbs (sectors) and their names stay.  A file left with no activity is FORGOTTEN too (its row and the `seen_file` paths), so importing the folder again brings the activities back
(the author's choice).  A file with several activities stays until the last goes.  `-f` to confirm, 5 s countdown on a terminal.  **Idea, not built**: `exclude` would delete the
activities but KEEP the file record, so the import skips the file for good (a bad recording, a ride that is not yours).

**`nch delete` shows its progress (2026-11-05)**: deleting costs about 9 ms for a ride with a track and about 0.1 ms for an activity with none (5 rides 0.05 s, 500 activities 4.6 s, 1,381 mostly
rides 12.7 s), so the activities go in chunks of 25 (still one transaction) and, after the countdown, the same live display as the import and the climbs draws two lines, the first plain with the
word in bold, the second the counts in RED joined by grey dots (`deleting 340 / 1,381 activities` / `activities 340 · files 120`); nothing is drawn if it takes less than 150 ms; the last frame
stays on the screen, then the "done:" line.  A file is forgotten as soon as its last selected activity goes.  Checked under a pseudo-terminal: bold, red and grey codes, no green.

**Climbs: a ride that stops short makes a climb of its own; retiring; the duplicates report (2026-11-05)**.  The author's Farellones sector had ONE effort: climbs are worked out in
start order, the oldest ride (2017-03-03) went furthest and defined the sector (16.7 km, +1,211 m), and every later ride found a climb that overlapped it (14.0 to 15.1 km) and stopped
1.5 to 2.5 km of road short of its finish gate, so it earned no effort and was thrown away as "a repeat".  choochoo does exactly the same (`DISTINCT_CLIMB = 0.5`, the later climb is deleted):
the limitation is inherited, not a porting error.  Tried on the author's 1,108 rides (scratch copies): shortest-first order gains little (+69 efforts); the rule below finds 61% more
efforts.  **Rule (`algorithmVersion` 2)**: a climb found on a ride is "the same again" only if the ride EARNED AN EFFORT on that stored sector (a sector made from this ride counts, so laps
are not new climbs); otherwise it is a sector of its own, made at once (the author does not want to wait for votes: anyone riding to Farellones wants to see that climb) and matched to the
earlier rides.  On the real rides: 138 sectors / 2,661 efforts become 179 / 4,295 (rebuild: `nch empty --sectors -f`, then `nch climbs`, 32 s).  Known: a longer ride after a shorter one
crosses the short climb's gates and makes no sector (the common part is the sector; pinned by a test).
**Never delete a climb**, but **retire**: `sector.retired` (`climbs/002-retired.sql`); `nch sector --edit NAME --retire` / `--unretire` (one at a time), `--retired` lists them.  A retired climb
is hidden from `nch climbs` and `nch sector` but keeps its efforts and its place in the (n/m) numbering (so the gap shows: the author's wish), still takes the efforts of new rides and still counts
as stored (or the next short ride would make it again).  The lists say how many are hidden.  `nch sector --duplicates` groups the climbs that largely overlap (`isRepeat`: more than half of each
within 25 m of the other; the group can be a chain), the most ridden first, and offers `hide:` only for a climb that directly overlaps a MORE RIDDEN one (the author's 16.7 km Farellones
climb, one effort, is offered: the report decides nothing).  On the real rides: 44 suggestions among 179 climbs, ten of them in the Farellones road's chain (16.7 km down to 2.8 km).
**Ideas kept for later**: candidate climbs that need votes before they are real (rejected for now: delays the first sight of a climb), overlap-first discovery of segments (the bigger project:
stretches ridden by many rides; also for non-climb segments), `--retire` for all the suggested at once, near-miss tools (how far along a sector each ride got) and drawing sectors on the map.

**`nch list --climb TEXT...` (2026-11-05)**: the activities that have an effort on a climb whose name AS SHOWN ("Farellones (2/3)", retired climbs too) contains the text, case and accents ignored
(`fold.nim`: `foldText` in the program, `foldGlob` in SQL, one letter table).  The names are turned into sector ids when the command runs (`shownNames`), the SQL asks for an effort on them; no match
is an error.  It composes with the others: `--climb "corral quemado (2/9)" --save`, then `nch climbs`, `nch heatmap --web`, `nch delete`.  Real rides: `--climb farellones` finds 10, `--climb "farellones (1/3)"`
the one 98 km ride of 2017-03-03.
**Next, for a user who wants to plot and compare (the author, 2026-11-05)**: (1) `nch sector --efforts NAME`: each ride on a climb (date, name, time, rank); (2) `nch heatmap --climbs`: draw the climbs
(named, or those the selected rides rode) over the rides, in another colour, which also shows where rides turn round compared with a climb's finish; (3) an elevation profile of a climb; (4) **a cross-section
comparison of rides up a climb: plot the efforts against distance along the climb and show how each leads or lags the others (time gap by distance)**.  Also the near-miss report (how far along a climb each ride got).

**One standard description of an activity and of a climb (the author, 2026-11-05)**: `importer/describe.nim` and `climbs/describe.nim` (each module says its own things; the number formats are in `ui/units.nim`; see AGENTS.md).  Applied to: the `nch list` table (columns `start`, `sport`, `distance`, `active`,
`place / name`, `path`; the position coordinates are no longer shown, "no GPS" is said in the place/name column with -v), the `previous:` / `latest:` lines, the heading and the climbs of `nch climbs`
(the climb first, then `at 1.7km` and how it went), `climbs --sectors`, `nch sector`, `--duplicates`, the landmark lists (`0.7km`).  The columns of the climb tables are now name, cat, length, gain, gradient.
`nch list` shows the place and the name in every listing (it read them only with -v).  Not changed: messages that are not a description (the countdown "in 5 s", the help texts).

**WHERE WE STOPPED (2026-11-05, the author is changing editor)**: exploring the data as a user would.  Done in this stretch: `list --climb`, the standard descriptions (`importer/describe.nim`,
`climbs/describe.nim`, `ui/units.nim`), `nch delete`, retiring climbs, `--duplicates`, `--invert`, `--name/--start/--path`.  **Pending, not built**: `--efforts NAME` (the rides on one climb, best first, with `--by date`),
`heatmap --climbs`, an elevation profile of a climb, the lead/lag cross-section comparison, the near-miss report, `exclude`, retire-all.
**An open confusion to settle first**: the user sees both "climbs" and "sectors" (`nch climbs`, `nch sector`, `climbs --sectors`).  Proposal (1), liked in principle: for the user climbs are climbs; "sector" stays the table
name inside (where other kinds, e.g. segments from overlapping rides, will be added later with their own command); fold `nch sector`'s modes into `nch climbs` (`--all` for `--sectors`, `--edit NAME --rename/--auto/--retire/--unretire`,
`--retired`, `--duplicates`, `--efforts NAME`) and drop `nch sector`.  But the author thinks the confusion is DEEPER ("we need to look at fundamentals and maybe change very basic ideas"): to be discussed before any rename.

**THE SHAPE OF THE COMMANDS (the author's theory, agreed 2026-11-05; the guide is in AGENTS.md)**.  Plural commands for the types in the database, a common grammar, the selection as the default for activities, `--all`
for everything, singular for what is outside, `cache` and `db` in place of `empty`.  **Steps** (each a commit, tests and help updated, nothing kept for compatibility):
1. `climbs` takes over `sector` (`--all` for `--sectors`; `--edit NAME` with `--rename/--auto/--retire/--unretire`; `--retired`; `--duplicates`); `nch sector` goes.  **DONE 2026-11-05** (`sector/` is gone, its code is `climbs/params.nim`, `climbs/edit.nim`; `--all` lists with a `manual` mark; `--user` is allowed on `climbs`).
2. `list` becomes `activities` (`--select` for `--save`; no arguments = the selection, `--all` = all; `--show` goes), `delete` becomes `activities --delete`, `import` becomes `activities --import`; `--users` goes.
3. `user`, `model`, `landmark` become `users`, `models`, `landmarks`; `--remove` becomes `--delete`.
4. `cache` and `db` replace `empty`: `cache` alone lists the kinds and sizes (downloads, system, geojson, csv, html ...), `cache --delete KIND`; `db` alone says where and how big, `db --delete`;
   `empty --user NAME` is `activities --all --delete` (that user), `empty --sectors` is `climbs --delete --all` (only with `--all`: a reset); `empty` goes.
Later: `--efforts NAME` on `climbs` (the rides on one climb), `heatmap --climbs`, the elevation profile, the lead/lag comparison, the near-miss report, `exclude`.  "spatial" in the old plan meant the height-correction data (not yet).

**Step 2 of the command shape is done (2026-11-05):** `list` is `activities` (no criteria = the selection; criteria or `--all` search all; `--select`; `--delete [-f]`; `--import PATH... [-q] [--slow] [-j N]`), and `import`, `list`, `delete` are gone from the dispatcher (`importer/run.nim` and `delete/` are libraries now).  **Step 3 is done too:** `users`, `models`, `landmarks` (`--remove` is `--delete`; `landmarks --delete` needs `-f` as well).  **Step 4 is done too:** `cache` (no arguments: kinds, counts, sizes; `--delete KIND...` or `all`; no -f) and `db` (path and size; `--delete -f`) replace `empty`; `climbs --all --delete -f` (new) and `activities --all --delete -f` do the rest.  The command shape is finished.  **Second squash (2026-11-05): all tables strict, incremental auto-vacuum** (see AGENTS.md).  Next: the later list.

**Country outlines are Natural Earth's now (2026-11-06)**: `download/sources.nim` `naturalEarthCountries` (a shapefile zip of 0.8 MB, public domain, all 242 valid for GEOS); `names/countries.nim` loads it through SpatiaLite's VirtualShape; "which countries are here" is asked of a QUARTER-DEGREE CELL (`countriesOfCell`, table `country_cell`, `names/002-country-cells.sql`, which also forgets the old GeoNames outlines in an existing database): worked out once with `Intersects`, then a lookup.  The hand-written point-in-polygon code is gone (`outlines.nim` is `countryinfo.nim`).  Measured: SQL `Contains` costs 1.3 ms a call (GEOS rebuilds the polygon), which is why it is per cell and not per point.

**Maps and layers: a design under discussion (2026-11-06), in `MAP-LAYERS.md`** (nothing built; the author is thinking): `heatmap` becomes `map`; GeoJSON files are layers with logical properties only and the page (Leaflet) decides the look; each layer-making command (`activities`, `climbs`, `landmarks`) writes its own layer; an index of layers in the database (`layers` command, `--layer NAME`) with internal selection snapshots; plots would share the index with a second format.

**Mutable names, FIXED for the numbering (2026-11-06): a shared climb name carries a kept number as a subscript, `Farellones₃` (`sector.name_n`, `climbs/002-name-number.sql`, `climbs/ordinal.nim`); no "/m"; typed `Farellones₃`, `Farellones 3` or `Farellones3` (`ordinalForms`), also in `--name` and `activities --climb`.  Left: a name that is renamed away from, then reused by a new climb, can reuse the highest number; the names themselves (from GeoNames or by hand) can still be changed.  Original note (raised by the review in `MAP-LAYERS.md`):** a climb's displayed name `Farellones (2/3)` is made at display time (the `(n/m)` rank among climbs sharing a name), so it changes when climbs are found, retired or renamed; anything that remembers a name can point at something else.  The author is questioning mutable names and wants a stable handle for climbs (and for what else is named?) decided, whatever happens to the map.  Not yet discussed in detail.  The map/layers design is on hold ("too complex for now").

**The map (2026-11-06): DONE** as in AGENTS.md ("the map and its addresses"): `heatmap` is `map`, with `bits`/`check` in the address, the climbs in the same file, proquint file names.  Not done: labels, a legend, landmarks on the map, the page's palette from `palette.nim`, a plot command.  The layer ideas in `MAP-LAYERS.md` are set aside.

**Climb profile (2026-11-06): every 5 m, NOT smoothed** (`climbs/profile.nim`, algorithm version 3): the device's altitude is barometric and clean, and the old choochoo smoothed only terrain-model heights (a spline, s = 3 per point), never barometric ones.  Measured on the author's rides (scratch builds): at the same 50 m window the step (10 m vs 5 m) changes little (179 vs 183 sectors); the window is the lever (25 m: 192 sectors, 13% more efforts); no filtering at 5 m: 184 sectors, the same 4 HC climbs.  **When a terrain model (SRTM) is added, smooth ITS heights** (`smoothed` is there for that).  Not explained: the old Python found one climb from the start of El Arrayan 11 to the end of Farellones 3 (30 km, +1,430 m on the ride of 2022-01-29); nimchoo's detector, with the same phi 0.7, scores the 15 km part higher (1.20 vs 1.05) and splits it; the whole wins only with phi <= 0.4, or with different elevation data, or a different phi in the old database.  Rebuild after a change: `nch climbs --all --delete -f`.

**The map's look is in the source now (2026-11-06)**: three templates (`map/page.html`, `page.css`, `page-style.json`), see AGENTS.md.  Next ideas: labels, a legend, rules by property in the style file (colour by sport or year), landmarks.

**PENDING, in priority order (triage 2026-11-06; the author's notes in brackets).**
1. **Naming is slow, and the author wants to understand it first.**  After the last download `activities --import` names every activity: 11 s for 1,112 (measured on a copy, 2026-11-06): reading the routes 4.6 s (6.2 million `coords` rows read one at a time and parsed from text), `nameActivity` 6.2 s (not yet broken down).  Nothing is shown meanwhile.  Ideas: a progress line (cheap), reading positions in bigger pieces or from the stored `route`, and finding what is slow in `nameActivity`.  Go through how naming works with the author first.
2. **Shell completion script** (author asked to add it): generated from the `Spec` option tables in `cli/args.nim` (`nch --completions bash`), command names and options first; values (users, sports, climb names) later by calling `nch`.  `std/parseopt` has none; `cligen` unchecked.
3. **The later list**: `heatmap --climbs`, the elevation profile of a climb, the lead/lag cross-section comparison, the near-miss report, `exclude`, retire-all (how to choose which climbs to retire "can come later"), and the "climbs vs sectors" question.
4. **Revisit how the selection is used in `climbs`.**  The author is no longer sure the rule "the selection chooses the climbs, never the attempts" is right (*"maybe i was wrong"*); I had built it that way (`climbs/attempts.nim`: `selectedClimbs`, all of the user's attempts counted).  Settle this before more is added to `climbs`.  Ongoing with it: **blue for the selection in `climbs`** (candidates: `-v` attempts of selected rides; the `latest`/`rank` cells when the latest attempt is of a selected ride).  `latest` = the user's most recent attempt (by ride start) with its date; `rank` = its personal rank.
5. **Low priority** (*"i don't care much about logs"*): the log's `saved` word is green for every use, the selection's included.
Decided: the flag stays `--import` (not `--ingest`).

**DONE 2026-11-06 (after the pause):** `climbs` shows a summary row a climb (attempts, best, latest, personal rank), `-v` lists the attempts, `--everyone` swaps to the leaderboard (never both ranks), `--name TEXT...` picks climbs by name (replaces the idea of `--efforts`), `--all` is purely climbs; the selection chooses climbs, never attempts (`climbs/attempts.nim`).  `activities --import` selects what it added (nothing new: the selection stays).  The paragraph below is from before.

**Colour of the selection (2026-11-06): it is now BLUE** (a light blue, `\e[38;5;111m`, `#4dabf7`; a sixth palette colour, `ui/palette.nim`), as in the Claude Code interface; yellow is only a warning again.  Open: blue for the selection in `nch climbs`.  (Was: yellow means "selected" (the `activities` rows in the selection, `N match selected`, the calendar's selected days, the import's `selected ...` line, `saved N activities as the selection`).  `nch climbs` has none yet: the author agrees it probably needs some but does not yet know what (candidates: with `-v` the attempts of selected rides; in the summary row the `latest`/`rank` cells when the latest attempt is of a selected ride).  Also open: the log's `saved` word is green for every use, the selection's included.

**PAUSED (2026-11-05, the author is thinking).**  Everything is committed and pushed (main).  The database at ~/.local/share/nch/nch.db is a HALF-BUILT import (stopped on request): run `nch db --delete -f`, then re-import (~/fit/bike/*; a copy of the old one is in the scratchpad, not needed).  Next candidate: `climbs --efforts NAME` (NAME = the climb as `climbs --all` shows it, "(n/m)" included; best first, `--by date`).  Open questions for the author: (1) whose rides by default (the user's, with `--all` for everyone's)? (2) ignore the selection or use it?  Then `heatmap --climbs`, elevation profile, lead/lag comparison, near-miss report, `exclude`, retire-all; and the "climbs vs sectors" question.

- tried 2026-11-06 and dropped: auto-retire of duplicates (`--duplicates --retire/--unretire`): the rule retired long climbs into shorter near copies (Farellones into El Medio); would need 'only into one at least as big'. The report keeps the unique counts (against direct near copies).
