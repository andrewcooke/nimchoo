import ../support/arrays
import nimchoo/packages/importer/coord
import nimchoo/packages/fit/time
import nimchoo/packages/db/statement
import std/[strutils, unittest]
import ../support/shims
import nimchoo/packages/db/store
import nimchoo/packages/download/fetch
import nimchoo/core/errors
import nimchoo/packages/importer/naming
import nimchoo/packages/names/countries
import ../support/namesdata

const home = (-70.65, -33.46) # Santiago
const barnechea = (-70.52, -33.35) # Lo Barnechea, about 18 km away

proc addActivity(
    s: Store, tag: string, startT: int, points: openArray[(float, float)]
) =
  ## An activity along the points (lon, lat), a position about every 50 m.
  let u = s.db.scalar(int64, "select id from user where name = 'default'")
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, 0)",
    userId = u,
    name = tag,
    sha256 = tag,
  )
  let f = s.db.scalar(int64, "select max(id) from file")
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t) values (:fileId, 0, :startT, :endT)",
    fileId = f,
    startT = startT,
    endT = startT + 10000,
  )
  let a = s.db.scalar(int64, "select max(id) from activity")
  var t = startT
  var coords: seq[Coord]
  for k in 0 ..< points.high:
    let (x0, y0) = points[k]
    let (x1, y1) = points[k + 1]
    let n = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / 0.0005))
    for i in 0 ..< n:
      coords.add Coord(
        t: UnixTime(t),
        lon: x0 + (x1 - x0) * i.float / n.float,
        lat: y0 + (y1 - y0) * i.float / n.float,
      )
      inc t
  s.db.putTrack(a, coords)

proc world(name: string): tuple[names: Names, st: Store, net: Net] =
  let net = Net(chile: @[santiago, sanCristobal, pass, lake, barrio].join("\n") & "\n")
  let (st, dir) = fresh(name)
  (newNames(st, dir, envOf(net), silent()), st, net)

suite "import: naming the activities":
  test "activities with no name get a start and a name, once; the order is the order they began":
    let w = world("once")
    defer:
      w.st.close()
    w.st.addActivity("later", 2_000_000, [home, barnechea, home])
    w.st.addActivity("earlier", 1_000_000, [home, barnechea])
    check pending(w.st) == @[2'i64, 1'i64]
    var seen: seq[int]
    let r = ensureActivityNames(
      w.st,
      w.names,
      proc(done, total: int) {.closure, raises: [].} =
        seen.add done
      ,
    )
    check r == Named(total: 2, named: 2)
    check seen == @[1, 2]
    check w.st.db.scalar(string, "select name from activity where id = 1") ==
      "Lo Barnechea and back"
    check w.st.db.scalar(string, "select name from activity where id = 2") ==
      "to Lo Barnechea"
    check w.st.db.scalar(string, "select start_place from activity where id = 2") ==
      "Santiago"
    check pending(w.st).len == 0
    let gets = w.net.gets.len
    check ensureActivityNames(w.st, w.names) == Named() # nothing left to do
    check w.net.gets.len == gets
  test "an activity with nothing to say is '' (named: not null), and one with only a start is counted so":
    let w = world("nothing")
    defer:
      w.st.close()
    w.st.addActivity("nowhere", 1_000_000, [(-71.0, -40.0), (-71.01, -40.0)])
      # nothing near
    w.st.addActivity("short", 2_000_000, [home, (-70.65, -33.455), home])
      # local: "at Santiago"
    let r = ensureActivityNames(w.st, w.names)
    check r == Named(total: 2, named: 1, nothing: 1)
    check w.st.db.scalar(
      string, "select coalesce(name, '-') from activity where id = 1"
    ) == ""
    check w.st.db.scalar(string, "select name from activity where id = 2") ==
      "at Santiago"
  test "a stretch with a bad GPS fix is counted, with its file; the other stretch still names the ride":
    let w = world("gps errors")
    defer:
      w.st.close()
    w.st.addActivity("a", 1_000_000, [home, barnechea, home])
    let u = w.st.db.scalar(int64, "select id from user where name = 'default'")
    w.st.db.execute(
      "insert into seen_file(user_id, path, size, mtime, file_id) values (:userId, '/rides/a.fit', 1, 1, 1)",
      userId = u,
    )
    # (the route: the loop, as one stretch, and a stretch with a fix on the other side of the world: it ends the route,
    # so the ride is "one way" to it, and the search at the turning point is the one that cannot be made)
    var good = ""
    for k, (x, y) in [home, (-70.40, -33.46), (-70.40, -33.35), (-70.65, -33.35), home]:
      good.add (if k > 0: ", " else: "") & $x & " " & $y
    w.st.db.execute(
      "insert into route(activity_id, geom) values (1, GeomFromText(:wkt, 4326))",
      wkt = "MULTILINESTRING((" & good & "), (-70.45 -33.40, 110 10))",
    )
    let r = ensureActivityNames(w.st, w.names)
    check r.gpsErrors == @[GpsErrors(where: "/rides/a.fit", searches: 1)]
    check r.gpsErrorCount == 1
  test "no positions at all: '' too":
    let w = world("nogps")
    defer:
      w.st.close()
    let u = w.st.db.scalar(int64, "select id from user where name = 'default'")
    w.st.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, 'x', 'x', 0)",
      userId = u,
    )
    w.st.db.execute(
      "insert into activity(file_id, session, start_t, end_t) values (1, 0, 1, 2)"
    )
    check ensureActivityNames(w.st, w.names).nothing == 1
    check w.st.db.scalar(string, "select coalesce(name, '-') from activity") == ""
  test "offline with nothing loaded: nothing is fetched, the activity is left (null), and a later run names it":
    let w = world("offline")
    defer:
      w.st.close()
    w.st.addActivity("a", 1_000_000, [home, barnechea, home])
    var names = w.names
    names.offline = true
    let r = ensureActivityNames(w.st, names)
    check r.left == 1 and r.nothing == 0 and r.named == 0
    check r.leftText.contains("1 left unnamed")
    check w.net.gets.len == 0
    check pending(w.st) == @[1'i64] # (not stored as "nothing")
    check ensureActivityNames(w.st, w.names).named == 1
      # (a run that may use the network)
    check pending(w.st).len == 0
  test "offline uses the places already loaded":
    let w = world("offline-loaded")
    defer:
      w.st.close()
    w.st.addActivity("first", 1_000_000, [home, barnechea, home])
    check ensureActivityNames(w.st, w.names).named == 1
    let fetched = w.net.gets.len
    check fetched > 0
    w.st.addActivity("second", 2_000_000, [home, barnechea, home])
    var names = w.names
    names.offline = true
    let r = ensureActivityNames(w.st, names)
    check r.named == 1 and r.left == 0
    check w.net.gets.len == fetched
  test "no network: an error, and what was named so far stays; the rest are named next time":
    let (st, dir) = fresh("nonet")
    defer:
      st.close()
    st.addActivity("a", 1_000_000, [home, barnechea, home])
    var env = envOf(Net())
    env.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
      FetchResult(ok: false, message: "cannot reach download.geonames.org")
    expect DownloadError:
      discard ensureActivityNames(st, newNames(st, dir, env, silent()))
    check pending(st) == @[1'i64]
    let good = Net(chile: @[santiago, barrio].join("\n") & "\n")
    check ensureActivityNames(st, newNames(st, dir, envOf(good), silent())).named == 1
    check pending(st).len == 0
