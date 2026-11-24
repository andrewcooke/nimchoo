## The frames of the climbs on a map, for the activities (climbs/mapframes.nim): the climbs the selected activities went up, their
## gates, and the efforts; each from the data as they are, each declaring the tables it reads.

import std/[json, os, strutils, unittest]
import nimchoo/core/[access, extension, globals]
import nimchoo/packages/db/[access, statement]
import nimchoo/packages/climbs/mapframes
import nimchoo/packages/fit/time
import nimchoo/packages/importer/coord
import nimchoo/packages/map/frames
import nimchoo/packages/user/session
import ../support/mapworld
from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

let dir = getTempDir() / "nch-test-climbs-frames"

proc frameOf(name: string): MapFrame =
  for f in extensions.get(mapFramePoint):
    if f.subject == "activities" and f.name == name:
      return f
  raiseAssert "no such frame: " & name

suite "climbs frames: the climbs":
  test "the climbs the selected activities went up are a frame of their own":
    let w = world(dir, "climbs")
    withClimb(w.db)
    check map(w.db) == exitOk
    check kinds(parseFile(frameFile(w.cache, "routes"))) == @["route", "route"]
    let j = parseFile(frameFile(w.cache, "climbs"))
    check kinds(j) == @["climb"]
    let c = j["features"][0]["properties"]
    check c["name"].getStr == "Cerro" and c["category"].getStr == "4" and
      c["gain_m"].getInt == 90
  test "the climbs follow the data as they are: a rename, a category, a retiring":
    let w = world(dir, "live")
    withClimb(w.db)
    check map(w.db, "--frames", "climbs") == exitOk
    let path = frameFile(w.cache, "climbs")
    for (sql, expected) in [
      ("update sector set name = 'Renamed'", "Renamed"),
      ("update sector set category = 'HC'", "HC"),
    ]:
      let s = openSession(w.db, allFragments, access = allAccess)
      s.db.execute(sql)
      s.close()
      check map(w.db, "--frames", "climbs") == exitOk
      check expected in readFile(path)
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("update sector set retired = 1")
    s.close()
    check map(w.db, "--frames", "climbs") == exitOk
    check kinds(parseFile(path)).len == 0 # (no climb now)
  test "routes alone work out no climbs":
    let w = world(dir, "routesonly")
    withClimb(w.db)
    check map(w.db, "--frames", "routes") == exitOk
    let s = openSession(w.db, allFragments, access = allAccess)
    defer:
      s.close()
    check s.db.scalar(int, "select count(*) from climbs_done") == 0

suite "climbs frames: they only read":
  test "activities with no climbs worked out are a note, and nothing is worked out":
    let w = world(dir, "unworked")
    let s = openSession(w.db, allFragments, access = newAllAccess(amEnforce))
    defer:
      s.close()
    for name in ["climbs", "gates", "efforts"]:
      let made = frameOf(name).make(s)
      check made.warnings ==
        @["3 activities have no climbs worked out (run `nch climbs` to work them out)"]
    check s.db.scalar(int, "select count(*) from climbs_done") == 0
    check s.db.scalar(int, "select count(*) from sector") == 0
  test "no note when the selected activities are worked out":
    let w = world(dir, "worked")
    let s = openSession(w.db, allFragments, access = allAccess)
    defer:
      s.close()
    s.db.execute(
      "insert into climbs_done(activity_id, version) select id, 1 from activity"
    )
    check frameOf("climbs").make(s).warnings.len == 0

