import ../support/arrays
import nimchoo/packages/db/statement
import std/[options, os, unittest]
import ../support/shims
import nimchoo/packages/importer/extract
import nimchoo/packages/importer/importer
import std/tables
import nimchoo/packages/db/store
import nimchoo/packages/user/session
import nimchoo/packages/importer/channel
import nimchoo/packages/util/hashing/hashing
import nimchoo/core/errors
import nimchoo/packages/util/bytes/bytes
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/fit/load
import nimchoo/packages/util/warnings/warnings
import ../support/fitbuilder

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"
  multisport =
    "../choochoo/data/test/source/python-fitparse/" &
    "activity-large-fenxi2-multisport.fit"
  base = 900_000_000

let p = loadProfile(profilePath)

proc openAll(path: string, user = defaultUser): Session =
  ## The whole schema.
  openSession(path, allFragments, user, access = allAccess)

let dir = getTempDir() / "nch-test-import"

proc tempDb(name: string): string =
  createDir(dir)
  result = dir / name & ".db"
  removeFile(result)

proc count(s: Session, table: string): int =
  s.db.scalar(int, "select count(*) from " & table)

proc importPath(s: Session, path: string): (ImportResult, seq[Warning]) =
  var ws: seq[Warning]
  let r = s.importFile(p, extractFilename(path), readBytes(path), ws)
  (r, ws)

# a small hand-built activity: three coordinates, one session
let tiny = fitFile(
  defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)]) & b(0) & le32(
    base
  ) & le32(536870912) & le32(-1073741824) & b(0) & le32(base + 1) & le32(536870912) &
    le32(-1073741824) & b(0) & le32(base + 2) & le32(536870912) & le32(-1073741824) &
    defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T), (5, 1, enumT)]) & b(1) &
    le32(base + 2) & le32(base) & b(2)
)

# three stretches of riding (the timer stopped and restarted by hand): 5, 4 and 3 coordinates,
# paused for 6 s and 7 s between them
let threeStretches = block:
  func rec(t, i: int): seq[byte] =
    b(0) & le32(base + t) & le32(536870912 + 100 * i) & le32(-1073741824)
  func timer(t, kind: int): seq[byte] =
    b(5) & le32(base + t) & b(0, kind, 0)
  var body = defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)])
  body.add defn(
    5, 21, @[(253, 4, uint32T), (0, 1, enumT), (1, 1, enumT), (3, 1, enumT)]
  )
  for (from0, to0) in [(0, 4), (10, 13), (20, 22)]:
    body.add timer(from0, 0)
    for t in from0 .. to0:
      body.add rec(t, t)
    body.add timer(to0, 4)
  body.add defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T), (5, 1, enumT)])
  body.add b(1) & le32(base + 22) & le32(base) & b(2)
  fitFile(body)

