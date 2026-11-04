import std/[math, os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/climbs/work
import nimchoo/db/store
import nimchoo/errors
import nimchoo/modules
import ../support/userdata

const metre = 360.0 / (2.0 * PI * 6_371_008.8)      # degrees of longitude per metre at the equator

let dir = getTempDir() / "nch-test-climbs-work"

func altitude(x: float): float =
  ## The road: 1 km flat, 3 km up at 4 % (120 m), then flat.
  if x < 1000.0: 100.0
  elif x < 4000.0: 100.0 + (x - 1000.0) * 0.04
  else: 220.0

proc fresh(name: string): Store =
  removeDir(dir / name)
  openStore(dir / name / "x.db", allFragments)

proc addRide(s: Store, user: string, tag: string, startT: int, speed: float, xs: seq[float],
             withAltitude = true, northM = 0.0) =
  ## A ride along the road: the places it passes in turn (metres east), a point a second.
  let u = s.db.getValue(sql"select id from user where name = ?", user)
  s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)", u, tag, tag)
  let f = s.db.getValue(sql"select max(id) from file")
  s.db.exec(sql"insert into activity(file_id, session, start_t, end_t) values (?, 0, ?, ?)",
            f, startT, startT + 10000)
  let a = s.db.getValue(sql"select max(id) from activity")
  var wkt: seq[string]
  var t = startT
  for x in xs:
    let alt = if withAltitude: $altitude(x) else: ""
    s.db.exec(sql"insert into coords(activity_id, t, lon, lat, alt) values (?, ?, ?, ?, nullif(?, ''))",
              a, t, x * metre, northM * metre, alt)
    wkt.add formatFloat(x * metre, ffDecimal, 9) & " " & formatFloat(northM * metre, ffDecimal, 9)
    inc t
  s.db.exec(sql"insert into route(activity_id, geom) values (?, GeomFromText(?, 4326))",
            a, "MULTILINESTRING((" & wkt.join(", ") & "))")

func eastbound(speed: float, from0 = -500.0, to0 = 6500.0): seq[float] =
  var x = from0
  while x <= to0:
    result.add x
    x += speed

