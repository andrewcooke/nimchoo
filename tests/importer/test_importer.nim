import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/importer/[extract, importer]
import nimchoo/db/store
import nimchoo/errors
import nimchoo/fit/bytes
import nimchoo/modules
import nimchoo/profile/load
import nimchoo/warnings
import ../support/fitbuilder

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"
  multisport = "../choochoo/data/test/source/python-fitparse/" &
    "activity-large-fenxi2-multisport.fit"
  base = 900_000_000

let p = loadProfile(profilePath)

proc openStore(path: string, user = defaultUser): Store =
  ## The whole schema.
  store.openStore(path, allFragments, user)
let dir = getTempDir() / "nch-test-import"

proc tempDb(name: string): string =
  createDir(dir)
  result = dir / name & ".db"
  removeFile(result)

proc count(s: Store, table: string): int =
  parseInt(s.db.getValue(sql("select count(*) from " & table)))

proc importPath(s: Store, path: string): (ImportResult, seq[Warning]) =
  var ws: seq[Warning]
  let r = s.importFile(p, extractFilename(path), readBytes(path), ws)
  (r, ws)

# a small hand-built activity: three coordinates, one session
let tiny = fitFile(
  defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)]) &
  b(0) & le32(base) & le32(536870912) & le32(-1073741824) &
  b(0) & le32(base + 1) & le32(536870912) & le32(-1073741824) &
  b(0) & le32(base + 2) & le32(536870912) & le32(-1073741824) &
  defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T), (5, 1, enumT)]) &
  b(1) & le32(base + 2) & le32(base) & b(2))

suite "import: a real ride":
  test "one activity and all its coordinates":
    let s = openStore(tempDb("ride"))
    defer: s.close()
    let (r, ws) = s.importPath(ride)
    check r.outcome == ioImported
    check r.activities == 1
    check r.coords == 2099
    check r.segments == 20
    check ws.len == 0
    check s.count("segment") == 20
    check s.count("file") == 1
    check s.count("activity") == 1
    check s.count("coords") == 2099
    check s.db.getValue(sql"select sport || '/' || sub_sport from activity") ==
      "cycling/generic"
    check s.db.getValue(sql"select start_t from activity") == "1535373814"
    check s.db.getValue(sql"select utc_offset_s from activity") == "-10800"
    check abs(parseFloat(s.db.getValue(sql"select distance_m from activity")) -
              11978.11) < 1e-6
    check s.db.getValue(sql"select count(*) from coords where alt is null") == "2099"

  test "the route has a part for each segment, and is where the points are":
    let s = openStore(tempDb("ride-route"))
    defer: s.close()
    discard s.importPath(ride)
    check s.count("route") == 1
    check s.db.getValue(sql"select NumGeometries(geom) from route") == "20"
    check s.db.getValue(sql"select ST_NPoints(geom) from route") == "2099"
    # every point is within the route's bounding box (to the rounding of 7 decimals), and the route is about as long as the ride
    check s.db.getValue(sql"""select count(*) from coords c, route r where
      c.lon < MbrMinX(r.geom) - 1e-6 or c.lon > MbrMaxX(r.geom) + 1e-6 or
      c.lat < MbrMinY(r.geom) - 1e-6 or c.lat > MbrMaxY(r.geom) + 1e-6""") == "0"
    let km = parseFloat(s.db.getValue(sql"select GeodesicLength(geom) from route")) / 1000
    check km > 8 and km < 14                      # (the device says 11.98 km)

  test "the coordinates are in degrees, at the right times":
    let s = openStore(tempDb("ride-coords"))
    defer: s.close()
    discard s.importPath(ride)
    let first = s.db.getRow(sql"select t, lat, lon from coords order by t limit 1")
    check first[0] == "1535373814"
    check abs(parseFloat(first[1]) - (-398821890.0 * 180.0 / 2147483648.0)) < 1e-9
    check abs(parseFloat(first[2]) - (-842376459.0 * 180.0 / 2147483648.0)) < 1e-9
    check s.db.getValue(sql"select min(t) = (select start_t from activity) from coords") == "1"

  test "importing the same file again does nothing":
    let s = openStore(tempDb("twice"))
    defer: s.close()
    discard s.importPath(ride)
    let (r, _) = s.importPath(ride)
    check r.outcome == ioDuplicate
    check r.activities == 0
    check s.count("file") == 1
    check s.count("activity") == 1
    check s.count("coords") == 2099

  test "the same content under another name is the same file":
    let s = openStore(tempDb("renamed"))
    defer: s.close()
    discard s.importPath(ride)
    var ws: seq[Warning]
    let r = s.importFile(p, "copy.fit", readBytes(ride), ws)
    check r.outcome == ioDuplicate

  test "each user has their own copy":
    let path = tempDb("users")
    let a = openStore(path)
    a.db.exec(sql"insert into user(name) values ('bob')")
    discard a.importPath(ride)
    a.close()
    let b = openStore(path, "bob")
    defer: b.close()
    let (r, _) = b.importPath(ride)
    check r.outcome == ioImported
    check b.count("file") == 2
    check b.count("activity") == 2
    check b.db.getValue(sql"select count(distinct f.user_id) from activity a join file f on f.id = a.file_id") == "2"

