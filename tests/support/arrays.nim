## Test data written the way the importer writes it: the positions and the heart rate of an activity as arrays.

import nimchoo/packages/db/statement
import nimchoo/packages/fit/time
import nimchoo/packages/heartrate/series as heartSeries
import nimchoo/packages/importer/[coord, series]

proc putTrack*(db: DbConn, activityId: int64, coords: seq[Coord]) =
  ## The `track` row of an activity (none if there are no positions).
  if coords.len == 0:
    return
  let a = encodePositions(coords)
  let st = prepareStmt(
    db,
    "insert into track(activity_id, t0, n, t, lon, lat, alt) values (?, ?, ?, ?, ?, ?, ?)",
  )
  st.bindInt(1, activityId)
  st.bindInt(2, int64(a.t0))
  st.bindInt(3, a.count)
  st.bindBlob(4, a.t)
  st.bindBlob(5, a.lon)
  st.bindBlob(6, a.lat)
  st.bindBlob(7, a.alt)
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
