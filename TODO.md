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
  profile/
    model.nim                 the profile as plain data (types, fields, messages)
    load.nim                  loading it from the Types/Messages sheets
    default.nim               the embedded Profile.xlsx
  commands/  common.nim fit.nim   exit codes and stderr helpers; `nch fit`
tests/                        test_<module>.nim per area; csvcompare/csvreport compare with SDK CSVs
```

Dependencies run one way: `errors/lookup/warnings` -> `fit/bytes` -> `fit/{basetype,crc,
time}` -> `fit/header` -> `fit/tokens`; `profile/model` -> `profile/load` (+ `xlsx`);
`fit/records` -> `fit/decode` -> `fit/reader` -> `fit/csvout` -> `commands`.  Nothing
below `fit/records` imports from `profile/`.

The Task 1 notes below use the module names of the time (`binary.nim` is now
`fit/{bytes,basetype,crc,time,header}`, `profile.nim` is `profile/{model,load}`, and so on).

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
