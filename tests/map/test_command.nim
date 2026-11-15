import ../support/arrays
import nimchoo/packages/importer/coord
import nimchoo/packages/fit/time
import nimchoo/packages/db/statement
import ../support/env
import std/[json, os, sequtils, strutils, times, unittest]
import nimchoo/core/globals
import nimchoo/packages/user/session
import nimchoo/packages/map/command as mapCommand
import nimchoo/packages/cache/cache
from nimchoo/registry import allFragments, allAccess, newAllAccess

let dir = getTempDir() / "nch-test-map"

proc wkt(points: int, lon0, lat0: float): string =
  ## A straight line of many points (so simplifying has something to remove).
  var pts: seq[string]
  for i in 0 ..< points:
    pts.add formatFloat(lon0 + i.float * 0.0001, ffDecimal, 7) & " " &
      formatFloat(lat0, ffDecimal, 7)
  "MULTILINESTRING((" & pts.join(", ") & "))"

proc world(name: string): tuple[db, cache: string] =
  ## Two activities with routes (60 points each) and one without; all selected.
  removeDir(dir / name)
  result = (dir / name / "x.db", dir / name / "cache" / "user") # (where the files go)
  putEnv("NCH_CACHE", dir / name / "cache")
  let s = openSession(result.db, allFragments, access = allAccess)
  defer:
    s.close()
  for (tag, t, route) in [
    ("a", 1000, wkt(60, -9.14, 38.72)),
    ("b", 2000, wkt(60, 2.35, 48.85)),
    ("c", 3000, ""),
  ]:
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, 0)",
      userId = s.userId,
      name = tag,
      sha256 = tag,
    )
    let f = s.db.scalar(int64, "select max(id) from file")
    s.db.execute(
      "insert into activity(file_id, session, start_t, end_t, sport) values (:fileId, 0, :startT, :endT, 'cycling')",
      fileId = f,
      startT = t,
      endT = t + 10,
    )
    let a = s.db.scalar(int64, "select max(id) from activity")
    if route.len > 0:
      s.db.execute(
        "insert into route(activity_id, geom) values (:activityId, GeomFromText(:wkt, 4326))",
        activityId = a,
        wkt = route,
      )
    s.db.execute(
      "insert into selection(user_id, activity_id) values (:userId, :activityId)",
      userId = s.userId,
      activityId = a,
    )

proc map(db: string, args: varargs[string]): int =
  ## `nch map ARGS --file` (without `--file` the command would serve the page until stopped).
  mapCommand.run(
    Globals(dbPath: db, fragments: allFragments, access: allAccess), @args & @["--file"]
  )

proc mapRaw(db: string, args: varargs[string]): int =
  ## `nch map ARGS` as given.
  mapCommand.run(Globals(dbPath: db, fragments: allFragments, access: allAccess), @args)

proc files(cache: string): seq[string] =
  if dirExists(cache):
    for f in walkFiles(cache / "*"):
      result.add f.extractFilename

proc geojsons(cache: string): seq[string] =
  for f in files(cache):
    if f.endsWith(".geojson"):
      result.add f

proc withClimb(db: string) =
  ## A climb ridden by activity 1.
  let s = openSession(db, allFragments, access = allAccess)
  defer:
    s.close()
  s.db.execute(
    """insert into sector(length_m, gain_m, gradient, category, name, route)
    values (1000, 90, 9, '4', 'Cerro', GeomFromText('LINESTRING Z(-9.14 38.72 10, -9.13 38.72 100)', 4326))"""
  )
  s.db.execute(
    """insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m)
    values (1, 1, 1, 61, 60, 0)"""
  )

proc withRideAlongClimb(db: string) =
  ## The positions of ride 1 over the climb (a point a second for the 60 s of its effort, along the climb's line).
  let s = openSession(db, allFragments, access = allAccess)
  defer:
    s.close()
  var coords: seq[Coord]
  for t in 0 .. 62:
    coords.add Coord(t: UnixTime(t), lon: -9.14 + 0.01 * float(t) / 61.0, lat: 38.72)
  s.db.putTrack(1, coords)

proc withCells(db: string) =
  ## Where the two rides went: ride 1 two cells, one of them twice, ride 2 one cell.
  let s = openSession(db, allFragments, access = allAccess)
  defer:
    s.close()
  s.db.execute(
    """insert into route_cell(activity_id, cell, t_in, t_out) values
      (1, cell(-9.14, 38.72), 1000, 1002), (1, cell(-9.13, 38.72), 1003, 1005),
      (1, cell(-9.14, 38.72), 1006, 1008), (2, cell(2.35, 48.85), 2000, 2004)"""
  )

proc kinds(j: JsonNode): seq[string] =
  for f in j["features"]:
    result.add f["properties"]["kind"].getStr

