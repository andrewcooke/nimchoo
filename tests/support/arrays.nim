## Test data written the way the importer writes it: the positions and the heart rate of an activity as arrays.

import nimchoo/packages/db/statement
import nimchoo/packages/fit/time
import nimchoo/packages/heartrate/series as heartSeries
import nimchoo/core/ids
import nimchoo/packages/heartrate/stored
import nimchoo/packages/importer/[coord, series, track]

proc putTrack*(db: DbConn, activityId: int64, coords: seq[Coord]) =
  ## The `track` row of an activity (none if there are no positions).
  if coords.len == 0:
    return
  let a = encodePositions(coords)
  let st = prepareStmt(
    db,
    "insert into track(activity_id, t0, t1, n, t, lon, lat, alt) values (?, ?, ?, ?, ?, ?, ?, ?)",
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

proc putHeart*(db: DbConn, activityId: int64, rows: seq[(UnixTime, int)]) =
  ## The `heartrate_series` row of an activity (none if there are no readings).
  if rows.len == 0:
    return
  let a = encodeReadings(rows)
  let st = prepareStmt(
    db,
    "insert into heartrate_series(activity_id, t0, n, t, bpm) values (?, ?, ?, ?, ?)",
  )
  st.bindInt(1, activityId)
  st.bindInt(2, int64(a.t0))
  st.bindInt(3, a.count)
  st.bindBlob(4, a.t)
  st.bindBlob(5, a.bpm)
  st.run()

proc materialise*(db: DbConn) =
  ## Temporary tables `coords` and `heartrate` with the rows the arrays hold, so that a test can ask SQL about them (the program
  ## never does: it reads the arrays).
  db.execute("drop table if exists temp.coords")
  db.execute("drop table if exists temp.heartrate")
  db.execute(
    "create temp table coords(activity_id integer, t integer, lon real, lat real, alt real)"
  )
  db.execute("create temp table heartrate(activity_id integer, t integer, bpm integer)")
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
  for id in db.query(
    int64, "select activity_id from heartrate_series order by activity_id"
  ):
    for (t, bpm) in readReadings(db, ActivityId(id)):
      db.execute(
        "insert into temp.heartrate values (:id, :t, :bpm)",
        id = id,
        t = int64(t),
        bpm = bpm,
      )
