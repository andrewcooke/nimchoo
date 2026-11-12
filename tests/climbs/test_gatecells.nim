import std/[algorithm, options, os, unittest]
import nimchoo/packages/db/statement
import nimchoo/packages/geo/cells
import nimchoo/packages/climbs/work
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

let dir = getTempDir() / "nch-test-gatecells"

proc fresh(name: string): Session =
  removeDir(dir / name)
  openSession(dir / name / "x.db", allFragments, access = allAccess)

proc addActivity(s: Session, sha: string): int64 =
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, 0)",
    userId = s.userId,
    name = sha,
    sha256 = sha,
  )
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t) select max(id), 0, 0, 1 from file"
  )
  s.db.scalar(int64, "select max(id) from activity")

proc addSector(s: Session, lon0, lat0, lon1, lat1: float): int64 =
  ## A climb from one point to another (a straight line is enough: only its ends make the cells).
  s.db.execute(
    "insert into sector(length_m, gain_m, gradient, route) values (1000, 100, 8, GeomFromText(:wkt, 4326))",
    wkt =
      "LINESTRING Z(" & $lon0 & " " & $lat0 & " 10, " & $lon1 & " " & $lat1 & " 110)",
  )
  s.db.scalar(int64, "select max(id) from sector")

proc visit(s: Session, activity: int64, lon, lat: float, t: int) =
  s.db.execute(
    "insert into route_cell(activity_id, cell, t_in, t_out) values (:a, cell(:lon, :lat), :t, :t)",
    a = activity,
    lon = lon,
    lat = lat,
    t = t,
  )

proc expected(lon, lat: float): seq[int64] =
  ## The cells round a gate, as geo/cells says: as many either way as 100 m is there (at most 4).
  let c = cellOf(lon, lat).get
  let r = reach(c, 0, 100.0)
  for dx in -min(r.dx, 4) .. min(r.dx, 4):
    for dy in -min(r.dy, 4) .. min(r.dy, 4):
      let n = shifted(c, dx, dy)
      if n.isSome:
        result.add int64(n.get)
  result.sort

proc stored(s: Session, sector: int64, which: int): seq[int64] =
  s.db.query(
    int64,
    "select cell from sector_gate_cell where sector_id = :s and which = :w order by cell",
    s = sector,
    w = which,
  )

suite "climbs: the cells round the gates":
  test "a climb that is made has the cells round its two ends, as many either way as 100 m is":
    let s = fresh("made")
    defer:
      s.close()
    # Santiago, and then where a cell is narrower: the block is wider there (the class of bug: a fixed block)
    for (lon, lat) in [(-70.60, -33.40), (-1.6, 54.1), (24.9, 60.2), (18.9, 69.6)]:
      let id = s.addSector(lon, lat, lon + 0.01, lat + 0.005)
      check stored(s, id, 0) == expected(lon, lat)
      check stored(s, id, 1) == expected(lon + 0.01, lat + 0.005)
    check expected(-70.60, -33.40).len == 15 # (5 by 3 at Santiago)
    check expected(18.9, 69.6).len > expected(-70.60, -33.40).len
  test "a climb with no route has none, and the cells go with the climb":
    let s = fresh("none")
    defer:
      s.close()
    s.db.execute("insert into sector(length_m, gain_m, gradient) values (1000, 100, 8)")
    check s.db.scalar(int, "select count(*) from sector_gate_cell") == 0
    let id = s.addSector(-70.60, -33.40, -70.59, -33.39)
    check s.db.scalar(int, "select count(*) from sector_gate_cell") == 30
    s.db.execute("delete from sector where id = :id", id = id)
    check s.db.scalar(int, "select count(*) from sector_gate_cell") == 0

suite "climbs: the sectors a ride may have gone over":
  test "a ride that visits the cells round the start and then those round the finish":
    let s = fresh("through")
    defer:
      s.close()
    let sector = s.addSector(-70.600, -33.400, -70.590, -33.390)
    let up = s.addActivity("up")
    s.visit(up, -70.6002, -33.4001, 100) # near the start
    s.visit(up, -70.5900, -33.3900, 200) # near the finish, later
    let down = s.addActivity("down")
    s.visit(down, -70.5900, -33.3900, 100) # the finish first
    s.visit(down, -70.6002, -33.4001, 200) # then the start: the other way
    let startOnly = s.addActivity("startOnly")
    s.visit(startOnly, -70.600, -33.400, 100)
    let elsewhere = s.addActivity("elsewhere")
    s.visit(elsewhere, -70.700, -33.500, 100)
    s.visit(elsewhere, -70.690, -33.490, 200)
    check s.db.query(int64, sectorsThroughSql, ride = up) == @[sector]
    check s.db.query(int64, sectorsThroughSql, ride = down).len == 0
    check s.db.query(int64, sectorsThroughSql, ride = startOnly).len == 0
    check s.db.query(int64, sectorsThroughSql, ride = elsewhere).len == 0
  test "the rides over a sector are the ones already looked at that may have gone over it":
    let s = fresh("rides")
    defer:
      s.close()
    let sector = s.addSector(-70.600, -33.400, -70.590, -33.390)
    let a = s.addActivity("a")
    s.visit(a, -70.600, -33.400, 100)
    s.visit(a, -70.590, -33.390, 200)
    let b = s.addActivity("b")
    s.visit(b, -70.600, -33.400, 100)
    s.visit(b, -70.590, -33.390, 200)
    s.db.execute("insert into climbs_done(activity_id, version) values (:a, 4)", a = a)
    check s.db.query(int64, ridesThroughSql, sector = sector) ==
      @[a] # (b has not been looked at)
  test "a pass across a gap in the samples, the gate crossed between two samples 90 m apart, is found":
    # (a sample within half the gap of the crossing is in the block: the margin of 100 m allows gaps up to 150 m)
    let s = fresh("gap")
    defer:
      s.close()
    let sector = s.addSector(-70.600, -33.400, -70.590, -33.390)
    let a = s.addActivity("a")
    s.visit(a, -70.6008, -33.4000, 100) # 68 m west of the start
    s.visit(a, -70.5992, -33.4000, 110) # 68 m east of it: the crossing is between
    s.visit(a, -70.590, -33.390, 200)
    check s.db.query(int64, sectorsThroughSql, ride = a) == @[sector]
