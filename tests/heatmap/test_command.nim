import std/[json, os, strutils, times, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/heatmap/command as heatmapCommand
import nimchoo/modules
import nimchoo/select/selection

let dir = getTempDir() / "nch-test-heatmap"

proc wkt(points: int, lon0, lat0: float): string =
  ## A straight line of many points (so simplifying has something to remove).
  var pts: seq[string]
  for i in 0 ..< points:
    pts.add formatFloat(lon0 + i.float * 0.0001, ffDecimal, 7) & " " & formatFloat(lat0, ffDecimal, 7)
  "MULTILINESTRING((" & pts.join(", ") & "))"

proc world(name: string): tuple[db, cache: string] =
  ## Two activities with routes (60 points each) and one without; all selected.
  removeDir(dir / name)
  result = (dir / name / "x.db", dir / name / "cache")
  putEnv("NCH_CACHE", result.cache)
  let s = openStore(result.db, allFragments)
  defer: s.close()
  for (tag, t, route) in [("a", 1000, wkt(60, -9.14, 38.72)), ("b", 2000, wkt(60, 2.35, 48.85)),
                          ("c", 3000, "")]:
    s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
              s.userId, tag, tag)
    let f = s.db.getValue(sql"select max(id) from file")
    s.db.exec(sql"insert into activity(file_id, session, start_t, end_t, sport) values (?, 0, ?, ?, 'cycling')",
              f, t, t + 10)
    let a = s.db.getValue(sql"select max(id) from activity")
    if route.len > 0:
      s.db.exec(sql"insert into route(activity_id, geom) values (?, GeomFromText(?, 4326))", a, route)
    s.db.exec(sql"insert into selection(user_id, activity_id) values (?, ?)", s.userId, a)

proc heatmap(db: string, args: varargs[string]): int =
  heatmapCommand.run(Globals(dbPath: db, fragments: allFragments), @args)

proc files(cache: string): seq[string] =
  if dirExists(cache):
    for f in walkFiles(cache / "*"): result.add f.extractFilename

proc points(j: JsonNode): int =
  for f in j["features"]:
    let g = f["geometry"]
    if g["type"].getStr == "LineString": result += g["coordinates"].len
    else:
      for part in g["coordinates"]: result += part.len

proc key(db: string): string =
  let s = openStore(db, allFragments)
  defer: s.close()
  selectionKey(s)

suite "heatmap: the command":
  test "writes a GeoJSON file named after the options, with a feature for each route":
    let w = world("basic")
    check heatmap(w.db) == exitOk
    let name = "heatmap--sel-" & key(w.db) & "--style-lines--tolerance-5.geojson"
    check files(w.cache) == @[name]
    let j = parseFile(w.cache / name)
    check j["features"].len == 2                  # (the third has no route)
    check j["features"][0]["properties"]["start"].getStr == "1970-01-01T00:16:40Z"

  test "routes are simplified, more with a larger tolerance, not at all with 0":
    let w = world("tolerance")
    check heatmap(w.db) == exitOk
    check heatmap(w.db, "--tolerance", "0") == exitOk
    check heatmap(w.db, "--tolerance", "0.1") == exitOk
    check files(w.cache).len == 3
    let k = key(w.db)
    let simplified = points(parseFile(w.cache / ("heatmap--sel-" & k & "--style-lines--tolerance-5.geojson")))
    let full = points(parseFile(w.cache / ("heatmap--sel-" & k & "--style-lines--tolerance-0.geojson")))
    check full == 120
    check simplified == 4                         # straight lines: two points each

  test "a second request does no work":
    let w = world("again")
    check heatmap(w.db) == exitOk
    let path = w.cache / files(w.cache)[0]
    setLastModificationTime(path, fromUnix(1_000_000_000))
    check heatmap(w.db) == exitOk
    check getLastModificationTime(path).toUnix == 1_000_000_000
    check files(w.cache).len == 1

  test "a file made for a selection is found by its key after the selection changes":
    let w = world("pinned")
    check heatmap(w.db) == exitOk
    let old = key(w.db)
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"delete from selection where activity_id = 1")
    s.close()
    check key(w.db) != old
    check heatmap(w.db, "--sel", old) == exitOk           # it is there
    check heatmap(w.db, "--sel", "ffffffffffff") == exitFailure   # not there, not current
    check heatmap(w.db) == exitOk                         # the current one, made now
    check files(w.cache).len == 2

  test "an empty selection, or none with a route, is an error and writes nothing":
    let w = world("empty")
    let s = openStore(w.db, allFragments)
    s.db.exec(sql"delete from selection")
    s.close()
    check heatmap(w.db) == exitFailure
    let s2 = openStore(w.db, allFragments)
    s2.db.exec(sql"insert into selection(user_id, activity_id) values (?, 3)", s2.userId)
    s2.close()
    check heatmap(w.db) == exitFailure                    # (activity 3 has no route)
    check files(w.cache).len == 0

  test "bad options are a usage error":
    let w = world("usage")
    check heatmap(w.db, "--style", "cells") == exitUsage
    check heatmap(w.db, "--tolerance", "x") == exitUsage
    check heatmap(w.db, "--sel", "a/b") == exitUsage
    check heatmap(w.db, "--help") == exitOk
    check files(w.cache).len == 0

  test "a cache directory that cannot be made is an error":
    let w = world("blocked")
    writeFile(dir / "blocked" / "file", "")
    putEnv("NCH_CACHE", dir / "blocked" / "file" / "cache")
    check heatmap(w.db) == exitFailure