suite "map: the command":
  test "writes a GeoJSON file named by the layers, with a feature for each route":
    let w = world("basic")
    check map(w.db) == exitOk
    check files(w.cache) == @["map-routes-climbs.geojson"]
    check isCacheFileName("map-routes-climbs.geojson")
    let j = parseFile(w.cache / "map-routes-climbs.geojson")
    check j["features"].len == 2 # (the third has no route)
    check j["features"][0]["properties"]["start"].getStr == "1970-01-01T00:16:40Z"
    check kinds(j) == @["route", "route"]

  test "the climbs the selected activities went up are in the file, after the routes":
    let w = world("climbs")
    withClimb(w.db)
    check map(w.db) == exitOk
    let j = parseFile(w.cache / geojsons(w.cache)[0])
    check kinds(j) == @["route", "route", "climb"]
    let c = j["features"][2]["properties"]
    check c["name"].getStr == "Cerro" and c["category"].getStr == "4" and
      c["gain_m"].getInt == 90

  test "a map is a live view: every request is made again from the data as they are":
    # (the class of bug: a file kept after something it is made from changed)
    let w = world("live")
    withClimb(w.db)
    check map(w.db) == exitOk
    let path = w.cache / "map-routes-climbs.geojson"
    setLastModificationTime(path, fromUnix(1_000_000_000))
    check map(w.db) == exitOk
    check getLastModificationTime(path).toUnix != 1_000_000_000
    check files(w.cache).len == 1 # (one name for the layers, whatever the data)
    for (sql, expected) in [
      ("update sector set name = 'Renamed'", "Renamed"), # the name of a climb
      ("update sector set category = 'HC'", "HC"), # its category
    ]:
      let s = openSession(w.db, allFragments, access = allAccess)
      s.db.execute(sql)
      s.close()
      check map(w.db) == exitOk
      check expected in readFile(path)
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("update sector set retired = 1")
    s.db.execute(
      "update route set geom = GeomFromText('MULTILINESTRING((-9.14 38.72, -9.13 38.72))', 4326) where activity_id = 1"
    )
    s.close()
    check map(w.db) == exitOk
    check kinds(parseFile(path)) == @["route", "route"] # (no climb now)
    check parseFile(path)["features"][0]["geometry"]["coordinates"][0].len == 2

  test "the map follows the selection, not the activities it was made for":
    let w = world("follows")
    check map(w.db) == exitOk
    let path = w.cache / "map-routes-climbs.geojson"
    check parseFile(path)["features"].len == 2
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("delete from selection where activity_id = 1")
    s.close()
    check map(w.db) == exitOk
    check parseFile(path)["features"].len == 1
    check files(w.cache).len == 1

  test "only the user's own selection is drawn":
    let w = world("others")
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
    check map(w.db) == exitOk
    check parseFile(w.cache / geojsons(w.cache)[0])["features"].len == 2
      # (the default user's two; bob's is not drawn)
    check mapCommand.run(
      Globals(dbPath: w.db, user: "bob", fragments: allFragments, access: allAccess),
      @["--file"],
    ) == exitOk
    check parseFile(w.cache / geojsons(w.cache)[0])["features"].len == 1

  test "--worker makes the page too, and both are made again":
    let w = world("worker")
    check map(w.db, "--worker") == exitUsage # (the helper adds --file: not together)
    check mapRaw(w.db, "--worker") == exitOk
    let stem = "map-routes-climbs"
    check files(w.cache) == @[stem & ".geojson", stem & ".html"]
    let page = readFile(w.cache / (stem & ".html"))
    check page.contains("fetch('/files/" & stem & ".geojson')")
    setLastModificationTime(w.cache / (stem & ".geojson"), fromUnix(1_000_000_000))
    writeFile(w.cache / (stem & ".html"), "old page")
    check mapRaw(w.db, "--worker") == exitOk
    check getLastModificationTime(w.cache / (stem & ".geojson")).toUnix != 1_000_000_000
    check readFile(w.cache / (stem & ".html")).startsWith("<!DOCTYPE html>")

  test "with --file there is no page":
    let w = world("nopage")
    check map(w.db) == exitOk
    check files(w.cache).len == 1 and files(w.cache)[0].endsWith(".geojson")

  test "an empty selection, or none with a route, is an error and writes nothing (also before serving)":
    let w = world("empty")
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("delete from selection")
    s.close()
    check map(w.db) == exitFailure
    check mapRaw(w.db, "--worker") == exitFailure
    check mapRaw(w.db) == exitFailure # (serving: refused at once, nothing is served)
    let s2 = openSession(w.db, allFragments, access = allAccess)
    s2.db.execute(
      "insert into selection(user_id, activity_id) values (:userId, 3)",
      userId = s2.userId,
    )
    s2.close()
    check map(w.db) == exitFailure # (activity 3 has no route)
    check files(w.cache).len == 0

  test "bad options are a usage error; the pinning options are gone":
    let w = world("usage")
    check map(w.db, "--style", "lines") == exitUsage
    check map(w.db, "--selection", "AB") == exitUsage
    check map(w.db, "--state", "ab12cd") == exitUsage
    check mapRaw(w.db, "--web") == exitUsage # (serving is the default now)
    check mapRaw(w.db, "--file", "--worker") == exitUsage
    check mapRaw(w.db, "--file", "--port", "0") == exitUsage # (a serving option)
    check map(w.db, "--layers", "nope") == exitUsage
    check mapRaw(w.db, "--help") == exitOk
    check files(w.cache).len == 0

  test "a cache directory that cannot be made is an error":
    let w = world("blocked")
    writeFile(dir / "blocked" / "file", "")
    putEnv("NCH_CACHE", dir / "blocked" / "file" / "cache")
    check map(w.db) == exitFailure
    useTestCache()

