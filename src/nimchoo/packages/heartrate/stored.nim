## The heart rate of an activity as the database holds it: the arrays of `heartrate_series` (series.nim).

import ../db/statement
import ../db/store
import ../../core/errors
import ../fit/time
import ../../core/ids
import ./series

{.push raises: [].}

const
  headSql* = "select t0, n from heartrate_series where activity_id = :activityId"
  arraysSql* = "select t, bpm from heartrate_series where activity_id = ?"

proc readReadings*(
    db: DbConn, id: ActivityId
): seq[(UnixTime, int)] {.raises: [StoreError].} =
  ## (time, bpm) in time order (none if the activity has no heart rate).
  let head = db.query(tuple[t0, n: int64], headSql, activityId = id)
  if head.len == 0:
    return
  let arrays = prepareStmt(db, arraysSql)
  arrays.bindInt(1, id)
  if not arrays.nextRow():
    return
  decodeReadings(
    Readings(
      t0: UnixTime(head[0].t0),
      count: int(head[0].n),
      t: arrays.blobAt(0),
      bpm: arrays.blobAt(1),
    )
  )
