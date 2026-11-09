import ../support/env
import std/[json, options, os, strutils, times, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/map/command as mapCommand
import nimchoo/cache
import nimchoo/modules
import nimchoo/selection/[bits, selection]

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
  let s = openStore(result.db, allFragments)
  defer:
    s.close()
  for (tag, t, route) in [
    ("a", 1000, wkt(60, -9.14, 38.72)),
    ("b", 2000, wkt(60, 2.35, 48.85)),
    ("c", 3000, ""),
  ]:
    s.db.exec(
      sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
      s.userId,
      tag,
      tag,
    )
    let f = s.db.getValue(sql"select max(id) from file")
    s.db.exec(
      sql"insert into activity(file_id, session, start_t, end_t, sport) values (?, 0, ?, ?, 'cycling')",
      f,
      t,
      t + 10,
    )
    let a = s.db.getValue(sql"select max(id) from activity")
    if route.len > 0:
      s.db.exec(
        sql"insert into route(activity_id, geom) values (?, GeomFromText(?, 4326))",
        a,
        route,
      )
    s.db.exec(
      sql"insert into selection(user_id, activity_id) values (?, ?)", s.userId, a
    )

proc map(db: string, args: varargs[string]): int =
  mapCommand.run(Globals(dbPath: db, fragments: allFragments), @args)

proc files(cache: string): seq[string] =
  if dirExists(cache):
    for f in walkFiles(cache / "*"):
      result.add f.extractFilename

proc geojsons(cache: string): seq[string] =
  for f in files(cache):
    if f.endsWith(".geojson"):
      result.add f

proc addressOf(db: string): tuple[bits, check: string] =
  ## What the address of the map of the current selection carries.
  let s = openStore(db, allFragments)
  defer:
    s.close()
  let ids = selectedIds(s)
  (encodeBits(ids), checkOf(s, ownedIds(s, ids)))

proc withClimb(db: string) =
  ## A climb ridden by activity 1.
  let s = openStore(db, allFragments)
  defer:
    s.close()
  s.db.exec(
    sql"""insert into sector(length_m, gain_m, gradient, category, name, route)
    values (1000, 90, 9, '4', 'Cerro', GeomFromText('LINESTRING Z(-9.14 38.72 10, -9.13 38.72 100)', 4326))"""
  )
  s.db.exec(
    sql"""insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m)
    values (1, 1, 1, 61, 60, 0)"""
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
      requestStem("map", "bits=" & a.bits & "&check=" & a.check).get & ".geojson"
    check files(w.cache) == @[name]
    check name.startsWith("map-") and isCacheFileName(name)
    let j = parseFile(w.cache / name)
    check j["nch"]["request"].getStr == "bits=" & a.bits & "&check=" & a.check
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

  test "every input of the file is part of its key: a change of any of them makes the file again, in place":
    # (the class of bug: a cached file kept after something it is made from changed)
    let w = world("inputs")
    withClimb(w.db)
    check map(w.db) == exitOk
    let path = w.cache / files(w.cache)[0]
    proc changeAndRemake(sql: string): string =
      let s = openStore(w.db, allFragments)
      s.db.exec(sql(sql))
      s.close()
      setLastModificationTime(path, fromUnix(1_000_000_000))
      check map(w.db) == exitOk
      check files(w.cache).len == 1 # (in place: no second file)
      readFile(path)

    check readFile(path).contains("\"name\":\"Cerro\"")
    # the name of a climb
    check changeAndRemake("update sector set name = 'Renamed'").contains("Renamed")
    # its category, and its retiring
    check changeAndRemake("update sector set category = 'HC'").contains("\"HC\"")
    check not changeAndRemake("update sector set retired = 1").contains(
      "\"kind\":\"climb\""
    )
    discard changeAndRemake("update sector set retired = 0")
    # the route of an activity
    let before = readFile(path)
    check changeAndRemake(
      "update route set geom = GeomFromText('MULTILINESTRING((-9.14 38.72, -9.13 38.72))', 4326) where activity_id = 1"
    ) != before
    # (the content of an activity is in the request, through `check`: another file, see below)

  test "the content of an activity changes the request: a file of its own":
    let w = world("content")
    check map(w.db) == exitOk
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"update file set sha256 = 'z' where name = 'a'")
    s.close()
    check map(w.db) == exitOk
    check files(w.cache).len == 2

  test "nothing changed: the file is left alone (also across other changes the map does not read)":
    let w = world("unchanged")
    withClimb(w.db)
    check map(w.db) == exitOk
    let path = w.cache / files(w.cache)[0]
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"insert into user(name, is_default) values ('bob', 0)")
    s.close()
    setLastModificationTime(path, fromUnix(1_000_000_000))
    check map(w.db) == exitOk
    check getLastModificationTime(path).toUnix == 1_000_000_000

  test "an address made for a selection still draws it after the selection changes":
    let w = world("pinned")
    check map(w.db) == exitOk
    let old = addressOf(w.db)
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"delete from selection where activity_id = 1")
    s.close()
    check addressOf(w.db) != old
    check map(w.db, "--bits", old.bits, "--check", old.check) == exitOk
      # the file is there, the old activities
    check files(w.cache).len == 1
    check map(w.db) == exitOk # the new selection: a file of its own
    check files(w.cache).len == 2

  test "an address whose activities have changed is refused: a wrong check, or activities deleted":
    let w = world("changed")
    check map(w.db) == exitOk
    let a = addressOf(w.db)
    check map(w.db, "--bits", a.bits, "--check", "000000") == exitFailure
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"delete from activity where id = 2") # the check no longer fits
    s.close()
    check map(w.db, "--bits", a.bits, "--check", a.check) == exitFailure

  test "without a check, activities that are not there are skipped; another user's are never drawn":
    let w = world("others")
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"insert into user(name, is_default) values ('bob', 0)")
    let bob = s.db.getValue(sql"select id from user where name = 'bob'")
    s.db.exec(
      sql"insert into file(user_id, name, sha256, imported_at) values (?, 'bobs', 'bobs', 0)",
      bob,
    )
    s.db.exec(
      sql"insert into activity(file_id, session, start_t, end_t) select max(id), 0, 5000, 5010 from file"
    )
    s.db.exec(
      sql"insert into route(activity_id, geom) select max(id), GeomFromText('MULTILINESTRING((0 0, 1 1))', 4326) from activity"
    )
    s.close()
    check map(w.db, "--bits", encodeBits([1'i64, 2, 4])) == exitOk # 4 is bob's
    let j = parseFile(w.cache / geojsons(w.cache)[0])
    check j["features"].len == 2 # (only the default user's)

  test "two spellings of the same activities are one request and one file":
    let w = world("spellings")
    let a = addressOf(w.db)
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"insert into user(name, is_default) values ('bob', 0)")
    let bob = s.db.getValue(sql"select id from user where name = 'bob'")
    s.db.exec(
      sql"insert into file(user_id, name, sha256, imported_at) values (?, 'bobs', 'bobs', 0)",
      bob,
    )
    s.db.exec(
      sql"insert into activity(file_id, session, start_t, end_t) select max(id), 0, 5000, 5010 from file"
    )
    s.close()
    check map(w.db, "--bits", a.bits) == exitOk
    check map(w.db, "--bits", encodeBits([1'i64, 2, 3, 4])) == exitOk # 4 is bob's
    check geojsons(w.cache).len == 1

  test "a name already used by another request is not reused":
    let w = world("collision")
    let a = addressOf(w.db)
    let request = "bits=" & a.bits & "&check=" & a.check
    createDir(w.cache)
    let taken = w.cache / (requestStem("map", request).get & ".geojson")
    writeFile(taken, "{\"not\":\"ours\"}")
    check map(w.db) == exitOk
    check geojsons(w.cache).len == 2
    check readFile(taken) == "{\"not\":\"ours\"}" # (left as it was)

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
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"delete from selection")
    s.close()
    check map(w.db) == exitFailure
    check map(w.db, "--worker") == exitFailure
    let s2 = openStore(w.db, allFragments)
    s2.db.exec(
      sql"insert into selection(user_id, activity_id) values (?, 3)", s2.userId
    )
    s2.close()
    check map(w.db) == exitFailure # (activity 3 has no route)
    check files(w.cache).len == 0

  test "bad options are a usage error":
    let w = world("usage")
    check map(w.db, "--bits", "a b") == exitUsage
    check map(w.db, "--bits", "A") == exitUsage # (too short to read)
    check map(w.db, "--bits", encodeBits([9999'i64])) == exitUsage
      # (beyond the last activity)
    check map(w.db, "--style", "lines") == exitUsage
    check map(w.db, "--check", "ab12cd") == exitUsage
    check map(w.db, "--help") == exitOk
    check files(w.cache).len == 0

  test "a cache directory that cannot be made is an error":
    let w = world("blocked")
    writeFile(dir / "blocked" / "file", "")
    putEnv("NCH_CACHE", dir / "blocked" / "file" / "cache")
    check map(w.db) == exitFailure
    useTestCache()
