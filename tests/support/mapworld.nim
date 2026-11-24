## A small world to draw maps of, with the real registry: two activities with routes and one without, all selected; a climb ridden by
## the first; the positions of that ride; the cells two rides went through.  Shared by the tests of the frames of `activities` and of
## `climbs` (tests/activities/test_mapframes.nim, tests/climbs/test_mapframes.nim).

import std/[options, json, os, strutils]
import nimchoo/core/globals
import nimchoo/packages/db/statement
import nimchoo/packages/fit/time
import nimchoo/packages/importer/coord
import nimchoo/packages/map/command as mapCommand
import nimchoo/packages/user/session
import ./arrays

from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

proc wkt(points: int, lon0, lat0: float): string =
  ## A straight line of many points (so simplifying has something to remove).
  var pts: seq[string]
  for i in 0 ..< points:
    pts.add formatFloat(lon0 + i.float * 0.0001, ffDecimal, 7) & " " &
      formatFloat(lat0, ffDecimal, 7)
  "MULTILINESTRING((" & pts.join(", ") & "))"

proc world*(top, name: string): tuple[db, cache: string] =
  ## Two activities with routes (60 points each) and one without; all selected.  `cache` is where the files go.
  removeDir(top / name)
  result = (top / name / "x.db", top / name / "cache" / "user")
  putEnv("NCH_CACHE", top / name / "cache")
  let s = openSession(result.db, allFragments, access = allAccess)
  defer:
    s.close()
  for (tag, t, route) in [
    ("a", 1000, wkt(60, -9.14, 38.72)),
    ("b", 2000, wkt(60, 2.35, 48.85)),
    ("c", 3000, ""),
  ]:
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_epoch) values (:userId, :name, :sha256, 0)",
      userId = s.userId,
      name = tag,
      sha256 = tag,
    )
    let f = s.db.scalar(int64, "select max(id) from file")
    s.db.execute(
      "insert into activity(file_id, session, start_epoch, end_epoch, sport, riding_start_epoch, riding_end_epoch) values (:fileId, 0, :startT, :endT, 'cycling', :startT, :endT)",
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
      "insert into activity_selection(user_id, activity_id) values (:userId, :activityId)",
      userId = s.userId,
      activityId = a,
    )

proc globalsOf*(db: string, user = ""): Globals =
  ## The globals of the real program for the database.
  Globals(
    dbPath: some(db),
    user: (if user.len > 0: some(user) else: none(string)),
    fragments: allFragments,
    access: allAccess,
    extensions: extensions,
  )

proc map*(db: string, args: varargs[string]): int =
  ## `nch map ARGS --file`, with the real registry (without `--file` the command would serve the page until stopped).
  mapCommand.run(globalsOf(db), @args & @["--file"])

proc mapRaw*(db: string, args: varargs[string]): int =
  ## `nch map ARGS` as given.
  mapCommand.run(globalsOf(db), @args)

proc files*(cache: string): seq[string] =
  if dirExists(cache):
    for f in walkFiles(cache / "*"):
      result.add f.extractFilename

proc frameFile*(cache, frame: string, subject = "activities"): string =
  ## The GeoJSON file of a frame (the path).
  cache / ("map-" & subject & "-" & frame & ".geojson")

proc kinds*(j: JsonNode): seq[string] =
  for f in j["features"]:
    result.add f["properties"]["kind"].getStr

proc withClimb*(db: string) =
  ## A climb ridden by activity 1.
  let s = openSession(db, allFragments, access = allAccess)
  defer:
    s.close()
  s.db.execute(
    """insert into sector(length_m, gain_m, gradient, category, name, route)
    values (1000, 90, 9, '4', 'Cerro', GeomFromText('LINESTRING Z(-9.14 38.72 10, -9.13 38.72 100)', 4326))"""
  )
  s.db.execute(
    """insert into effort(sector_id, activity_id, start_epoch, finish_epoch, elapsed_s, start_m)
    values (1, 1, 1, 61, 60, 0)"""
  )

proc withRideAlongClimb*(db: string) =
  ## The positions of ride 1 over the climb (a point a second for the 60 s of its effort, along the climb's line).
  let s = openSession(db, allFragments, access = allAccess)
  defer:
    s.close()
  var coords: seq[Coord]
  for t in 0 .. 62:
    coords.add Coord(t: UnixTime(t), lon: -9.14 + 0.01 * float(t) / 61.0, lat: 38.72)
  s.db.putTrack(1, coords)

proc withCells*(db: string) =
  ## Where the two rides went: ride 1 two cells, one of them twice, ride 2 one cell.
  let s = openSession(db, allFragments, access = allAccess)
  defer:
    s.close()
  s.db.execute(
    """insert into route_cell(activity_id, cell, in_epoch, out_epoch) values
      (1, cell(-9.14, 38.72), 1000, 1002), (1, cell(-9.13, 38.72), 1003, 1005),
      (1, cell(-9.14, 38.72), 1006, 1008), (2, cell(2.35, 48.85), 2000, 2004)"""
  )
