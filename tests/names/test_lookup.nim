import std/[math, strutils, unittest]
import nimchoo/db/store
import nimchoo/download/fetch
import nimchoo/names/[countries, features, lookup]
import ../support/[namesdata, userdata]

proc world(name: string): tuple[names: Names, st: Store, net: Net] =
  let net = Net(chile: @[santiago, sanCristobal, pass, barrio].join("\n") & "\n")
  let (st, dir) = fresh(name)
  (newNames(st, dir, envOf(net), silent()), st, net)

suite "names: looking things up":
  test "a place in Chile is ready; the cells round it are then in the table":
    let w = world("ready")
    defer:
      w.st.close()
    let r = w.names.prepare([-70.64], [-33.45])
    check r.status == rdReady
    check w.st.count("feature") == 3
      # Santiago, the hill, Lo Barnechea: the cell -71, -34
    check w.st.count("coverage") >= 1
  test "nothing to be had in the middle of the sea":
    let w = world("sea")
    defer:
      w.st.close()
    check w.names.prepare([-120.0], [-30.0]).status == rdNothing
    check w.st.count("coverage") == 0
  test "positions spread over more than a ride can: nothing is fetched (one bad fix once meant every country)":
    let w = world("wide")
    defer:
      w.st.close()
    check w.names.prepare([-70.64, 100.0], [-33.45, -33.45]).status == rdTooWide
    check w.names.prepare([-70.64, -70.64], [-33.45, 20.0]).status == rdTooWide
    check w.net.gets.len == 0 and w.st.count("coverage") == 0
    check w.names.prepare([-70.64, -68.0], [-33.45, -31.0]).status == rdReady
      # (a long day: a few degrees)
  test "offline: nothing, with no fetch":
    let w = world("offlineflag")
    defer:
      w.st.close()
    var names = w.names
    names.offline = true
    check names.prepare([-70.64], [-33.45]).status == rdNothing
    check w.net.gets.len == 0
  test "the features in the box round some positions, widened by the margin":
    let w = world("near")
    defer:
      w.st.close()
    discard w.names.prepare([-70.65, -70.62], [-33.46, -33.41])
    let found = w.names.featuresNear([-70.65, -70.62], [-33.46, -33.41])
    var names: seq[string]
    for f in found:
      names.add f.name
    check "Santiago" in names and "Cerro San Cristóbal" in names
    check "Paso Los Libertadores" notin names
    for f in found:
      if f.name == "Santiago":
        check f.isPlace and f.code == "PPLC"
      if f.name == "Cerro San Cristóbal":
        check not f.isPlace and f.code == "HLL"
    check w.names.featuresNear([], []).len == 0
  test "the box margin is metres: wider in degrees of longitude at high latitudes, and never past the whole circle":
    let eq = boxAround([0.0], [0.0], 6000.0)
    let north = boxAround([0.0], [60.0], 6000.0)
    check abs((eq.lat1 - eq.lat0) - (north.lat1 - north.lat0)) < 1e-9
      # the same in latitude
    check (north.lon1 - north.lon0) > 1.8 * (eq.lon1 - eq.lon0)
      # about twice as wide in longitude at 60 degrees
    let pole = boxAround([0.0], [89.95], 6000.0)
    check pole.lon1 - pole.lon0 >= 360.0 and pole.lat1 <= 90.0
    let south = boxAround([10.0], [-89.95], 6000.0)
    check south.lat0 >= -90.0
