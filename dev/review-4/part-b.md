# part B: fit, importer (status: done)

## 1. values from the file reach `doAssert`s at import: a corrupt FIT file crashes `nch import`

`src/nimchoo/packages/importer/series.nim:50` and `:62` (encodePositions), `src/nimchoo/packages/heartrate/series.nim:24-26`
(encodeReadings), fed by `importer/extract.nim:125` (coordOf) and `heartrate/step.nim:17` (readings).

What is wrong: the decoder reads a field with the base type the *definition* gives (`decode.nim:470`, `s.piece.defBase =
s.def.base`), so a file may declare `position_lat` as sint64 or `heart_rate` as uint16; and record times may be any FIT time
from 1998 to 2106.  `coordOf` and `readings` pass these on unchecked, and the encoders treat them as invariants:

* `heart_rate` declared uint16 with value 300 -> `readings` keeps bpm 300 -> `doAssert bpm in 1 .. 255` -> AssertionDefect.
* `position_lat` declared sint64 holding 2^40 -> lat about 9e7 degrees; `cleanCoords` cannot drop the only (or every)
  position -> `semicircles` -> `doAssert ... "a position outside the Earth reached the arrays"`.
* even with the declared sint32, `position_lat` 0x50000000 is 112.5 degrees: `haversine` (geo.nim:39) then has
  `cos(p1)*cos(p2) < 0`, `sqrt` of a negative is NaN, `min(1.0, NaN)` is NaN, and across a timer gap `joinStretches`
  -> `joinable` (stretch.nim:51) `doAssert g.metres >= 0` fails (in a release build; with float checks on, earlier).
  This one is inside `readActivities`, so the fuzzer could find it, but only with an auto-stopped timer gap as well.
* one record whose timestamp's top byte is damaged (2020 -> 2100): the record goes to the last session (extract.nim:409),
  nothing clips coordinates to the session, the spike filter cannot reject it (a century makes any distance reachable) ->
  `doAssert ... "within 68 years"` in encodePositions (and the same in encodeReadings).

`visitsOf` (visits.nim:15) already expects "a position that is not on the Earth", so the modules disagree about what
`Coord` can hold.  The fuzzers (`tests/importer/test_fuzz.nim`) stop at `readActivities`, so none of this is exercised.

Fix: parse at extraction: `coordOf` refuses (with a warning) a position off the Earth, `readings` a bpm outside 1..255, and
samples/coords outside the session's span (or > int32 seconds from its start) are dropped with a warning; extend the
importer fuzzer through `decodeFile` + `encodePositions`/`encodeReadings`/`routeWkb`/`visitsOf`.  Confidence: confirmed
by reading for the heart rate, the sint64 latitude and the time span (each needs one byte of a definition or a timestamp
changed); plausible for the NaN chain (the cleaning may drop the bad position first).

## 2. the import's log lines are written under the command `activities`, so the hint `nch log import ... --last` finds none

`src/nimchoo/packages/importer/logsink.nim:17` (`const command = "activities"`); the hint at `importer/sinks.nim:198`;
the naming and after-import lines at `importer/command.nim:131-147, 188` use `commandName` ("import").

What is wrong: since e5b9040 ("nch import is a command of importer ... The log names the command import") the file
events (`start`, `imported`, `duplicate`, `failed`, `advisory`, `note`, `done`) are still logged as `activities`, while
the run's other lines are `import`.  So one run is split across two command names, and the hint printed after every run
with failures, "more: `nch log import failed duplicate --last`", selects the `import` lines, which hold no `failed` or
`duplicate` events.  The test pins the wrong name (`tests/importer/test_logsink.nim:115`, "ERROR activities  failed").
The module doc (`nch log import advisory` finds one kind) says the intended thing.  A second list of the name, besides
`cmdname.commandName`: one fact in two places.

Fix: `logSink` uses `cmdname.commandName`; the test checks the line names `import`, and that the hint's command words
select the run's lines.  Confidence: confirmed.

## 3. a passing failure (database busy, file unreadable) is remembered as the file's verdict: it is never tried again

`src/nimchoo/packages/importer/batch.nim:294-296` (stores it), `:210-227` (skips it next time); kinds made at
`batch.nim:268`, `:286` (fkStore) and `work.nim:53` (fkUnreadable).

