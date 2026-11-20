## The heart-rate channel of an import: the `heart_rate` field of each record,
## kept as beats per minute, one reading per second at most.  (The importer
## calls `write` for each activity, inside the transaction that imports it.)

import std/[math, strformat, tables]
import ../ui/units
import ../util/warnings/warnings
import ../db/statement
import ../importer/channel
import ./series
import ../../core/errors
import ../fit/time
import ../../core/ids

{.push raises: [].}

const field* = "heart_rate"

func readings*(samples: Samples): tuple[rows: seq[(UnixTime, int)], dropped: int] =
  ## (time, bpm) in time order, and how many values were not a heart rate.  A heart rate is 1 to 254: the field is a
  ## byte, whose 255 is FIT's "invalid" (the decoder drops it: a strap that has lost contact writes it), so anything
  ## else comes from a damaged file (a file may declare the field wider).  Zero is not one either: nothing known
  ## gives it a meaning, and none of the author's readings is zero (two samples of 60 files, 2026-11-20).
  for x in samples.getOrDefault(field):
    let bpm = int(round(x.v))
    if bpm in 1 .. 254:
      result.rows.add (x.t, bpm)
    else:
      inc result.dropped

proc write(
    db: DbConn, activityId: ActivityId, samples: Samples, warnings: var seq[Warning]
): int {.nimcall, raises: [StoreError].} =
  let (rows, dropped) = readings(samples)
  if dropped > 0:
    let values = counted(dropped, "value", "values")
    warnings.add wkBadReading, 0, fmt"heart rate: {values} not from 1 to 254 (dropped)"
  if rows.len == 0:
    return 0
  let arrays = encodeReadings(rows)
  let series = prepareStmt(
    db,
    "insert into heartrate_series(activity_id, t0, n, t, bpm) values (?, ?, ?, ?, ?)",
  )
  series.bindInt(1, activityId)
  series.bindInt(2, int64(arrays.t0))
  series.bindInt(3, arrays.count)
  series.bindBlob(4, arrays.t)
  series.bindBlob(5, arrays.bpm)
  series.run()
  rows.len

let heartrateStep* = ImportStep(
  label: "heart-rate reading",
  labels: "heart-rate readings",
  channels: @[field],
  write: write,
)
