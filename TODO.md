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
* **CLI contract** (`src/nimchoo/commands/common.nim`): a command's `run(args): int` is
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

### Code layout

```
src/nch.nim                  the one command; a thin dispatcher (commands/*)
src/nimchoo/
  errors.nim  lookup.nim  warnings.nim   NchError and subtypes; must/mustMut; typed warnings
  xlsx.nim                    xlsx reader (zip + xml, from memory); Row, cell
  fit/                        the FIT file format and its decoding
    bytes.nim                 getUint/getInt/getBits/canRead, readBytes
    basetype.nim              BaseType, bad-value markers, decode of base-type values
    crc.nim  time.nim         the FIT CRC; FIT time, expandTimestamp16
    header.nim                FileHeader, readHeader, problems
    tokens.nim                the tokenizer (definitions, data, timestamps; no profile)
    records.nim               FieldValue, Record, Event; field, valueName
    decode.nim                the Decoder: plans, scaling, composite/dynamic, developer fields
    reader.nim                Reader: tokenizer + decoder as events/records iterators
    csvout.nim                SDK-format CSV lines
    activity.nim              readActivities: sessions + coordinates from a file (no database)
  profile/
    model.nim                 the profile as plain data (types, fields, messages)
    load.nim                  loading it from the Types/Messages sheets
    default.nim               the embedded Profile.xlsx
  db/                         the SQLite database
    migrations.nim            the schema, as a list of migrations
    store.nim                 Store, openStore (create + migrate + find the user), guard
    statement.nim             re-runnable prepared statements
    importer.nim              importFile: hash, skip repeats, write one file in one transaction
  commands/  common.nim fit.nim importfit.nim   exit codes, Globals; `nch fit`; `nch import`
tests/                        test_<module>.nim per area; csvcompare/csvreport compare with SDK CSVs
```

Dependencies run one way: `errors/lookup/warnings` -> `fit/bytes` -> `fit/{basetype,crc,
time}` -> `fit/header` -> `fit/tokens`; `profile/model` -> `profile/load` (+ `xlsx`);
`fit/records` -> `fit/decode` -> `fit/reader` -> `fit/csvout` -> `commands`.  Nothing
below `fit/records` imports from `profile/`.

The Task 1 notes below use the module names of the time (`binary.nim` is now
`fit/{bytes,basetype,crc,time,header}`, `profile.nim` is `profile/{model,load}`, and so on).

## Task 2: database (step 1 built: `nch import`; more is added piecemeal)

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
