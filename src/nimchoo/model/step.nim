## The impulse step of an import: after an activity's heart rate is written (the heart-rate
## step comes first), work out its impulses for every model, if its user has a threshold
## heart rate.

import std/[options, strutils]
import db_connector/db_sqlite
import ../db/[channel, store]
import ../errors
import ./[impulses, models]

{.push raises: [].}

proc write(db: DbConn, activityId: int64, samples: Samples): int
    {.nimcall, raises: [StoreError].} =
  var userId = 0'i64
  guard:
    let v = db.getValue(sql"""select f.user_id from activity a join file f on f.id = a.file_id
                              where a.id = ?""", activityId)
    if v.len == 0: return 0
    try: userId = parseBiggestInt(v)
    except ValueError: return 0
  let fthr = fthrOf(db, userId)
  if fthr.isNone: return 0
  for m in loadModels(db): result += calculateActivity(db, activityId, fthr.get, m)

let impulseStep* = ImportStep(label: "impulse hour", labels: "impulse hours",
                              channels: @[], write: write)
