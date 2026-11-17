## The frames of the activities on a map (activities/mapframes.nim): what each contains, that each is made from the data as they are
## and from the user's own selection, that each declares the tables it reads, and the map end to end with the real registry.

import std/[json, os, sequtils, strutils, times, unittest]
import nimchoo/core/[access, extension]
import nimchoo/packages/activities/mapframes
import nimchoo/packages/db/[access, statement]
import nimchoo/packages/map/frames
import nimchoo/packages/user/session
import nimchoo/packages/map/command as mapCommand
import nimchoo/core/globals
import ../support/mapworld
from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

let dir = getTempDir() / "nch-test-activities-frames"

proc frameOf(name: string): MapFrame =
  for f in extensions.get(mapFramePoint):
    if f.subject == "activities" and f.name == name:
      return f
  raiseAssert "no such frame: " & name

suite "activities frames: the routes":
  test "a feature for each route, oldest first, in a file named for the subject and the frame":
    let w = world(dir, "routes")
    check map(w.db, "--frames", "routes") == exitOk
    check files(w.cache) == @["map-activities-routes.geojson"]
    let j = parseFile(frameFile(w.cache, "routes"))
    check j["features"].len == 2 # (the third has no route)
    check j["features"][0]["properties"]["start"].getStr == "1970-01-01T00:16:40Z"
    check kinds(j) == @["route", "route"]
  test "a route in several parts (a ride with pauses) can be drawn":
    let w = world(dir, "parts")
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute(
      "update route set geom = GeomFromText('MULTILINESTRING((-9.14 38.72, -9.13 38.72), (-9.12 38.72, -9.11 38.72))', 4326) where activity_id = 1"
    )
    s.close()
    check map(w.db, "--frames", "routes") == exitOk
    check parseFile(frameFile(w.cache, "routes"))["features"].len == 2
  test "none with a route is a note and an empty frame, not a failure":
    let w = world(dir, "noroute")
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("delete from selection")
    s.db.execute(
      "insert into selection(user_id, activity_id) values (:userId, 3)",
      userId = s.userId,
    )
    s.close()
    check map(w.db, "--frames", "routes") == exitOk # (activity 3 has no route)
    check kinds(parseFile(frameFile(w.cache, "routes"))).len == 0
    let s2 = openSession(w.db, allFragments, access = newAllAccess(amEnforce))
    defer:
      s2.close()
    check frameOf("routes").make(s2).notes ==
      @["none of the 1 activities has a route (no positions in the files)"]
  test "only the user's own selection is drawn":
    let w = world(dir, "others")
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("insert into user(name, is_default) values ('bob', 0)")
    let bob = s.db.scalar(int64, "select id from user where name = 'bob'")
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, 'bobs', 'bobs', 0)",
      userId = bob,
    )
    s.db.execute(
      "insert into activity(file_id, session, start_t, end_t) select max(id), 0, 5000, 5010 from file"
    )
    s.db.execute(
      "insert into route(activity_id, geom) select max(id), GeomFromText('MULTILINESTRING((0 0, 1 1))', 4326) from activity"
    )
    s.db.execute(
      "insert into selection(user_id, activity_id) select :userId, max(id) from activity",
      userId = bob,
    )
    s.close()
    check map(w.db, "--frames", "routes") == exitOk
    check parseFile(frameFile(w.cache, "routes"))["features"].len == 2
    check mapCommand.run(globalsOf(w.db, "bob"), @["--frames", "routes", "--file"]) ==
      exitOk
    check parseFile(frameFile(w.cache, "routes"))["features"].len == 1