What is wrong: every failure, whatever its kind, is written to `seen_file` with the file's size and mtime, and a later run
that finds the same size and mtime reports it as `oKnownFailure` without reading the file.  That is right for what the
*content* decides (no activity, monitor, bad format, bad time), but `fkStore` ("database is locked" while `nch` serves a
page or another import runs; a full disk) and `fkUnreadable` (permissions, a file still being copied) say nothing about
the file.  Scenario: run `nch import ~/fit` while another `nch import` holds the write lock -> each file fails with a
StoreError -> the next, ordinary `nch import ~/fit` skips them all as known failures; only `--slow` recovers, and nothing
says so.  (failure.nim's doc says "a known failure is not tried again", without the distinction.)

Fix: give `FailureKind` a `remembered` (content-decided) property, `case`d over the enum, and record only those in
`seen_file`.  Confidence: confirmed (by reading).

## 4. `nch fit --profile MISSING FILE` blames the FIT file

`src/nimchoo/packages/fit/command.nim:123-143`.

What is wrong: `loadProfile(path)` raises `IOError` (declared, load.nim:343) when the profile cannot be read, but the
inner `try` catches only `NchError`; the IOError reaches the outer `except IOError` (`:140`), which wraps the message with
`about(files[0], ...)`.  Scenario: `nch fit --profile nosuch.xlsx ride.fit` -> "nch fit: ride.fit: cannot open:
nosuch.xlsx" instead of "nch fit: cannot use the profile: ...".  (Also `files = @[parsed.params.file]` (`:117`) is a
leftover of several files: `files[0]` everywhere.)

Fix: catch `NchError, IOError` in the inner `try`, and use `parsed.params.file` directly.  Confidence: confirmed.

## 5. import's lines break the counting rule, and say one thing in two places

`src/nimchoo/packages/importer/sinks.nim:30, 34, 66, 72-79`; `importer/command.nim:119-147`; `importer/display.nim:61` vs
`sinks.nim:242`.

What is wrong: the ui rule is "a count has commas from 1,000 ... `counted`/`count`".  `summaryLine` mixes them:
`counted(s.done, "file", "files") & ", " & $s.imported & " imported"` prints "3,000 files, 1113 imported, 1196
unchanged, 12 failed"; `failureBreakdown` (`$s.failures[k]`), `extrasText` (`$x.n` and its own `if x.n == 1` plural:
its doc promises "2,099 heart-rate readings", it prints "2099") and the naming line of command.nim (`$counts.named`,
`$counts.total`) do the same.  The guard test ("refuses commas written elsewhere") cannot see a missing comma.  Also:
the naming message is assembled twice, character for character (command.nim:123-127 for the screen, :142-146 for the
log), and the "read: " line is made twice (`display.readLine` and `plainLines`' own `"read: " & summaryLine`).
`sinks.plural` (sinks.nim:33) has no caller: a second `counted`, dead.  `summaryLine`'s doc example ("1113 files") is
stale.

Fix: `count`/`counted` for every number in these lines (extras through `counted(x.n, x.one, x.many)`), one function for
the naming text and one for the read line, delete `plural`; a test that a summary of >= 1,000 files has commas
everywhere.  Confidence: confirmed.

## 6. the delete confirmation describes activities differently from the table that listed them

`src/nimchoo/packages/importer/remove.nim:112-124` (used by `activities/deleterun.nim:42`).

What is wrong: `describe(plan)` gives the dates with `fromUnix(...).utc.format("yyyy-MM-dd")`, but every listing of
activities uses the user's time zone (`describe.dateTimeText(startT, zone)`); a ride started at 22:00 in Santiago
(UTC-3) is listed on the 30th and "would delete 1 activity (cycling 1) on 2026-10-31".  It says "no sport" where
`describe.sportText` says `-` (`notRecorded`), and writes the per-sport counts with `$k` (no commas, see 3).

Fix: `describe` takes the zone and uses `dateTimeText`'s date, `sportText`/`notRecorded`, and `count`.  Confidence:
confirmed (by reading).

## 7. module-level mutable state in the worker pool, and a failure stored as a result

`src/nimchoo/packages/importer/pool.nim:104-108`, `:116-138`; `importer/work.nim:17-35`.

What is wrong: (a) `config`, `jobs`, `results` and `channelsOpen` are module-level `var`s; CLAUDE.md says "no module-level
mutable state (exceptions today: `packages/util/profiling`, and the stop flag of `packages/db/checkpointer.nim`)", and
pool.nim is not in that list (the list is stale, or the rule is broken: say which).  (b) a worker whose profile does not
load stores `Profile()` as its profile ("a failure is never stored as a result") and then only rewrites outcomes that
are `poDecoded`; but with an empty profile no message has a name, so `readActivities` raises "no session" and the file
comes back `poFailed`/`fkNoActivity` -- remembered in `seen_file` as a content verdict (see 3) and never tried again.
Hard to reach today (the main thread loads the same bytes first), but the code's own fallback is wrong.  (c) `Job.index`
negative means stop, and `Prepared` is a bag (`decoded` valid for `poDecoded`, `failure`/`message` for `poFailed`)
rather than a variant on `outcome`.

Fix: a worker that cannot load the profile reports every job as failed with the profile's message (no stand-in); make
`Prepared` a variant object and `Job` an `Option`/variant; put pool.nim in CLAUDE.md's list with its reason (Nim's
`Channel` must be global) or move the state into `Pool`.  Confidence: (a), (c) confirmed; (b) confirmed in code,
unlikely in practice.

