import std/[strutils, unittest]
import nimchoo/db/store
import nimchoo/download/fetch
import nimchoo/names/[countries, lookup]
import ../support/[namesdata, userdata]

proc world(name: string): tuple[names: Names, st: Store] =
  let net = Net(chile: @[santiago, sanCristobal, pass, barrio].join("\n") & "\n")
  let (st, dir) = fresh(name)
  (newNames(st, dir, envOf(net), silent()), st)

suite "names: looking things up":
  test "a place in Chile is ready; the names of the country are then in the table":
    let w = world("ready")
    defer: w.st.close()
    let r = w.names.prepare(-70.64, -33.45)
    check r.status == rdReady and r.iso == "CL"
    check w.st.count("feature") == 4
  test "nothing to be had in the middle of the sea":
    let w = world("sea")
    defer: w.st.close()
    check w.names.prepare(-120.0, -30.0).status == rdNothing
  test "the features in the box round some positions, widened by the margin":
    let w = world("near")
    defer: w.st.close()
    let r = w.names.prepare(-70.64, -33.45)
    let found = w.names.featuresNear(r.iso, [-70.65, -70.62], [-33.46, -33.41])
    var names: seq[string]
    for f in found: names.add f.name
    check "Santiago" in names and "Cerro San Cristóbal" in names
    check "Paso Los Libertadores" notin names
    for f in found:
      if f.name == "Santiago": check f.isPlace and f.code == "PPLC"
      if f.name == "Cerro San Cristóbal": check not f.isPlace and f.code == "HLL"
    check w.names.featuresNear(r.iso, [], []).len == 0
