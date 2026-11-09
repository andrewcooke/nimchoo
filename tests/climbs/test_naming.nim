import nimchoo/packages/db/statement
import std/[os, strutils, unittest]
import ../support/shims
import nimchoo/packages/climbs/naming
import nimchoo/packages/db/store
import nimchoo/packages/download/fetch
import nimchoo/core/errors
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/names/countries
import ../support/namesdata

proc sectorAt(s: Store, lons: openArray[float], lat: float) =
  ## A sector along a line of latitude, with altitudes that rise.
  var pts: seq[string]
  for i, lon in lons:
    pts.add $lon & " " & $lat & " " & $(100 + i * 10)
  s.db.execute(
    "insert into sector(length_m, gain_m, gradient, route) values (1000, 100, 5, GeomFromText(:wkt, 4326))",
    wkt = "LINESTRING Z(" & pts.join(", ") & ")",
  )

proc world(name: string): tuple[net: Net, names: Names, st: Store] =
  let net = Net(chile: @[santiago, sanCristobal, pass, barrio].join("\n") & "\n")
  let top = getTempDir() / "nch-test-climbs-naming" / name
  removeDir(top)
  let st = openStore(top / "x.db", allFragments, access = allAccess)
  (net, newNames(st, top / "data", envOf(net), silent()), st)

suite "climbs: naming the sectors":
  test "a sector is named from the places near it, once":
    let w = world("once")
    defer:
      w.st.close()
    sectorAt(w.st, [-70.14, -70.135, -70.13, -70.125, -70.12], -32.83)
      # tops out at the pass
    sectorAt(w.st, [-71.0, -71.01], -40.0) # nothing near it
    let r = ensureSectorNames(w.st, w.names)
    check r == Named(named: 1, nothing: 1)
    check w.st.db.scalar(string, "select name from sector where id = 1") ==
      "Paso Los Libertadores"
    check w.st.db.scalar(string, "select name from sector where id = 2") == ""
      # (looked at, nothing near)
    check w.st.db.scalar(int, "select count(*) from sector where name is null") == 0
    let gets = w.net.gets.len
    check ensureSectorNames(w.st, w.names) == Named() # nothing left to look at
    check w.net.gets.len == gets

  test "without the network it is an error, and the sectors stay unnamed (null) for the next time":
    let top = getTempDir() / "nch-test-climbs-naming" / "offline"
    removeDir(top)
    let st = openStore(top / "x.db", allFragments, access = allAccess)
    defer:
      st.close()
    var env = envOf(Net())
    env.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
      FetchResult(ok: false, message: "cannot reach download.geonames.org")
    let names = newNames(st, top / "data", env, silent())
    sectorAt(st, [-70.14, -70.12], -32.83)
    sectorAt(st, [-70.14, -70.12], -32.9)
    expect DownloadError:
      discard ensureSectorNames(st, names)
    check st.db.scalar(int, "select count(*) from sector where name is null") == 2
    # the network back: the same sectors are named now
    let good = Net(chile: @[santiago, sanCristobal, pass, barrio].join("\n") & "\n")
    let r = ensureSectorNames(st, newNames(st, top / "data", envOf(good), silent()))
    check r.named + r.nothing == 2
    check st.db.scalar(int, "select count(*) from sector where name is null") == 0

  test "a sector whose route cannot be read is not named, not marked as having no name near, and is said":
    # (the class: a failure is never stored as a result)
    let w = world("damaged")
    defer:
      w.st.close()
    w.st.db.execute(
      "insert into sector(length_m, gain_m, gradient) values (1000, 100, 5)"
    ) # (no route)
    sectorAt(w.st, [-70.14, -70.135, -70.13, -70.125, -70.12], -32.83)
    let r = ensureSectorNames(w.st, w.names)
    check r.damaged == @[1'i64] and r.named == 1 and r.nothing == 0
    check w.st.db.scalar(int, "select name is null from sector where id = 1") == 1
      # (still to do: not "")
    check w.st.db.scalar(string, "select name from sector where id = 2") ==
      "Paso Los Libertadores"
    # said again while it is still damaged, and named once the route is there
    check ensureSectorNames(w.st, w.names).damaged == @[1'i64]
    w.st.db.execute(
      "update sector set route = GeomFromText(:wkt, 4326) where id = 1",
      wkt = "LINESTRING Z(-70.14 -32.83 100, -70.12 -32.83 120)",
    )
    let again = ensureSectorNames(w.st, w.names)
    check again.damaged.len == 0 and again.named + again.nothing == 1
    check w.st.db.scalar(int, "select count(*) from sector where name is null") == 0

  test "a sector added later is named on the next pass":
    let w = world("later")
    defer:
      w.st.close()
    sectorAt(w.st, [-70.14, -70.12], -32.83)
    check ensureSectorNames(w.st, w.names).named == 1
    sectorAt(w.st, [-70.54, -70.52], -33.35)
    let r = ensureSectorNames(w.st, w.names)
    check r.named == 1
    check w.st.db.scalar(string, "select name from sector where id = 2") ==
      "Lo Barnechea" # (it ends there)
