import std/[strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/download/fetch
import nimchoo/errors
import nimchoo/importer/naming
import nimchoo/names/countries
import ../support/namesdata

const home = (-70.65, -33.46) # Santiago
const barnechea = (-70.52, -33.35) # Lo Barnechea, about 18 km away

proc addActivity(
    s: Store, tag: string, startT: int, points: openArray[(float, float)]
) =
  ## An activity along the points (lon, lat), a position about every 50 m.
  let u = s.db.getValue(sql"select id from user where name = 'default'")
  s.db.exec(
    sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
    u,
    tag,
    tag,
  )
  let f = s.db.getValue(sql"select max(id) from file")
  s.db.exec(
    sql"insert into activity(file_id, session, start_t, end_t) values (?, 0, ?, ?)",
    f,
    startT,
    startT + 10000,
  )
  let a = s.db.getValue(sql"select max(id) from activity")
  var t = startT
  for k in 0 ..< points.high:
    let (x0, y0) = points[k]
    let (x1, y1) = points[k + 1]
    let n = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / 0.0005))
    for i in 0 ..< n:
      s.db.exec(
        sql"insert into coords(activity_id, t, lon, lat) values (?, ?, ?, ?)",
        a,
        t,
        x0 + (x1 - x0) * i.float / n.float,
        y0 + (y1 - y0) * i.float / n.float,
      )
      inc t

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
    check w.st.db.getValue(sql"select name from activity where id = 1") ==
      "Lo Barnechea and back"
    check w.st.db.getValue(sql"select name from activity where id = 2") ==
      "to Lo Barnechea"
    check w.st.db.getValue(sql"select start_place from activity where id = 2") ==
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
    check w.st.db.getValue(sql"select coalesce(name, '-') from activity where id = 1") ==
      ""
    check w.st.db.getValue(sql"select name from activity where id = 2") == "at Santiago"
  test "no positions at all: '' too":
    let w = world("nogps")
    defer:
      w.st.close()
    let u = w.st.db.getValue(sql"select id from user where name = 'default'")
    w.st.db.exec(
      sql"insert into file(user_id, name, sha256, imported_at) values (?, 'x', 'x', 0)",
      u,
    )
    w.st.db.exec(
      sql"insert into activity(file_id, session, start_t, end_t) values (1, 0, 1, 2)"
    )
    check ensureActivityNames(w.st, w.names).nothing == 1
    check w.st.db.getValue(sql"select coalesce(name, '-') from activity") == ""
  test "offline: '' for all, no fetch, and they stay":
    let w = world("offline")
    defer:
      w.st.close()
    w.st.addActivity("a", 1_000_000, [home, barnechea, home])
    var names = w.names
    names.offline = true
    check ensureActivityNames(w.st, names).nothing == 1
    check w.net.gets.len == 0
    check pending(w.st).len == 0
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
