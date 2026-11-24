## The channels of an activity as the database holds them: the rows of `channel_series` (series.nim).

import ../db/statement
import ../db/store
import ../../core/errors
import ../fit/time
import ../../core/ids
import ./[kinds, series]

{.push raises: [].}

const
  headSql* =
    "select start_epoch, n_readings from channel_series where activity_id = :activityId and channel = :channel"
  arraysSql* =
    "select gaps_s, readings from channel_series where activity_id = ? and channel = ?"

proc readStored*(
    db: DbConn, id: ActivityId, ch: ChannelKind
): seq[(UnixTime, int64)] {.raises: [StoreError].} =
  ## (time, stored value) in time order (none if the activity does not have the channel).
  let head =
    db.query(tuple[start, n: int64], headSql, activityId = id, channel = specs[ch].name)
  if head.len == 0:
    return
  let arrays = prepareStmt(db, arraysSql)
  arrays.bindInt(1, id)
  arrays.bindText(2, specs[ch].name)
  if not arrays.nextRow():
    return
  unpack(
    ch,
    Packed(
      start: UnixTime(head[0].start),
      count: int(head[0].n),
      gaps: arrays.blobAt(0),
      values: arrays.blobAt(1),
    ),
  )

proc readChannel*(
    db: DbConn, id: ActivityId, ch: ChannelKind
): seq[(UnixTime, float)] {.raises: [StoreError].} =
  ## (time, value in the channel's unit) in time order (none if the activity does not have the channel).
  for (t, v) in readStored(db, id, ch):
    result.add (t, value(ch, v))
