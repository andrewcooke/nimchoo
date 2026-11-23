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
  activities*, stretches*: int ## activities worked out, impulse rows written

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

proc stretchesOf(
    db: DbConn, activityId: ActivityId
): seq[tuple[n: int64, stretch: Stretch]] {.raises: [StoreError].} =
  ## The activity's stretches of riding, in time order, with their numbers.
  for (n, s0, s1) in db.query(
    tuple[n, startT, endT: int64],
    "select n, start_t, end_t from segment where activity_id = :activityId order by start_t",
    activityId = activityId,
  ):
    result.add (n, (s0, s1))

proc calculateActivity*(
    db: DbConn, activityId: ActivityId, fthr: int, m: Model
): int {.raises: [StoreError].} =
  ## Work out and store one activity's impulses for a model (replacing any), one a stretch; returns the number of
  ## stretches.
  let stretches = stretchesOf(db, activityId)
  var spans: seq[Stretch]
  for (_, s) in stretches:
    spans.add s
  let lumps = stretchImpulse(readings(db, activityId), spans, fthr, m)
  db.execute(
    "delete from impulse where activity_id = :activityId and model_id = :modelId",
    activityId = activityId,
    modelId = m.id,
  )
  if lumps.len == 0:
    return 0
  let st = prepareStmt(
    db,
    "insert into impulse(activity_id, model_id, n, centre_t, value) values (?, ?, ?, ?, ?)",
  )
  for k, (t, v) in lumps:
    st.bindInt(1, activityId)
    st.bindInt(2, m.id)
    st.bindInt(3, stretches[k].n)
    st.bindInt(4, t)
    st.bindReal(5, v)
    st.run()
  lumps.len

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
  ## threshold heart rate.  (Every stretch gets a row, of zero if need be, so an activity is worked
  ## out once.)  Called when impulses are wanted, by the commands that show them.
  let fthr = fthrOf(db, userId)
  if fthr.isNone:
    return
  for id in missing(db, userId, m.id):
    let n = calculateActivity(db, id, fthr.get, m)
    result.stretches += n
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

proc userLumps*(
    db: DbConn, userId: UserId, modelId: ModelId
): seq[Lump] {.raises: [StoreError].} =
  ## The user's impulses for a model, over all their activities, in time order (those of zero left out: they add nothing).
  db.query(
    Lump,
    """select i.centre_t, i.value from impulse i
        join activity a on a.id = i.activity_id join file f on f.id = a.file_id
        where f.user_id = :userId and i.model_id = :modelId and i.value > 0
        order by i.centre_t""",
    userId = userId,
    modelId = modelId,
  )