## 8. sentinels instead of `Option` where values cross the package's boundaries

* `importer/seen.nim:17-20, 37-50`: `Seen.fileId` "0 if it failed", `failure`/`message` "" if not, made with
  `coalesce(file_id, 0)`, `coalesce(failure, '')`; the stored kind is a string re-parsed by `failure.kindOf`, which turns
  an unknown label into `fkBadFormat` (validation after the fact).  `Seen` should be a variant
  (imported FileId | failed FailureKind+message), read with `Option` columns.
* `bundle/unpack.nim:45, 104-106, 149`: `Resolved.path` "" if none, `resolve(top: "")` meaning no cache: `resolve(b)` turns
  `cacheDir()`'s `Option` back into "" to pass it on.
* `fit/default.nim:30`, `importer/batch.nim:140`: `problem` "" meaning none (and `defaultProfile` returns a tuple).
* `importer/params.nim:12`: `jobs` "0: the default" (an `Option[int]`).
* `importer/events.nim:47-55`: `evFileDone` carries `counts` "for oImported", `failure` "for oFailed and oKnownFailure",
  `sameAs` "for oDuplicate", all present whatever the outcome (a bag checked by convention; a variant on `Outcome`
  would make a failed file without a kind unrepresentable).
* `fit/tokens.nim:38`: `timestampField` "or -1"; `fit/decode.nim:373` and `records.nim:33`: field number -1 if none.

Fix: `Option` in each (the FIT ones are hot paths, but `Option[int]` is a value type and costs little: measure).
Confidence: confirmed (rule breaks, not bugs).

## 9. `ActivityId` half adopted: activities are `int64` across the importer's interfaces

`importer/after.nim:113` (`ids: seq[int64]`), `importer/remove.nim:62-64, 74` (`ids`, `fileOf`, `fileIds: seq[int64]`,
`first`, `last: int64` "Unix seconds"), `importer/command.nim:45-57` (`newestActivity`, `newActivities`), while
`importer.nim`, `track.nim`, `heartrate/*` use `ActivityId`, `FileId` and `UnixTime` from `core/ids` / `fit/time`.

What is wrong: the distinct types exist so that an activity id cannot be passed as a file id or a time ("compiler-checked
is better than convention"); `remove.Plan` holds activity ids, file ids and times all as `int64`, side by side, and the
extension point `afterImport` hands every contributor bare `int64`s.

Fix: `seq[ActivityId]`, `seq[FileId]`, `UnixTime` in these signatures (the query helpers already read distinct ids, as
`knownFile` does).  Confidence: confirmed (drift, not a bug today).

## 10. stale references in the docs of this part

* `importer/extract.nim:4`: "Rules (see TODO.md, "Schema direction")": that section is in `dev/HISTORY.md:1900` now.
* `importer/importer.nim:85`: `channelsOf` "(see db/channel.nim)": the file is `importer/channel.nim`.
* `importer/sinks.nim:164`: `summaryLine` example "1113 files, 1112 imported": `counted` prints "1,113 files" (see 5).
* `importer/failure.nim:1-2`: "remembered ... so a known failure is not tried again", true of every kind (see 3).
* CLAUDE.md's list of module-level mutable state omits `importer/pool.nim` (see 7).

Fix: update each.  Confidence: confirmed.

## 11. the inflating child is sized by the caller's limit, not by the entry's declared size

`src/nimchoo/packages/util/zip/zipbytes.nim:92-99`, `zipchild.nim:157`.

What is wrong: `extractEntry` already refuses any result whose length is not `e.size` (`:98`), but hands the inflater
`limit` (256 MB by default, 64 MB for the countries), and the child sets its address space to `3 * limit + 512 MB`.  An
entry that declares 1 KB and inflates to 200 MB is inflated in full, written to a temporary file, read back, and only then
refused.  The in-process `inflateHere` (used for every xlsx, including the author's Profile.xlsx from the cache) has the
same shape with no ceiling at all.

Fix: pass `e.size` (already checked to be <= `limit`) as the inflater's limit.  Confidence: confirmed (robustness, not
a crash).

## what is good

* The FIT decoder is careful: every odd input is a collected `Warning` with an offset, `{.raises.}` is precise, and the
  three fuzzers (FIT, zip, xlsx, plus the profile) plus `nimble csvreport` against the SDK give real assurance up to
  `readActivities`.
* Times are typed (`FitTime` vs `UnixTime` distinct), and every conversion is guarded by `isFitTime` at the point of use.
* The import pipeline is cleanly split: pure decode on worker threads (`work.nim`), one writer, events to sinks, so the
  screen, the plain output and the log are pure functions of events and tested without a terminal.
* `bundle/unpack.nim`'s `decide` is a small pure decision with the I/O kept apart; the manifest logic is clear.
* Per-second arrays are written once, encoded/decoded symmetrically, and read back with length checks that raise
  `StoreError` rather than trusting the blob.
