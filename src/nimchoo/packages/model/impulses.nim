## Working out and storing the impulses of activities (calc.nim does the arithmetic).
##
## An activity has impulses for a model if it has heart rate and its user has a threshold
## heart rate.  They are worked out only when wanted (by `nch ff`): `calculateMissing` finds
## what is lacking.  (A change of the threshold heart rate deletes the user's impulses: see the
## trigger in 001-schema.sql.)

import std/options
import ../db/statement
import ../db/store
import ../../core/errors
import ../fit/time
import ../heartrate/stored
import ./calc

{.push raises: [].}

type Calculated* = object
  activities*, hours*: int ## activities worked out, impulse rows written

proc readings(
    db: DbConn, activityId: ActivityId
): seq[(UnixTime, int)] {.raises: [StoreError].} =
  readReadings(db, activityId)

proc fthrOf*(db: DbConn, userId: UserId): Option[int] {.raises: [StoreError].} =
  ## The user's threshold heart rate, if they have one.
  let got = db.queryOne(
    Option[int],
    "select fthr from user_profile where user_id = :userId",
    userId = userId,
  )
  if got.isSome:
    got.get
  else:
    none(int)

proc calculateActivity*(
    db: DbConn, activityId: ActivityId, fthr: int, m: Model
): int {.raises: [StoreError].} =
  ## Work out and store one activity's impulses for a model (replacing any); returns the
  ## number of hours.
  let rows = hourlyImpulse(readings(db, activityId), fthr, m)
  db.execute(
    "delete from impulse where activity_id = :activityId and model_id = :modelId",
    activityId = activityId,
    modelId = m.id,
  )
  if rows.len == 0:
    return 0
  let st = prepareStmt(
    db, "insert into impulse(activity_id, model_id, hour_t, value) values (?, ?, ?, ?)"
  )
  for (hour, v) in rows:
    st.bindInt(1, activityId)
    st.bindInt(2, m.id)
    st.bindInt(3, hour)
    st.bindReal(4, v)
    st.run()
  rows.len

proc missing(
    db: DbConn, userId: UserId, modelId: ModelId
): seq[ActivityId] {.raises: [StoreError].} =
  ## The user's activities that have heart rate but no impulses for the model.
  db.query(
    ActivityId,
    """select a.id from activity a join file f on f.id = a.file_id
        where f.user_id = :userId
          and exists (select 1 from heartrate_series h where h.activity_id = a.id)
          and not exists (select 1 from impulse i where i.activity_id = a.id and i.model_id = :modelId)
        order by a.id""",
    userId = userId,
    modelId = modelId,
  )

proc calculateMissing*(
    db: DbConn, userId: UserId, m: Model
): Calculated {.raises: [StoreError].} =
  ## Work out the impulses the user's activities lack for a model.  Nothing if the user has no
  ## threshold heart rate.  (An activity whose heart rate yields no hour at all is tried again
  ## each time; that costs little.)  Called when impulses are wanted, by the commands that show them.
  let fthr = fthrOf(db, userId)
  if fthr.isNone:
    return
  for id in missing(db, userId, m.id):
    let n = calculateActivity(db, id, fthr.get, m)
    result.hours += n
    if n > 0:
      inc result.activities

proc hasHeartRate*(db: DbConn, userId: UserId): bool {.raises: [StoreError].} =
  ## Whether the user has an activity with heart rate: what impulses are made from.
  db.scalar(
    int,
    """select exists (select 1 from activity a join file f on f.id = a.file_id
        where f.user_id = :userId
          and exists (select 1 from heartrate_series h where h.activity_id = a.id))""",
    userId = userId,
  ) == 1