suite "import: a real ride":
  test "one activity and all its coordinates":
    let s = openAll(tempDb("ride"))
    defer:
      s.close()
    let (r, ws) = s.importPath(ride)
    check r.outcome == ioImported
    check r.activities == 1
    check r.coords == 2099
    check r.segments == 1 # its 20 timer segments are auto-pauses the rider did not leave
    check ws.len == 0
    check s.count("segment") == 1
    check s.count("file") == 1
    check s.count("activity") == 1
    s.db.materialise()
    check s.count("coords") == 2099
    check s.db.scalar(string, "select sport || '/' || sub_sport from activity") ==
      "cycling/generic"
    check s.db.scalar(int, "select start_t from activity") == 1535373814
    check s.db.scalar(int, "select utc_offset_s from activity") == -10800
    check abs(s.db.scalar(float, "select distance_m from activity") - 11978.11) < 1e-6
    check s.db.scalar(int, "select count(*) from coords where alt is null") == 2099

  test "the route has a part for each segment, and is where the points are":
    let s = openAll(tempDb("ride-route"))
    defer:
      s.close()
    discard s.importPath(ride)
    check s.count("route") == 1
    check s.db.scalar(int, "select NumGeometries(geom) from route") == 1
    check s.db.scalar(int, "select ST_NPoints(geom) from route") == 2099
    # every point is within the route's bounding box (to the rounding of 7 decimals), and the route is about as long as the ride
    s.db.materialise()
    check s.db.scalar(
      int,
      """select count(*) from coords c, route r where
      c.lon < MbrMinX(r.geom) - 1e-6 or c.lon > MbrMaxX(r.geom) + 1e-6 or
      c.lat < MbrMinY(r.geom) - 1e-6 or c.lat > MbrMaxY(r.geom) + 1e-6""",
    ) == 0
    let km = s.db.scalar(float, "select GeodesicLength(geom) from route") / 1000
    check km > 8 and km < 14 # (the device says 11.98 km)

  test "the coordinates are in degrees, at the right times":
    let s = openAll(tempDb("ride-coords"))
    defer:
      s.close()
    discard s.importPath(ride)
    s.db.materialise()
    let first = s.db.scalar(
      tuple[t: int64, lat, lon: float],
      "select t, lat, lon from coords order by t limit 1",
    )
    check first.t == 1535373814
    check abs(first.lat - (-398821890.0 * 180.0 / 2147483648.0)) < 1e-9
    check abs(first.lon - (-842376459.0 * 180.0 / 2147483648.0)) < 1e-9
    check s.db.scalar(int, "select min(t) = (select start_t from activity) from coords") ==
      1

  test "importing the same file again does nothing":
    let s = openAll(tempDb("twice"))
    defer:
      s.close()
    discard s.importPath(ride)
    let (r, _) = s.importPath(ride)
    check r.outcome == ioDuplicate
    check r.activities == 0
    check s.count("file") == 1
    check s.count("activity") == 1
    s.db.materialise()
    check s.count("coords") == 2099

  test "the same content under another name is the same file":
    let s = openAll(tempDb("renamed"))
    defer:
      s.close()
    discard s.importPath(ride)
    var ws: seq[Warning]
    let r = s.importFile(p, "copy.fit", readBytes(ride), ws)
    check r.outcome == ioDuplicate

  test "each user has their own copy":
    let path = tempDb("users")
    let a = openAll(path)
    a.db.execute("insert into user(name) values ('bob')")
    discard a.importPath(ride)
    a.close()
    let b = openAll(path, "bob")
    defer:
      b.close()
    let (r, _) = b.importPath(ride)
    check r.outcome == ioImported
    check b.count("file") == 2
    check b.count("activity") == 2
    check b.db.scalar(
      int,
      "select count(distinct f.user_id) from activity a join file f on f.id = a.file_id",
    ) == 2

suite "import: several sessions":
  test "a multisport file gives an activity per session":
    let s = openAll(tempDb("multi"))
    defer:
      s.close()
    let (r, _) = s.importPath(multisport)
    check r.activities == 7
    check s.count("activity") == 7
    s.db.materialise()
    check s.count("coords") == r.coords
    check r.coords > 20000
    check s.db.scalar(int, "select count(distinct session) from activity") == 7
    # the time ranges follow one another
    check s.db.scalar(
      int,
      """select count(*) from activity a join activity b
      on b.start_t > a.start_t and b.start_t < a.end_t""",
    ) == 0
    # every coordinate lies in the activity it belongs to (or before the first)
    check s.db.scalar(
      int,
      """select count(*) from coords c join activity a
      on a.id = c.activity_id where c.t > a.end_t + 1""",
    ) == 0

