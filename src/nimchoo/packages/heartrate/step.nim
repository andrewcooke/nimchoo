## The heart-rate channel of an import: the `heart_rate` field of each record,
## kept as beats per minute, one reading per second at most.  (The importer
## calls `write` for each activity, inside the transaction that imports it.)

import std/[math, tables]
import ../db/statement
import ../importer/channel
import ./series
import ../../core/errors
import ../fit/time
import ../../core/ids

{.push raises: [].}

const field* = "heart_rate"

func readings*(samples: Samples): seq[(UnixTime, int)] =
  ## (time, bpm) in time order.  Zero (and below) means "no reading": the strap
  ## has lost contact.
  for x in samples.getOrDefault(field):
    let bpm = int(round(x.v))
    if bpm >= 1:
      result.add (x.t, bpm)

proc write(
    db: DbConn, activityId: ActivityId, samples: Samples
): int {.nimcall, raises: [StoreError].} =
  let rows = readings(samples)
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
