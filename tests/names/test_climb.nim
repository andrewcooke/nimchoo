import std/[strutils, unittest]
import nimchoo/db/store
import nimchoo/download/fetch
import nimchoo/names/[climb, climbpick, countries]
import ../support/[namesdata, userdata]

# a climb in Chile that goes up towards the Paso Los Libertadores (-70.12, -32.83): from 600 m below to the pass
let lons = @[-70.14, -70.135, -70.13, -70.125, -70.12]
let lats = @[-32.83, -32.83, -32.83, -32.83, -32.83]

proc world(name: string, extra: seq[string] = @[]): tuple[net: Net, names: Names, st: Store, events: ref seq[DownloadEvent]] =
  let net = Net(chile: (@[santiago, sanCristobal, pass, lake, road, barrio] & extra).join("\n") & "\n")
  let (st, dir) = fresh(name)
  var events: ref seq[DownloadEvent]
  new(events)
  let sink = proc(ev: DownloadEvent) {.closure, raises: [].} = events[].add ev
  (net, newNames(st, dir, envOf(net), sink), st, events)

suite "names: naming a route":
  test "a climb that tops out at a pass is named for the pass":
    let w = world("pass")
    defer: w.st.close()
    let r = nameClimb(w.names, lons, lats)
    check r.status == nsNamed and r.pick.name == "Paso Los Libertadores" and r.pick.kind == pkPass
    check r.pick.distanceM < 5.0
    # the second time nothing is fetched again
    let gets = w.net.gets.len
    check nameClimb(w.names, lons, lats).status == nsNamed
    check w.net.gets.len == gets

  test "a climb that ends at a place is named for it; one a few km away is near it":
    let w = world("town")
    defer: w.st.close()
    let ends = nameClimb(w.names, @[-70.54, -70.53, -70.52], @[-33.36, -33.355, -33.35])      # Lo Barnechea is at -70.52, -33.35
    check ends.status == nsNamed and ends.pick.name == "Lo Barnechea" and ends.pick.tier == 1
    let away = nameClimb(w.names, @[-70.56, -70.555, -70.55], @[-33.35, -33.35, -33.35])      # about 3 km west of it
    check away.status == nsNamed and away.pick.name == "near Lo Barnechea" and away.pick.tier == 3

  test "a climb with nothing near it is no name, and a position in the sea is nowhere":
    let w = world("nothing")
    defer: w.st.close()
    check nameClimb(w.names, @[-71.0, -71.01], @[-40.0, -40.01]).status == nsNothing
    check nameClimb(w.names, @[-120.0, -120.01], @[-30.0, -30.01]).status == nsNothing
    check nameClimb(w.names, @[], @[]).status == nsNothing

  test "without the network the answer is later, and nothing is marked as looked at":
    let (st, dir) = fresh("offline")
    defer: st.close()
    var env = envOf(Net())
    env.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
      FetchResult(ok: false, message: "cannot reach download.geonames.org")
    let names = newNames(st, dir, env, silent())
    check nameClimb(names, lons, lats).status == nsLater
    check st.count("name_source") == 0 and st.count("feature") == 0