suite "map: layers":
  test "heat alone: only cells, at each level, and the climbs are not even worked out":
    let w = world("heat")
    withCells(w.db)
    check map(w.db, "--layers", "heat") == exitOk
    let j = parseFile(w.cache / geojsons(w.cache)[0])
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
    let w = world("rides")
    withCells(w.db)
    check map(w.db, "--layers", "heat") == exitOk
    let j = parseFile(w.cache / geojsons(w.cache)[0])
    var lisbon = 0
    for f in j["features"]:
      let p = f["properties"]
      if p["level"].getInt == 0 and p["visits"].getInt == 2:
        lisbon = p["rides"].getInt # (ride 1 went through that cell twice)
    check lisbon == 1
  test "the layers are chosen: routes alone has no climbs, with heat it has the cells too":
    let w = world("choose")
    withClimb(w.db)
    withCells(w.db)
    check map(w.db, "--layers", "routes") == exitOk
    check "climb" notin kinds(parseFile(w.cache / geojsons(w.cache)[0]))
    check map(w.db, "--layers", "routes", "climbs", "heat") == exitOk
    check geojsons(w.cache).len == 2 # (other layers: another file)
    var all: seq[string]
    for g in geojsons(w.cache):
      let ks = kinds(parseFile(w.cache / g))
      if "heat" in ks:
        all = ks
    check "route" in all and "climb" in all and "heat" in all
    check all.find("heat") < all.find("route") # (the heat is under the routes)
  test "the default is routes and climbs, and says the same as asking for them":
    let w = world("default")
    check map(w.db) == exitOk
    check map(w.db, "--layers", "climbs", "routes") == exitOk
    check geojsons(w.cache).len == 1
  test "a heat map of activities that went through no cell is an error, and writes nothing":
    let w = world("nocells")
    check map(w.db, "--layers", "heat") == exitFailure
    check geojsons(w.cache).len == 0
  test "a route in several parts (a ride with pauses) can be drawn":
    let w = world("parts")
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute(
      "update route set geom = GeomFromText('MULTILINESTRING((-9.14 38.72, -9.13 38.72), (-9.12 38.72, -9.11 38.72))', 4326) where activity_id = 1"
    )
    s.close()
    check map(w.db) == exitOk
    check parseFile(w.cache / geojsons(w.cache)[0])["features"].len == 2

suite "map: gates and efforts":
  test "the efforts layer draws the part of the ride between the stored start and finish; the gates layer, two lines a climb":
    let w = world("efforts")
    withClimb(w.db)
    withRideAlongClimb(w.db)
    check map(w.db, "--layers", "efforts", "gates") == exitOk
    let j = parseFile(w.cache / geojsons(w.cache)[0])
    check kinds(j) == @["effort", "gate", "gate"]
    let e = j["features"][0]
    check e["properties"]["name"].getStr == "Cerro" and
      e["properties"]["activity"].getInt == 1
    check e["properties"]["elapsed_s"].getFloat == 60.0
    check e["geometry"]["coordinates"].len == 61
      # (t from 1 to 61: the times of the effort)
    check j["features"][1]["properties"]["end"].getStr == "start"
    check j["features"][2]["properties"]["end"].getStr == "finish"
  test "the efforts and the gates follow the climbs and the efforts as they are":
    let w = world("effortsfollow")
    withClimb(w.db)
    withRideAlongClimb(w.db)
    check map(w.db, "--layers", "efforts", "gates") == exitOk
    let path = w.cache / geojsons(w.cache)[0]
    check parseFile(path)["features"][0]["properties"]["elapsed_s"].getFloat == 60.0
    let gateBefore = parseFile(path)["features"][1]["geometry"]["coordinates"]
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("update effort set finish_t = 60, elapsed_s = 59")
    s.db.execute(
      "update sector set route = GeomFromText('LINESTRING Z(-9.14 38.72 10, -9.12 38.73 100)', 4326)"
    )
    s.close()
    check map(w.db, "--layers", "efforts", "gates") == exitOk
    let j = parseFile(path)
    check j["features"][0]["properties"]["elapsed_s"].getFloat == 59.0
      # (the effort moved)
    check j["features"][1]["geometry"]["coordinates"] != gateBefore
      # (and the gate with the climb)
  test "no efforts, and no climbs: the layers are empty and the file is still valid":
    let w = world("noefforts")
    check map(w.db, "--layers", "routes", "efforts", "gates") == exitOk
    check kinds(parseFile(w.cache / geojsons(w.cache)[0])) == @["route", "route"]
