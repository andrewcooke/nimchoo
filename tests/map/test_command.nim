import ../support/arrays
import nimchoo/packages/importer/coord
import nimchoo/packages/fit/time
import nimchoo/packages/db/statement
import ../support/env
import std/[json, options, os, sequtils, strutils, times, unittest]
import nimchoo/core/globals
import nimchoo/packages/user/session
import nimchoo/packages/map/command as mapCommand
import nimchoo/packages/cache/cache
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/selection/bits
import nimchoo/packages/selection/selection
import nimchoo/packages/map/params

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
  mapCommand.run(Globals(dbPath: db, fragments: allFragments, access: allAccess), @args)

proc files(cache: string): seq[string] =
  if dirExists(cache):
    for f in walkFiles(cache / "*"):
      result.add f.extractFilename

proc geojsons(cache: string): seq[string] =
  for f in files(cache):
    if f.endsWith(".geojson"):
      result.add f

proc addressOf(db: string): tuple[selection, state: string] =
  ## What the address of the map of the current selection carries.
  let s = openSession(db, allFragments, access = allAccess)
  defer:
    s.close()
  let ids = selectedIds(s)
  (encodeBits(ids), stateOf(s, ownedIds(s, ids)))

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
  test "writes a GeoJSON file named by a hash of the request, with a feature for each route":
    let w = world("basic")
    check map(w.db) == exitOk
    let a = addressOf(w.db)
    let name =
      requestStem(
        "map", "selection=" & a.selection & "&layers=routes,climbs&state=" & a.state
      ).get & ".geojson"
    check files(w.cache) == @[name]
    check name.startsWith("map-") and isCacheFileName(name)
    let j = parseFile(w.cache / name)
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

  test "a second request does no work":
    let w = world("again")
    check map(w.db) == exitOk
    let path = w.cache / files(w.cache)[0]
    setLastModificationTime(path, fromUnix(1_000_000_000))
    check map(w.db) == exitOk
    check getLastModificationTime(path).toUnix == 1_000_000_000
    check files(w.cache).len == 1

  test "every input of the map is part of its state: a change of any of them is another state":
    # (the class of bug: a cached file kept after something it is made from changed)
    let w = world("inputs")
    withClimb(w.db)
    check map(w.db) == exitOk
    var seen = @[addressOf(w.db).state]
    for sql in [
      "update sector set name = 'Renamed'", # the name of a climb
      "update sector set category = 'HC'", # its category
      "update sector set retired = 1", # its retiring
      "update route set geom = GeomFromText('MULTILINESTRING((-9.14 38.72, -9.13 38.72))', 4326) where activity_id = 1",
    ]:
      let s = openSession(w.db, allFragments, access = allAccess)
      s.db.execute(sql)
      s.close()
      let state = addressOf(w.db).state
      check state notin seen
      seen.add state
    check map(w.db) == exitOk
    check files(w.cache).len == 2 # (the first map is still there: it is the old plot)

  test "the content of an activity changes the request: a file of its own":
    let w = world("content")
    check map(w.db) == exitOk
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("update file set sha256 = 'z' where name = 'a'")
    s.close()
    check map(w.db) == exitOk
    check files(w.cache).len == 2

  test "nothing changed: the file is left alone (also across other changes the map does not read)":
    let w = world("unchanged")
    withClimb(w.db)
    check map(w.db) == exitOk
    let path = w.cache / files(w.cache)[0]
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("insert into user(name, is_default) values ('bob', 0)")
    s.close()
    setLastModificationTime(path, fromUnix(1_000_000_000))
    check map(w.db) == exitOk
    check getLastModificationTime(path).toUnix == 1_000_000_000

  test "an address made for a selection still draws it after the selection changes":
    let w = world("pinned")
    check map(w.db) == exitOk
    let old = addressOf(w.db)
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("delete from selection where activity_id = 1")
    s.close()
    check addressOf(w.db) != old
    check map(w.db, "--selection", old.selection, "--state", old.state) == exitOk
      # the file is there, the old activities
    check files(w.cache).len == 1
    check map(w.db) == exitOk # the new selection: a file of its own
    check files(w.cache).len == 2

  test "an address whose activities have changed is refused: a wrong state, or activities deleted":
    let w = world("changed")
    check map(w.db) == exitOk
    let a = addressOf(w.db)
    check map(w.db, "--selection", a.selection, "--state", "000000") == exitFailure
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("delete from activity where id = 2") # the check no longer fits
    s.close()
    check map(w.db, "--selection", a.selection, "--state", a.state) == exitFailure

  test "without a state, activities that are not there are skipped; another user's are never drawn":
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
    s.close()
    check map(w.db, "--selection", encodeBits([1'i64, 2, 4])) == exitOk # 4 is bob's
    let j = parseFile(w.cache / geojsons(w.cache)[0])
    check j["features"].len == 2 # (only the default user's)

  test "two spellings of the same activities are one request and one file":
    let w = world("spellings")
    let a = addressOf(w.db)
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
    s.close()
    check map(w.db, "--selection", a.selection) == exitOk
    check map(w.db, "--selection", encodeBits([1'i64, 2, 3, 4])) == exitOk # 4 is bob's
    check geojsons(w.cache).len == 1

  test "a pinned address whose file is gone is made again if the state is the same, else refused":
    let w = world("remade")
    check map(w.db) == exitOk
    let a = addressOf(w.db)
    let path = w.cache / files(w.cache)[0]
    removeFile(path)
    check map(w.db, "--selection", a.selection, "--state", a.state) == exitOk
    check fileExists(path) # (the same name: the plot of that address)
    removeFile(path)
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("update file set sha256 = 'z' where name = 'a'")
    s.close()
    check map(w.db, "--selection", a.selection, "--state", a.state) == exitFailure
    check files(w.cache).len == 0

  test "--worker makes the page too; the data is not remade, the page is":
    let w = world("worker")
    check map(w.db, "--worker") == exitOk
    let stem = files(w.cache)[0].changeFileExt("")
    check files(w.cache) == @[stem & ".geojson", stem & ".html"]
    let page = readFile(w.cache / (stem & ".html"))
    check page.contains("fetch('/files/" & stem & ".geojson')")
    setLastModificationTime(w.cache / (stem & ".geojson"), fromUnix(1_000_000_000))
    writeFile(w.cache / (stem & ".html"), "old page")
    check map(w.db, "--worker") == exitOk
    check getLastModificationTime(w.cache / (stem & ".geojson")).toUnix == 1_000_000_000
    check readFile(w.cache / (stem & ".html")).startsWith("<!DOCTYPE html>")
      # (rewritten)

  test "without --worker there is no page":
    let w = world("noworker")
    check map(w.db) == exitOk
    check files(w.cache).len == 1 and files(w.cache)[0].endsWith(".geojson")

  test "an empty selection, or none with a route, is an error and writes nothing":
    let w = world("empty")
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("delete from selection")
    s.close()
    check map(w.db) == exitFailure
    check map(w.db, "--worker") == exitFailure
    let s2 = openSession(w.db, allFragments, access = allAccess)
    s2.db.execute(
      "insert into selection(user_id, activity_id) values (:userId, 3)",
      userId = s2.userId,
    )
    s2.close()
    check map(w.db) == exitFailure # (activity 3 has no route)
    check files(w.cache).len == 0

  test "bad options are a usage error":
    let w = world("usage")
    check map(w.db, "--selection", "a b") == exitUsage
    check map(w.db, "--selection", "A") == exitUsage # (too short to read)
    check map(w.db, "--selection", encodeBits([9999'i64])) == exitUsage
      # (beyond the last activity)
    check map(w.db, "--style", "lines") == exitUsage
    check map(w.db, "--state", "ab12cd") == exitUsage
    check map(w.db, "--help") == exitOk
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
    check geojsons(w.cache).len == 2 # (another request: another file)
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
  test "the state of a heat map does not depend on the climbs, but the default's does":
    let w = world("state")
    withCells(w.db)
    let s = openSession(w.db, allFragments, access = allAccess)
    let ids = ownedIds(s, selectedIds(s))
    let heat = stateOf(s, ids, {lyHeat})
    let routes = stateOf(s, ids, {lyRoutes, lyClimbs})
    s.db.execute(
      """insert into sector(length_m, gain_m, gradient, category, name, route)
      values (1000, 90, 9, '4', 'Cerro', GeomFromText('LINESTRING Z(-9.14 38.72 10, -9.13 38.72 100)', 4326))"""
    )
    s.db.execute(
      "insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m) values (1, 1, 1, 61, 60, 0)"
    )
    check stateOf(s, ids, {lyHeat}) == heat
    check stateOf(s, ids, {lyRoutes, lyClimbs}) != routes
    s.db.execute("update file set sha256 = 'z' where name = 'a'")
    check stateOf(s, ids, {lyHeat}) != heat # (the activities themselves)
    s.close()
  test "a heat map of activities that went through no cell is an error, and writes nothing":
    let w = world("nocells")
    check map(w.db, "--layers", "heat") == exitFailure
    check geojsons(w.cache).len == 0
  test "a route in several parts (a ride with pauses) can be drawn":
    # (the key of the routes counted their points with NumPoints, which is null for more than one part)
    let w = world("parts")
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute(
      "update route set geom = GeomFromText('MULTILINESTRING((-9.14 38.72, -9.13 38.72), (-9.12 38.72, -9.11 38.72))', 4326) where activity_id = 1"
    )
    s.close()
    check map(w.db) == exitOk
    check parseFile(w.cache / geojsons(w.cache)[0])["features"].len == 2
  test "an address with layers is pinned with them, and an old address without is the default":
    let w = world("pin")
    withCells(w.db)
    check map(w.db, "--layers", "heat") == exitOk
    let a = addressOf(w.db)
    let s = openSession(w.db, allFragments, access = allAccess)
    let heat = stateOf(s, ownedIds(s, selectedIds(s)), {lyHeat})
    s.close()
    check map(w.db, "--layers", "heat", "--selection", a.selection, "--state", heat) ==
      exitOk
    check geojsons(w.cache).len == 1 # (the file is there: nothing was made)
    check map(w.db, "--layers", "heat", "--selection", a.selection, "--state", "000000") ==
      exitFailure # (a state that is not the heat's, and the file is not there)

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
  test "the efforts and the gates need the climbs worked out, and are inputs of the state; a heat map is not touched":
    let w = world("effortsstate")
    withClimb(w.db)
    withRideAlongClimb(w.db)
    let s = openSession(w.db, allFragments, access = allAccess)
    defer:
      s.close()
    let ids = ownedIds(s, selectedIds(s))
    let before = stateOf(s, ids, {lyEfforts})
    s.db.execute("update effort set finish_t = 60, elapsed_s = 59")
    check stateOf(s, ids, {lyEfforts}) != before # (the effort moved)
    let gates = stateOf(s, ids, {lyGates})
    s.db.execute(
      "update sector set route = GeomFromText('LINESTRING Z(-9.14 38.72 10, -9.12 38.73 100)', 4326)"
    )
    check stateOf(s, ids, {lyGates}) != gates # (the gates moved with the route)
  test "no efforts, and no climbs: the layers are empty and the file is still valid":
    let w = world("noefforts")
    check map(w.db, "--layers", "routes", "efforts", "gates") == exitOk
    check kinds(parseFile(w.cache / geojsons(w.cache)[0])) == @["route", "route"]
