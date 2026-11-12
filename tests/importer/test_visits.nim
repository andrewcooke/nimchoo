import ../support/arrays
import nimchoo/packages/importer/series
import nimchoo/packages/fit/time
import std/[options, os, unittest]
import ../support/shims
import nimchoo/core/errors
import nimchoo/packages/db/statement
import nimchoo/packages/fit/[load, time]
import nimchoo/packages/geo/cells
import nimchoo/packages/importer/[extract, visits]
import nimchoo/packages/user/session
import nimchoo/packages/util/bytes/bytes
import nimchoo/packages/util/warnings/warnings
from nimchoo/registry import allFragments, allAccess

proc at(t: int, lon, lat: float): Coord =
  Coord(t: UnixTime(t), lon: lon, lat: lat, alt: none(float))

const
  a = (-70.6500, -33.4500) # (two samples within one cell: 1/1024 degree is about 100 m)
  a2 = (-70.6502, -33.4501)
  b = (-70.6400, -33.4500) # (a few cells east)

suite "visits: the cells a route went through":
  test "no samples, no visits; one sample is a visit of one instant":
    check visitsOf(newSeq[Coord]()).len == 0
    let v = visitsOf([at(5, a[0], a[1])])
    check v.len == 1 and v[0].tIn == UnixTime(5) and v[0].tOut == UnixTime(5)
    check v[0].cell == cellOf(a[0], a[1]).get
  test "samples in one cell are one visit, from the first to the last":
    check cellOf(a[0], a[1]) == cellOf(a2[0], a2[1])
    let v = visitsOf([at(1, a[0], a[1]), at(2, a2[0], a2[1]), at(3, a[0], a[1])])
    check v.len == 1 and v[0].tIn == UnixTime(1) and v[0].tOut == UnixTime(3)
  test "leaving a cell and coming back is two visits":
    let v = visitsOf([at(1, a[0], a[1]), at(2, b[0], b[1]), at(3, a[0], a[1])])
    check v.len == 3
    check v[0].cell == v[2].cell and v[0].cell != v[1].cell
    check v[1].tIn == UnixTime(2) and v[2].tIn == UnixTime(3)
  test "a sample off the Earth is left out, and the run goes on across it":
    let v = visitsOf([at(1, a[0], a[1]), at(2, 999.0, 0.0), at(3, a2[0], a2[1])])
    check v.len == 1 and v[0].tIn == UnixTime(1) and v[0].tOut == UnixTime(3)

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"

proc importedRide(name: string): Session =
  let path = getTempDir() / "nch-test-visits" / name & ".db"
  createDir(parentDir(path))
  removeFile(path)
  result = openSession(path, allFragments, access = allAccess)
  var ws: seq[Warning]
  discard result.importFile(loadProfile(profilePath), "r.fit", readBytes(ride), ws)

proc rows(s: Session): seq[tuple[activityId, cell, tIn, tOut: int64]] =
  s.db.query(
    tuple[activityId, cell, tIn, tOut: int64],
    "select activity_id, cell, t_in, t_out from route_cell order by activity_id, t_in",
  )

suite "track: the positions as arrays":
  test "the arrays hold the positions that coords does":
    let s = importedRide("track")
    defer:
      s.close()
    let st = prepareStmt(s.db, "select t0, n, t, lon, lat, alt from track")
    check st.nextRow()
    let p = Positions(
      t0: UnixTime(s.db.scalar(int64, "select t0 from track")),
      count: s.db.scalar(int, "select n from track"),
      t: st.blobAt(2),
      lon: st.blobAt(3),
      lat: st.blobAt(4),
      alt: st.blobAt(5),
    )
    let decoded = decodePositions(p)
    s.db.materialise()
    let rows = s.db.query(
      tuple[t: int64, lon, lat: float], "select t, lon, lat from coords order by t"
    )
    check decoded.len == rows.len and decoded.len > 100
    for i in 0 ..< rows.len:
      check int64(decoded[i].t) == rows[i].t
      check abs(decoded[i].lon - rows[i].lon) < 1e-9 and
        abs(decoded[i].lat - rows[i].lat) < 1e-9
  test "deleting an activity deletes its track":
    let s = importedRide("track-delete")
    defer:
      s.close()
    s.db.execute("delete from activity")
    check s.db.scalar(int, "select count(*) from track") == 0

suite "route_cell: written with the samples":
  test "a real ride has visits, and they are what the samples say":
    let s = importedRide("ride")
    defer:
      s.close()
    let written = rows(s)
    check written.len > 100
    check s.db.scalar(int, "select count(*) from route_cell") == written.len
    # each visit starts at a sample that is in its cell, they are in order and disjoint (the invariants say so too)
    s.db.materialise()
    check s.db.scalar(
      int,
      """select count(*) from route_cell r join coords c on c.activity_id = r.activity_id and c.t = r.t_in
          where cell(c.lon, c.lat) != r.cell""",
    ) == 0
    for i in 1 ..< written.len:
      check written[i].tIn > written[i - 1].tOut
  test "deleting an activity deletes its visits":
    let s = importedRide("delete")
    defer:
      s.close()
    check rows(s).len > 0
    s.db.execute("delete from activity")
    check rows(s).len == 0
