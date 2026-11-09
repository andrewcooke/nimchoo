## The heart-rate channel of an import: the `heart_rate` field of each record,
## kept as beats per minute, one reading per second at most.  (The importer
## calls `write` for each activity, inside the transaction that imports it.)

import std/[math, tables]
import db_connector/db_sqlite
import ../db/[channel, multirow, statement]
import ../core/errors
import ../fit/time
import ../core/ids

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
  var insert =
    initMultiInsert(db, "insert into heartrate(activity_id, t, bpm) values ", 3)
  var i = 0
  while i < rows.len: # many rows to a statement
    let n = min(rowsPerStatement, rows.len - i)
    let st = insert.statement(n)
    for r in 0 ..< n:
      st.bindInt(3 * r + 1, activityId)
      st.bindInt(3 * r + 2, int64(rows[i + r][0]))
      st.bindInt(3 * r + 3, int64(rows[i + r][1]))
    st.run()
    i += n
  rows.len

let heartrateStep* = ImportStep(
  label: "heart-rate reading",
  labels: "heart-rate readings",
  channels: @[field],
  write: write,
)
