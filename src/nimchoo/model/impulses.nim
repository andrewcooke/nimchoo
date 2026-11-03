## Working out and storing the impulses of activities (calc.nim does the arithmetic).
##
## An activity has impulses for a model if it has heart rate and its user has a threshold
## heart rate.  They are worked out only when wanted (by `nch ff`): `calculateMissing` finds
## what is lacking.  (A change of the threshold heart rate deletes the user's impulses: see the
## trigger in 001-schema.sql.)

import std/[options, strutils]
import db_connector/db_sqlite
import ../db/[statement, store]
import ../errors
import ./calc

{.push raises: [].}

type Calculated* = object
  activities*, hours*: int      ## activities worked out, impulse rows written

proc readings(db: DbConn, activityId: int64): seq[(int64, int)] {.raises: [StoreError].} =
  guard:
    for r in db.fastRows(sql"select t, bpm from heartrate where activity_id = ? order by t", activityId):
      try: result.add (parseBiggestInt(r[0]), parseInt(r[1]))
      except ValueError: raiseStore("bad heart rate row")

proc fthrOf*(db: DbConn, userId: int64): Option[int] {.raises: [StoreError].} =
  guard:
    let v = db.getValue(sql"select fthr from user_profile where user_id = ?", userId)
    if v.len > 0:
      try: return some(parseInt(v))
      except ValueError: discard

proc calculateActivity*(db: DbConn, activityId: int64, fthr: int, m: Model): int
    {.raises: [StoreError].} =
  ## Work out and store one activity's impulses for a model (replacing any); returns the
  ## number of hours.
  let rows = hourlyImpulse(readings(db, activityId), fthr, m)
  guard:
    db.exec(sql"delete from impulse where activity_id = ? and model_id = ?", activityId, m.id)
  if rows.len == 0: return 0
  let st = prepareStmt(db, "insert into impulse(activity_id, model_id, hour_t, value) values (?, ?, ?, ?)")
  try:
    for (hour, v) in rows:
      st.bindInt(1, activityId)
      st.bindInt(2, m.id)
      st.bindInt(3, hour)
      st.bindReal(4, v)
      st.run()
  finally:
    finalize(st)
  rows.len

proc missing(db: DbConn, userId: int64, modelId: int64): seq[int64] {.raises: [StoreError].} =
  ## The user's activities that have heart rate but no impulses for the model.
  guard:
    for r in db.fastRows(sql"""select a.id from activity a join file f on f.id = a.file_id
        where f.user_id = ?
          and exists (select 1 from heartrate h where h.activity_id = a.id)
          and not exists (select 1 from impulse i where i.activity_id = a.id and i.model_id = ?)
        order by a.id""", userId, modelId):
      try: result.add parseBiggestInt(r[0])
      except ValueError: raiseStore("bad activity id")

proc calculateMissing*(db: DbConn, userId: int64, m: Model): Calculated {.raises: [StoreError].} =
  ## Work out the impulses the user's activities lack for a model.  Nothing if the user has no
  ## threshold heart rate.  (An activity whose heart rate yields no hour at all is tried again
  ## each time; that costs little.)  Called when impulses are wanted, by the commands that show them.
  let fthr = fthrOf(db, userId)
  if fthr.isNone: return
  for id in missing(db, userId, m.id):
    let n = calculateActivity(db, id, fthr.get, m)
    result.hours += n
    if n > 0: inc result.activities
