import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/climbs/naming
import nimchoo/db/store
import nimchoo/download/fetch
import nimchoo/modules
import nimchoo/names/countries
import ../support/namesdata

proc sectorAt(s: Store, lons: openArray[float], lat: float) =
  ## A sector along a line of latitude, with altitudes that rise.
  var pts: seq[string]
  for i, lon in lons: pts.add $lon & " " & $lat & " " & $(100 + i * 10)
  s.db.exec(sql"insert into sector(length_m, gain_m, gradient, route) values (1000, 100, 5, GeomFromText(?, 4326))",
            "LINESTRING Z(" & pts.join(", ") & ")")

proc world(name: string): tuple[net: Net, names: Names, st: Store] =
  let net = Net(chile: @[santiago, sanCristobal, pass, barrio].join("\n") & "\n")
  let top = getTempDir() / "nch-test-climbs-naming" / name
  removeDir(top)
  let st = openStore(top / "x.db", allFragments)
  (net, newNames(st, top / "data", envOf(net), silent()), st)

suite "climbs: naming the sectors":
  test "a sector is named from the places near it, once":
    let w = world("once")
    defer: w.st.close()
    sectorAt(w.st, [-70.14, -70.135, -70.13, -70.125, -70.12], -32.83)       # tops out at the pass
    sectorAt(w.st, [-71.0, -71.01], -40.0)                                  # nothing near it
    let r = ensureSectorNames(w.st, w.names)
    check r == Named(named: 1, nothing: 1, pending: 0)
    check w.st.db.getValue(sql"select name from sector where id = 1") == "Paso Los Libertadores"
    check w.st.db.getValue(sql"select name from sector where id = 2") == ""          # (null)
    check w.st.db.getValue(sql"select count(*) from sector where name_checked = 1") == "2"
    let gets = w.net.gets.len
    check ensureSectorNames(w.st, w.names) == Named()                        # nothing left to look at
    check w.net.gets.len == gets

  test "without the network nothing is marked as looked at, and the rest wait":
    let top = getTempDir() / "nch-test-climbs-naming" / "offline"
    removeDir(top)
    let st = openStore(top / "x.db", allFragments)
    defer: st.close()
    var env = envOf(Net())
    env.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
      FetchResult(ok: false, message: "cannot reach download.geonames.org")
    let names = newNames(st, top / "data", env, silent())
    sectorAt(st, [-70.14, -70.12], -32.83)
    sectorAt(st, [-70.14, -70.12], -32.9)
    check ensureSectorNames(st, names) == Named(pending: 2)
    check st.db.getValue(sql"select count(*) from sector where name_checked = 0") == "2"

  test "a sector added later is named on the next pass":
    let w = world("later")
    defer: w.st.close()
    sectorAt(w.st, [-70.14, -70.12], -32.83)
    check ensureSectorNames(w.st, w.names).named == 1
    sectorAt(w.st, [-70.54, -70.52], -33.35)
    let r = ensureSectorNames(w.st, w.names)
    check r.named == 1
    check w.st.db.getValue(sql"select name from sector where id = 2") == "Lo Barnechea"          # (it ends there)