suite "climbs frames: gates and efforts":
  test "the efforts frame draws the part of the ride between the stored start and finish; the gates frame, two lines a climb":
    let w = world(dir, "efforts")
    withClimb(w.db)
    withRideAlongClimb(w.db)
    check map(w.db, "--frames", "efforts", "gates") == exitOk
    let eff = parseFile(frameFile(w.cache, "efforts"))
    check kinds(eff) == @["effort"]
    let e = eff["features"][0]
    check e["properties"]["name"].getStr == "Cerro" and
      e["properties"]["activity"].getInt == 1
    check e["properties"]["elapsed"].getStr == "1m00s"
    check e["geometry"]["coordinates"].len == 61
      # (t from 1 to 61: the times of the effort)
    let gates = parseFile(frameFile(w.cache, "gates"))
    check kinds(gates) == @["gate", "gate"]
    check gates["features"][0]["properties"]["end"].getStr == "start"
    check gates["features"][1]["properties"]["end"].getStr == "finish"
  test "the efforts and the gates follow the climbs and the efforts as they are":
    let w = world(dir, "effortsfollow")
    withClimb(w.db)
    withRideAlongClimb(w.db)
    check map(w.db, "--frames", "efforts", "gates") == exitOk
    check parseFile(frameFile(w.cache, "efforts"))["features"][0]["properties"][
      "elapsed"
    ].getStr == "1m00s"
    let gateBefore =
      parseFile(frameFile(w.cache, "gates"))["features"][0]["geometry"]["coordinates"]
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("update effort set finish_epoch = 60, elapsed_s = 59")
    s.db.execute(
      "update sector set route = GeomFromText('LINESTRING Z(-9.14 38.72 10, -9.12 38.73 100)', 4326)"
    )
    s.close()
    check map(w.db, "--frames", "efforts", "gates") == exitOk
    check parseFile(frameFile(w.cache, "efforts"))["features"][0]["properties"][
      "elapsed"
    ].getStr == "59s" # (the effort moved)
    check parseFile(frameFile(w.cache, "gates"))["features"][0]["geometry"][
      "coordinates"
    ] != gateBefore # (and the gate with the climb)
  test "no efforts, and no climbs: the frames are empty and the files are still valid":
    let w = world(dir, "noefforts")
    check map(w.db, "--frames", "routes", "efforts", "gates") == exitOk
    check kinds(parseFile(frameFile(w.cache, "routes"))) == @["route", "route"]
    check kinds(parseFile(frameFile(w.cache, "efforts"))).len == 0
    check kinds(parseFile(frameFile(w.cache, "gates"))).len == 0

suite "climbs frames: each declares the tables it reads":
  test "every table the frame reads is in its declaration":
    for name in ["climbs", "gates", "efforts"]:
      let w = world(dir, "declared" & name)
      withClimb(w.db)
      withRideAlongClimb(w.db)
      let f = frameOf(name)
      let s = openSession(w.db, allFragments, access = newAllAccess(amEnforce))
      defer:
        s.close()
      startRecording()
      discard f.make(s)
      let read = stopRecording()
      check read.len > 0
      for t in read:
        check t in f.tables

suite "climbs frames: the line of an effort":
  proc ride(): seq[Coord] =
    ## A position a second, from t = 10, moving 0.001 degrees east a second.
    for k in 0 .. 5:
      result.add Coord(t: UnixTime(10 + k), lon: 0.001 * float(k), lat: -33.0)

  test "it starts and ends where the gates were crossed, between the positions either side":
    let p = effortPath(ride(), 11.25, 13.5)
    check p.len == 4 # (the start, the positions at 12 and 13, the finish)
    check abs(p[0].lon - 0.00125) < 1e-12 and p[0].lat == -33.0
    check p[1].lon == 0.002 and p[2].lon == 0.003
    check abs(p[3].lon - 0.0035) < 1e-12
  test "a time on a position is that position, once":
    let p = effortPath(ride(), 11.0, 13.0)
    check p.len == 3 and p[0].lon == 0.001 and p[1].lon == 0.002 and p[2].lon == 0.003
  test "a time outside the ride is taken at its first or last position; no positions, no line":
    let p = effortPath(ride(), 5.0, 99.0)
    check p[0].lon == 0.0 and p[^1].lon == 0.005 and p.len == 6 + 2
    check effortPath(@[], 1.0, 2.0).len == 0

suite "climbs frames: the climbs subject":
  proc chooseClimb(db: string) =
    let s = openSession(db, allFragments, access = allAccess)
    defer:
      s.close()
    s.db.execute(
      "insert into climb_selection(user_id, sector_id) select :userId, id from sector",
      userId = s.userId,
    )

  test "an empty climbs selection is said, and nothing is made (no failure)":
    let w = world(dir, "subject-empty")
    withClimb(w.db)
    check map(w.db, "climbs") == exitOk
    check not fileExists(frameFile(w.cache, "climbs", "climbs"))

  test "the climbs of the selection, their gates, and the routes of the rides up them":
    let w = world(dir, "subject")
    withClimb(w.db)
    chooseClimb(w.db)
    check map(w.db, "climbs", "--frames", "climbs", "gates", "routes") == exitOk
    check kinds(parseFile(frameFile(w.cache, "climbs", "climbs"))) == @["climb"]
    check kinds(parseFile(frameFile(w.cache, "gates", "climbs"))).len == 2
    check kinds(parseFile(frameFile(w.cache, "routes", "climbs"))) ==
      @["route"] # (ride 1 went up it; ride 2 did not)

  test "the climbs subject's frames do not read the activities' selection":
    let w = world(dir, "subject-own")
    withClimb(w.db)
    chooseClimb(w.db)
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("delete from activity_selection")
    s.close()
    check map(w.db, "climbs", "--frames", "climbs") == exitOk
    check kinds(parseFile(frameFile(w.cache, "climbs", "climbs"))) == @["climb"]