suite "climbs: working them out":
  test "a ride with a climb makes a sector and an effort; asking again does nothing":
    let s = fresh("first")
    defer: s.close()
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    let w = ensureClimbs(s)
    check w == Worked(activities: 1, sectors: 1, efforts: 1)
    check s.count("sector") == 1 and s.count("effort") == 1 and s.count("climbs_done") == 1
    check s.db.getValue(sql"select category from sector") == "4"
    check abs(parseFloat(s.db.getValue(sql"select gain_m from sector")) - 118.0) < 3.0
    check abs(parseFloat(s.db.getValue(sql"select gradient from sector")) - 4.0) < 0.2
    check s.db.getValue(sql"select found_at from sector") == "1000000"
    check abs(parseFloat(s.db.getValue(sql"select elapsed_s from effort")) - 592.0) < 3.0
    check abs(parseFloat(s.db.getValue(sql"select start_m from effort")) - 1520.0) < 15.0      # (the ride starts 500 m before the road does)
    check ensureClimbs(s) == Worked()

  test "another ride, by another user, is a pass over the same sector, not a new one":
    let s = fresh("second")
    defer: s.close()
    addUser(s.path, "bob")
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "bob", "two", 2_000_000, 4.0, eastbound(4.0))
    let w = ensureClimbs(s)
    check w == Worked(activities: 2, sectors: 1, efforts: 2)
    check s.count("sector") == 1
    let fast = parseFloat(s.db.getValue(sql"select elapsed_s from effort order by start_t limit 1"))
    let slow = parseFloat(s.db.getValue(sql"select elapsed_s from effort order by start_t desc limit 1"))
    check abs(slow / fast - 1.25) < 0.02                       # 4 m/s against 5 m/s
    # ... and they are ranked by the time
    check s.db.getValue(sql"select e.activity_id from effort e order by e.elapsed_s limit 1") ==
          s.db.getValue(sql"select id from activity where start_t = 1000000")

  test "a ride with no altitude has efforts on known climbs, and a ride before the climb was found too":
    let s = fresh("noalt")
    defer: s.close()
    addRide(s, "default", "early", 500_000, 5.0, eastbound(5.0), withAltitude = false)   # no altitude: no climbs of its own
    addRide(s, "default", "later", 1_000_000, 5.0, eastbound(5.0))
    let w = ensureClimbs(s)
    check w.sectors == 1 and w.efforts == 2                    # the earlier ride is matched when the sector is found
    check s.db.getValue(sql"select count(distinct activity_id) from effort") == "2"
    # a ride with no altitude that comes later is matched against what exists
    addRide(s, "default", "third", 3_000_000, 5.0, eastbound(5.0), withAltitude = false)
    check ensureClimbs(s) == Worked(activities: 1, sectors: 0, efforts: 1)

  test "a ride that is older than those already looked at is dealt with in its turn":
    let s = fresh("older")
    defer: s.close()
    addRide(s, "default", "later", 2_000_000, 5.0, eastbound(5.0))
    discard ensureClimbs(s)
    addRide(s, "default", "older", 1_000_000, 4.0, eastbound(4.0))     # imported afterwards, started before
    let w = ensureClimbs(s)
    check w == Worked(activities: 1, sectors: 0, efforts: 1)          # the sector stays as it was found
    check s.db.getValue(sql"select found_at from sector") == "2000000"
    check s.count("effort") == 2

  test "laps over a climb are separate efforts":
    let s = fresh("laps")
    defer: s.close()
    let xs = eastbound(5.0)
    var back: seq[float]
    var x = 6500.0
    while x >= -500.0:
      back.add x
      x -= 5.0
    let lap = xs & back & xs
    addRide(s, "default", "laps", 1_000_000, 5.0, lap)
    let w = ensureClimbs(s)
    check w.sectors == 1 and w.efforts == 2                   # up, down (no climb), up again
    check s.db.getValue(sql"select count(*) from effort where elapsed_s between 580 and 600") == "2"

  test "rides elsewhere have nothing to do with it":
    let s = fresh("elsewhere")
    defer: s.close()
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "default", "north", 2_000_000, 5.0, eastbound(5.0), northM = 5000.0)
    let w = ensureClimbs(s)
    check w.activities == 2 and w.sectors == 2                # the other road has its own climb
    check s.count("effort") == 2 and s.db.getValue(sql"select count(distinct sector_id) from effort") == "2"

  test "activities with nothing to look at are recorded, and not looked at again":
    let s = fresh("empty")
    defer: s.close()
    fill(s, "fill")                                           # one coordinate: no ride
    addRide(s, "default", "flat", 1_000_000, 5.0, @[0.0, 5.0])
    check ensureClimbs(s) == Worked(activities: 2, sectors: 0, efforts: 0)
    check s.count("climbs_done") == 2
    check ensureClimbs(s) == Worked()

  test "a change of the method is noticed; clearing starts again":
    let s = fresh("version")
    defer: s.close()
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    discard ensureClimbs(s)
    s.db.exec(sql"update climbs_done set version = 0")
    try:
      discard ensureClimbs(s)
      check false
    except StoreError as e:
      check "nch empty --sectors" in e.msg
    check countClimbs(s) == Counts(sectors: 1, efforts: 1)
    clearClimbs(s)
    check countClimbs(s) == Counts()
    check s.count("climbs_done") == 0 and s.count("activity") == 1      # the rides stay
    check ensureClimbs(s) == Worked(activities: 1, sectors: 1, efforts: 1)

  test "progress is reported":
    let s = fresh("progress")
    defer: s.close()
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "default", "two", 2_000_000, 5.0, eastbound(5.0))
    var seen: seq[(int, int)]
    discard ensureClimbs(s, proc(done, total: int) {.closure, raises: [].} = seen.add (done, total))
    check seen == @[(1, 2), (2, 2)]