suite "import: files that cannot be imported":
  test "a small hand-built file":
    let s = openAll(tempDb("tiny"))
    defer:
      s.close()
    var ws: seq[Warning]
    let r = s.importFile(p, "tiny.fit", tiny, ws)
    check r.coords == 3
    s.db.materialise()
    check s.db.scalar(string, "select lat || ' ' || lon from coords limit 1") ==
      "45.0 -90.0"

  test "the start of an activity is its first position, as a point":
    let s = openAll(tempDb("start"))
    defer:
      s.close()
    var ws: seq[Warning]
    discard s.importFile(p, "tiny.fit", tiny, ws)
    check s.db.scalar(string, "select ST_Y(start) || ' ' || ST_X(start) from activity") ==
      "45.0 -90.0"
    check s.db.scalar(int, "select count(*) from idx_activity_start") == 1
      # (and it is indexed)
    # a real ride: the same as the first row of its coordinates
    discard s.importPath(ride)
    s.db.materialise()
    check s.db.scalar(
      int,
      """select count(*) from activity a where a.start is not null and
      ST_X(a.start) = (select lon from coords where activity_id = a.id order by t limit 1) and
      ST_Y(a.start) = (select lat from coords where activity_id = a.id order by t limit 1)""",
    ) == 2

  test "the start is the first position; the start place and the name are not made at import (they are null until named)":
    let s = openAll(tempDb("placed"))
    defer:
      s.close()
    discard s.importPath(ride)
    check s.db.scalar(int, "select count(*) from activity where start is not null") == 1
    check s.db.scalar(
      int, "select count(*) from activity where start_place is null and name is null"
    ) == 1

  test "no positions, no start":
    let s = openAll(tempDb("nostart"))
    defer:
      s.close()
    let noGps = fitFile(
      defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T), (5, 1, enumT)]) & b(1) &
        le32(base + 2) & le32(base) & b(2)
    )
    var ws: seq[Warning]
    let r = s.importFile(p, "nogps.fit", noGps, ws)
    check r.activities == 1 and r.coords == 0
    check s.db.scalar(int, "select count(*) from activity where start is null") == 1
    check s.db.scalar(int, "select count(*) from idx_activity_start") == 0

  test "a file with no activity writes nothing":
    let s = openAll(tempDb("noact"))
    defer:
      s.close()
    let noSession = fitFile(defn(0, 20, @[(253, 4, uint32T)]) & b(0) & le32(base))
    var ws: seq[Warning]
    expect ImportError:
      discard s.importFile(p, "x.fit", noSession, ws)
    check s.count("file") == 0
    check s.count("activity") == 0

  test "a file that is not a FIT file writes nothing":
    let s = openAll(tempDb("junk"))
    defer:
      s.close()
    var ws: seq[Warning]
    expect FitError:
      discard s.importFile(p, "x.fit", b(1, 2, 3), ws)
    check s.count("file") == 0

  test "a route has a part for each stretch, with every point in some part":
    let s = openAll(tempDb("route-parts"))
    defer:
      s.close()
    var ws: seq[Warning]
    discard s.importFile(p, "three.fit", threeStretches, ws)
    check s.db.scalar(int, "select NumGeometries(geom) from route") == 3
    check s.db.scalar(int, "select ST_NPoints(geom) from route") == 12

  test "a failure part way leaves no rows behind":
    let s = openAll(tempDb("rollback"))
    defer:
      s.close()
    s.db.execute("drop table track") # an insert will fail
    var ws: seq[Warning]
    expect StoreError:
      discard s.importFile(p, "tiny.fit", tiny, ws)
    check s.count("file") == 0
    check s.count("activity") == 0
    # and the connection is usable afterwards
    s.db.execute("create table track(x)")

suite "import: segments":
  test "the segments are stored in order, covering every coordinate":
    let s = openAll(tempDb("segments"))
    defer:
      s.close()
    var ws: seq[Warning]
    discard s.importFile(p, "three.fit", threeStretches, ws)
    check s.db.scalar(string, "select min(n) || '-' || max(n) from segment") == "0-2"
    check s.db.scalar(
      int,
      """select count(*) from segment a join segment b
      on b.activity_id = a.activity_id and b.n = a.n + 1
      where b.start_t <= a.end_t""",
    ) == 0
    s.db.materialise()
    check s.db.scalar(
      int,
      """select count(*) from coords c where not exists (
      select 1 from segment g where g.activity_id = c.activity_id
        and c.t between g.start_t and g.end_t)""",
    ) == 0
    # the time between segments is the time paused
    check s.db.scalar(
      int,
      """select sum(b.start_t - a.end_t) from segment a
      join segment b on b.activity_id = a.activity_id and b.n = a.n + 1""",
    ) == 13

  test "the real ride's auto-pauses are joined: one stretch from its first start to its last stop":
    let s = openAll(tempDb("ride-stretch"))
    defer:
      s.close()
    discard s.importPath(ride)
    check s.db.scalar(string, "select min(n) || '-' || max(n) from segment") == "0-0"
    s.db.materialise()
    check s.db.scalar(
      int,
      """select count(*) from coords c, segment g where c.t < g.start_t or c.t > g.end_t""",
    ) == 0

  test "the coordinates of one segment are a range of the key":
    let s = openAll(tempDb("segrange"))
    defer:
      s.close()
    discard s.importPath(ride)
    s.db.materialise()
    check s.db.scalar(
      int,
      """select sum(cnt) from (
      select (select count(*) from coords c where c.activity_id = g.activity_id
        and c.t between g.start_t and g.end_t) as cnt from segment g)""",
    ) == 2099

  test "a multisport file has segments for each activity":
    let s = openAll(tempDb("segmulti"))
    defer:
      s.close()
    let (r, _) = s.importPath(multisport)
    check r.segments == s.count("segment")
    check s.db.scalar(int, "select count(distinct activity_id) from segment") == 7

