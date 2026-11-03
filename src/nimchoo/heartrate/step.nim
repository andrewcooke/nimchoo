## The heart-rate channel of an import: the `heart_rate` field of each record,
## kept as beats per minute, one reading per second at most.  (The importer
## calls `write` for each activity, inside the transaction that imports it.)

import std/[math, tables]
import db_connector/db_sqlite
import ../db/[channel, statement]
import ../errors

{.push raises: [].}

const field* = "heart_rate"

func readings*(samples: Samples): seq[(int64, int)] =
  ## (time, bpm) in time order.  Zero (and below) means "no reading": the strap
  ## has lost contact.
  for x in samples.getOrDefault(field):
    let bpm = int(round(x.v))
    if bpm >= 1: result.add (x.t, bpm)

proc write(db: DbConn, activityId: int64, samples: Samples): int
    {.nimcall, raises: [StoreError].} =
  let rows = readings(samples)
  if rows.len == 0: return 0
  let st = prepareStmt(db, "insert into heartrate(activity_id, t, bpm) values (?, ?, ?)")
  try:
    for (t, bpm) in rows:
      st.bindInt(1, activityId)
      st.bindInt(2, t)
      st.bindInt(3, int64(bpm))
      st.run()
  finally:
    finalize(st)
  rows.len

let heartrateStep* = ImportStep(label: "heart-rate reading", labels: "heart-rate readings",
                                channels: @[field], write: write)