suite "import: several sessions":
  test "a multisport file gives an activity per session":
    let s = openStore(tempDb("multi"))
    defer: s.close()
    let (r, _) = s.importPath(multisport)
    check r.activities == 7
    check s.count("activity") == 7
    check s.count("coords") == r.coords
    check r.coords > 20000
    check s.db.getValue(sql"select count(distinct session) from activity") == "7"
    # the time ranges follow one another
    check s.db.getValue(sql"""select count(*) from activity a join activity b
      on b.start_t > a.start_t and b.start_t < a.end_t""") == "0"
    # every coordinate lies in the activity it belongs to (or before the first)
    check s.db.getValue(sql"""select count(*) from coords c join activity a
      on a.id = c.activity_id where c.t > a.end_t + 1""") == "0"

suite "import: files that cannot be imported":
  test "a small hand-built file":
    let s = openStore(tempDb("tiny"))
    defer: s.close()
    var ws: seq[Warning]
    let r = s.importFile(p, "tiny.fit", tiny, ws)
    check r.coords == 3
    check s.db.getValue(sql"select lat || ' ' || lon from coords limit 1") == "45.0 -90.0"

  test "a file with no activity writes nothing":
    let s = openStore(tempDb("noact"))
    defer: s.close()
    let noSession = fitFile(defn(0, 20, @[(253, 4, uint32T)]) & b(0) & le32(base))
    var ws: seq[Warning]
    expect ImportError:
      discard s.importFile(p, "x.fit", noSession, ws)
    check s.count("file") == 0
    check s.count("activity") == 0

  test "a file that is not a FIT file writes nothing":
    let s = openStore(tempDb("junk"))
    defer: s.close()
    var ws: seq[Warning]
    expect FitError:
      discard s.importFile(p, "x.fit", b(1, 2, 3), ws)
    check s.count("file") == 0

  test "a failure part way leaves no rows behind":
    let s = openStore(tempDb("rollback"))
    defer: s.close()
    s.db.exec(sql"drop table coords")        # the last insert will fail
    var ws: seq[Warning]
    expect StoreError:
      discard s.importFile(p, "tiny.fit", tiny, ws)
    check s.count("file") == 0
    check s.count("activity") == 0
    # and the connection is usable afterwards
    s.db.exec(sql"create table coords(x)")

suite "import: segments":
  test "the ride's segments are stored in order, covering every coordinate":
    let s = openStore(tempDb("segments"))
    defer: s.close()
    discard s.importPath(ride)
    check s.db.getValue(sql"select min(n) || '-' || max(n) from segment") == "0-19"
    check s.db.getValue(sql"""select count(*) from segment a join segment b
      on b.activity_id = a.activity_id and b.n = a.n + 1
      where b.start_t <= a.end_t""") == "0"
    check s.db.getValue(sql"""select count(*) from coords c where not exists (
      select 1 from segment g where g.activity_id = c.activity_id
        and c.t between g.start_t and g.end_t)""") == "0"
    # the time between segments is the time paused
    check s.db.getValue(sql"""select sum(b.start_t - a.end_t) from segment a
      join segment b on b.activity_id = a.activity_id and b.n = a.n + 1""") == "412"

  test "the coordinates of one segment are a range of the key":
    let s = openStore(tempDb("segrange"))
    defer: s.close()
    discard s.importPath(ride)
    check s.db.getValue(sql"""select sum(cnt) from (
      select (select count(*) from coords c where c.activity_id = g.activity_id
        and c.t between g.start_t and g.end_t) as cnt from segment g)""") == "2099"

  test "a multisport file has segments for each activity":
    let s = openStore(tempDb("segmulti"))
    defer: s.close()
    let (r, _) = s.importPath(multisport)
    check r.segments == s.count("segment")
    check s.db.getValue(sql"select count(distinct activity_id) from segment") == "7"