suite "activities frames: the heat":
  test "cells, at each level, and the climbs are not even worked out":
    let w = world(dir, "heat")
    withCells(w.db)
    check map(w.db, "--frames", "heat") == exitOk
    let j = parseFile(frameFile(w.cache, "heat"))
    check kinds(j) == newSeq[string](j["features"].len).mapIt("heat")
    var perLevel: array[3, tuple[cells, visits: int]]
    for f in j["features"]:
      let p = f["properties"]
      let k = heatLevels.find(p["level"].getInt)
      check k >= 0
      inc perLevel[k].cells
      perLevel[k].visits += p["visits"].getInt
    check perLevel[0] == (3, 4)
      # (every visit is in the finest level, three different cells)
    check perLevel[1].visits == 4 and perLevel[2].visits == 4 # (and in the coarser ones)
    check perLevel[1].cells <= 3 and perLevel[2].cells <= perLevel[1].cells
    let s = openSession(w.db, allFragments, access = allAccess)
    check s.db.scalar(int, "select count(*) from climbs_done") == 0
    s.close()
  test "a cell says how many different activities visited it":
    let w = world(dir, "rides")
    withCells(w.db)
    check map(w.db, "--frames", "heat") == exitOk
    let j = parseFile(frameFile(w.cache, "heat"))
    var lisbon = 0
    for f in j["features"]:
      let p = f["properties"]
      if p["level"].getInt == 0 and p["visits"].getInt == 2:
        lisbon = p["rides"].getInt # (ride 1 went through that cell twice)
    check lisbon == 1
  test "activities that went through no cell are an empty frame, and the other frames are still drawn":
    let w = world(dir, "nocells")
    check map(w.db, "--frames", "heat", "routes") == exitOk
    check kinds(parseFile(frameFile(w.cache, "heat"))).len == 0
    check kinds(parseFile(frameFile(w.cache, "routes"))).len == 2

suite "activities frames: the map, with the real registry":
  test "by default the routes and the climbs, a file each":
    let w = world(dir, "default")
    check map(w.db) == exitOk
    check files(w.cache) ==
      @["map-activities-climbs.geojson", "map-activities-routes.geojson"]
  test "frames are chosen, in any order, once each; a file for each":
    let w = world(dir, "choose")
    withCells(w.db)
    check map(w.db, "--frames", "heat", "routes", "heat") == exitOk
    check files(w.cache) ==
      @["map-activities-heat.geojson", "map-activities-routes.geojson"]
    check "climb" notin kinds(parseFile(frameFile(w.cache, "routes")))
  test "a map is a live view: every request is made again from the data as they are":
    let w = world(dir, "live")
    check map(w.db, "--frames", "routes") == exitOk
    let path = frameFile(w.cache, "routes")
    setLastModificationTime(path, fromUnix(1_000_000_000))
    check map(w.db, "--frames", "routes") == exitOk
    check getLastModificationTime(path).toUnix != 1_000_000_000
    check files(w.cache).len == 1 # (one name for the frame, whatever the data)
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute(
      "update route set geom = GeomFromText('MULTILINESTRING((-9.14 38.72, -9.13 38.72))', 4326) where activity_id = 1"
    )
    s.db.execute("delete from selection where activity_id = 2")
    s.close()
    check map(w.db, "--frames", "routes") == exitOk
    let j = parseFile(path)
    check j["features"].len == 1
    check j["features"][0]["geometry"]["coordinates"][0].len == 2
  test "--worker makes the page too, which names the files of the frames and carries their styles":
    let w = world(dir, "worker")
    check mapRaw(w.db, "--worker") == exitOk
    check files(w.cache) ==
      @[
        "map-activities-climbs.geojson", "map-activities-routes-climbs.html",
        "map-activities-routes.geojson",
      ]
    let page = readFile(w.cache / "map-activities-routes-climbs.html")
    check page.contains("\"map-activities-routes.geojson\"") and
      page.contains("\"map-activities-climbs.geojson\"")
    check page.contains(
      "\"name\":\"activities/routes\",\"file\":\"map-activities-routes.geojson\",\"style\":{\"color\":\"#e03131\""
    ) # the style of the routes, in the page
    check page.contains("\"gap_m\":15") # and of the climbs
    check page.contains("drawers[\"activities-map-routes\"] = (") and
      page.contains("drawers[\"activities-map-climbs\"] = (") # and their drawings

suite "activities frames: each declares the tables it reads":
  test "every table the frame reads is in its declaration":
    for name in ["routes", "heat"]:
      let w = world(dir, "declared" & name)
      withCells(w.db)
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
