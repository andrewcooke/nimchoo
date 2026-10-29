# TODO

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

### Step 1 result

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
6. [ ] Message decoding: scaling, composite, dynamic (dependency ordering),
       accumulators (with rollover), timestamp_16.  Plain records (no laziness /
       filter pipeline initially).
7. [ ] Validation: simple debug dump command; compare against
       `../choochoo/data/test` (76 .fit files; Garmin SDK CSV outputs are
       independent ground truth).

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
