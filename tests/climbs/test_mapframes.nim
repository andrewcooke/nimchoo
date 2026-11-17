## The frames of the climbs on a map, for the activities (climbs/mapframes.nim): the climbs the selected activities went up, their
## gates, and the efforts; each from the data as they are, each declaring the tables it reads.

import std/[json, os, strutils, unittest]
import nimchoo/core/[access, extension, globals]
import nimchoo/packages/db/[access, statement]
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
    for (sql, expected) in [
      ("update sector set name = 'Renamed'", "Renamed"),
      ("update sector set category = 'HC'", "HC"),
    ]:
      let s = openSession(w.db, allFragments, access = allAccess)
      s.db.execute(sql)
      s.close()
      forget(w.cache)
      check map(w.db, "--frames", "climbs") == exitOk
      check expected in readFile(frameFile(w.cache, "climbs"))
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("update sector set retired = 1")
    s.close()
    forget(w.cache)
    check map(w.db, "--frames", "climbs") == exitOk
    check kinds(parseFile(frameFile(w.cache, "climbs"))).len == 0 # (no climb now)
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
      check made.notes ==
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
    check frameOf("climbs").make(s).notes.len == 0

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
    check e["properties"]["elapsed_s"].getFloat == 60.0
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
      "elapsed_s"
    ].getFloat == 60.0
    let gateBefore =
      parseFile(frameFile(w.cache, "gates"))["features"][0]["geometry"]["coordinates"]
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("update effort set finish_t = 60, elapsed_s = 59")
    s.db.execute(
      "update sector set route = GeomFromText('LINESTRING Z(-9.14 38.72 10, -9.12 38.73 100)', 4326)"
    )
    s.close()
    forget(w.cache)
    check map(w.db, "--frames", "efforts", "gates") == exitOk
    check parseFile(frameFile(w.cache, "efforts"))["features"][0]["properties"][
      "elapsed_s"
    ].getFloat == 59.0 # (the effort moved)
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