suite "import: decoding apart from writing":
  test "decodeFile needs no database: activities, their routes as bytes, and the warnings":
    var ws: seq[Warning]
    let d = decodeFile(p, tiny, @[], ws)
    check d.activities.len == 1 and d.routes.len == 1
    check d.activities[0].coords.len == 3
    check d.routes[0].isSome and d.routes[0].get.len == 9 + 9 + 3 * 16
      # one line of three points
    check ws.len == 0

  test "a real ride: the route has a point for each coordinate":
    var ws: seq[Warning]
    let d = decodeFile(p, readBytes(ride), @["heart_rate"], ws)
    check d.activities[0].coords.len == 2099 and
      d.activities[0].samples["heart_rate"].len == 2099
    check d.routes[0].get.len == 9 + 1 * 9 + 2099 * 16 # one stretch

  test "a file that cannot be used raises, and the warnings so far are kept":
    var ws: seq[Warning]
    expect FitError:
      discard decodeFile(p, b(1, 2, 3), @[], ws)
    let noSession = fitFile(defn(0, 20, @[(253, 4, uint32T)]) & b(0) & le32(base))
    expect ImportError:
      discard decodeFile(p, noSession, @[], ws)

  test "channelsOf lists the fields the steps want, once each":
    let a = ImportStep(channels: @["heart_rate", "cadence"])
    let c = ImportStep(channels: @["heart_rate", "power"])
    check channelsOf(@[a, c]) == @["heart_rate", "cadence", "power"]
    check channelsOf(@[]).len == 0

  test "knownFile finds a file by its content, only for the user it was imported for":
    let path = tempDb("known")
    let a = openAll(path)
    a.db.execute("insert into user(name) values ('bob')")
    var ws: seq[Warning]
    let digest = sha256Hex(tiny)
    check knownFile(a, digest).isNone
    let r = a.importFile(p, "tiny.fit", tiny, ws)
    check knownFile(a, digest) == some(r.fileId)
    a.close()
    let b2 = openAll(path, "bob")
    defer:
      b2.close()
    check knownFile(b2, digest).isNone

  test "writeDecoded writes what importFile does, and only that":
    let one = openAll(tempDb("write1"))
    let two = openAll(tempDb("write2"))
    defer:
      one.close()
      two.close()
    var ws: seq[Warning]
    let viaFile = one.importFile(p, "r.fit", readBytes(ride), ws)
    var ws2: seq[Warning]
    let d = decodeFile(p, readBytes(ride), @[], ws2)
    let viaParts = two.writeDecoded("r.fit", sha256Hex(readBytes(ride)), d, @[])
    check viaParts.outcome == ioImported and viaParts.coords == viaFile.coords and
      viaParts.segments == viaFile.segments and viaParts.activities == viaFile.activities
    for table in ["file", "activity", "track", "segment", "route"]:
      check one.count(table) == two.count(table)
    one.db.materialise()
    two.db.materialise()
    check one.db.scalar(string, "select sum(lon) || ',' || sum(lat) from coords") ==
      two.db.scalar(string, "select sum(lon) || ',' || sum(lat) from coords")
    # and nothing is written if the writing fails part way
    let three = openAll(tempDb("write3"))
    defer:
      three.close()
    three.db.execute("drop table track")
    expect StoreError:
      discard three.writeDecoded("r.fit", "x", d, @[])
    check three.count("file") == 0
