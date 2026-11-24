## Test data written the way the importer writes it: the positions and the channels of an activity as arrays.

import std/options
import nimchoo/packages/db/statement
import nimchoo/packages/fit/time
import nimchoo/packages/channels/[kinds, series as channelSeries]
import nimchoo/core/ids
import nimchoo/packages/channels/stored
import nimchoo/packages/importer/[coord, series, track]

proc putTrack*(db: DbConn, activityId: int64, coords: seq[Coord]) =
  ## The `track` row of an activity (none if there are no positions).
  if coords.len == 0:
    return
  let a = encodePositions(coords)
  let st = prepareStmt(
    db,
    "insert into track(activity_id, start_epoch, end_epoch, n_readings, offsets_s, lon_semi, lat_semi, alt_fit) values (?, ?, ?, ?, ?, ?, ?, ?)",
  )
  st.bindInt(1, activityId)
  st.bindInt(2, int64(a.t0))
  st.bindInt(3, int64(coords[^1].t))
  st.bindInt(4, a.count)
  st.bindBlob(5, a.t)
  st.bindBlob(6, a.lon)
  st.bindBlob(7, a.lat)
  st.bindBlob(8, a.alt)
  st.run()

proc putChannel*(
    db: DbConn, activityId: int64, ch: ChannelKind, rows: seq[(UnixTime, int64)]
) =
  ## The `channel_series` row of an activity's channel (none if there are no readings), values as they are stored.
  if rows.len == 0:
    return
  let a = pack(ch, rows)
  let st = prepareStmt(
    db,
    "insert into channel_series(activity_id, channel, start_epoch, n_readings, gaps_s, readings) values (?, ?, ?, ?, ?, ?)",
  )
  st.bindInt(1, activityId)
  st.bindText(2, specs[ch].name)
  st.bindInt(3, int64(a.start))
  st.bindInt(4, a.count)
  st.bindBlob(5, a.gaps)
  st.bindBlob(6, a.values)
  st.run()

proc putHeart*(db: DbConn, activityId: int64, rows: seq[(UnixTime, int)]) =
  ## The heart rate of an activity (none if there are no readings).
  var stored: seq[(UnixTime, int64)]
  for (t, bpm) in rows:
    stored.add (t, int64(bpm))
  putChannel(db, activityId, chHeartRate, stored)

proc materialise*(db: DbConn) =
  ## Temporary tables `coords` and `heartrate` (and `channels`, every channel) with the rows the arrays hold, so that a test can ask SQL about them (the program
  ## never does: it reads the arrays).
  db.execute("drop table if exists temp.coords")
  db.execute("drop table if exists temp.heartrate")
  db.execute(
    "create temp table coords(activity_id integer, t integer, lon real, lat real, alt real)"
  )
  db.execute("drop table if exists temp.channels")
  db.execute("create temp table heartrate(activity_id integer, t integer, bpm integer)")
  db.execute(
    "create temp table channels(activity_id integer, channel text, t integer, value real)"
  )
  for id in db.query(int64, "select activity_id from track order by activity_id"):
    for c in readPositions(db, ActivityId(id)):
      db.execute(
        "insert into temp.coords values (:id, :t, :lon, :lat, :alt)",
        id = id,
        t = int64(c.t),
        lon = c.lon,
        lat = c.lat,
        alt = c.alt,
      )
  for (id, name) in db.query(
    (int64, string), "select activity_id, channel from channel_series order by 1, 2"
  ):
    let ch = channelNamed(name).get
    for (t, v) in readChannel(db, ActivityId(id), ch):
      db.execute(
        "insert into temp.channels values (:id, :name, :t, :v)",
        id = id,
        name = name,
        t = int64(t),
        v = v,
      )
      if ch == chHeartRate:
        db.execute(
          "insert into temp.heartrate values (:id, :t, :bpm)",
          id = id,
          t = int64(t),
          bpm = int64(v),
        )
