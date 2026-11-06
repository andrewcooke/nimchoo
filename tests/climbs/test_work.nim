import std/[strutils, unittest]
import db_connector/db_sqlite
import nimchoo/climbs/work
import nimchoo/db/store
import nimchoo/errors
import ../support/[climbdata, userdata]

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

  test "a ride that stops short of a stored climb's finish makes a climb of its own, and the earlier ride is matched to it":
    let s = fresh("short")
    defer: s.close()
    addRide(s, "default", "long", 1_000_000, 5.0, eastbound(5.0))                          # up the whole 3 km
    addRide(s, "default", "short", 2_000_000, 5.0, eastbound(5.0, to0 = 3500.0))           # stops 500 m before the top
    let w = ensureClimbs(s)
    check w.sectors == 2
    check s.count("sector") == 2
    # the long ride earned an effort on both (it crosses the gates of the shorter one), the short ride on its own only
    check s.db.getValue(sql"select count(*) from effort where sector_id = 1") == "1"
    check s.db.getValue(sql"select count(*) from effort where sector_id = 2") == "2"
    check s.db.getValue(sql"select length_m between 2800 and 3200 from sector where id = 1") == "1"      # the whole climb
    check s.db.getValue(sql"select length_m between 2200 and 2700 from sector where id = 2") == "1"      # up to where the short ride stopped
  test "the same short ride again is that climb again, not a third":
    let s = fresh("shortagain")
    defer: s.close()
    addRide(s, "default", "long", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "default", "short", 2_000_000, 5.0, eastbound(5.0, to0 = 3500.0))
    addRide(s, "default", "short2", 3_000_000, 5.0, eastbound(5.0, to0 = 3500.0))
    discard ensureClimbs(s)
    check s.count("sector") == 2
    check s.db.getValue(sql"select count(*) from effort where sector_id = 2") == "3"
  test "a longer ride after a shorter one crosses its gates and makes no sector (the shorter climb is the common part)":
    let s = fresh("longafter")
    defer: s.close()
    addRide(s, "default", "short", 1_000_000, 5.0, eastbound(5.0, to0 = 3500.0))
    addRide(s, "default", "long", 2_000_000, 5.0, eastbound(5.0))
    let w = ensureClimbs(s)
    check w.sectors == 1 and s.count("sector") == 1
    check s.db.getValue(sql"select count(*) from effort where sector_id = 1") == "2"
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

  test "the count says how many names given by hand would be lost":
    let s = fresh("manual")
    defer: s.close()
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    discard ensureClimbs(s)
    check countClimbs(s).manual == 0
    check describe(countClimbs(s)) == "1 sector and 1 effort (of every user)"
    s.db.exec(sql"update sector set name = 'Mine', manual = 1")
    check countClimbs(s) == Counts(sectors: 1, efforts: 1, manual: 1)
    check describe(countClimbs(s)) == "1 sector and 1 effort (of every user); 1 name given by hand is lost"
    check describe(Counts(sectors: 9, efforts: 20, manual: 3)).endsWith("; 3 names given by hand are lost")
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
      check "nch climbs --all --delete" in e.msg
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
    var counts: seq[Worked]
    discard ensureClimbs(s, proc(done, total: int, soFar: Worked) {.closure, raises: [].} =
      seen.add (done, total)
      counts.add soFar)
    check seen == @[(1, 2), (2, 2)]
    check counts[0].activities == 1 and counts[0].sectors == 1       # the counts so far
    check counts[1].activities == 2 and counts[1].efforts == 2
