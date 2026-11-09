import std/[options, strutils, unittest]
import ../support/shims
import nimchoo/packages/db/store
import nimchoo/core/errors
import nimchoo/packages/download/fetch
import nimchoo/landmark/landmarks
import nimchoo/names/[climb, climbpick, countries]
import ../support/[namesdata, userdata]

# a climb in Chile that goes up towards the Paso Los Libertadores (-70.12, -32.83): from 600 m below to the pass
let lons = @[-70.14, -70.135, -70.13, -70.125, -70.12]
let lats = @[-32.83, -32.83, -32.83, -32.83, -32.83]

proc world(
    name: string, extra: seq[string] = @[]
): tuple[net: Net, names: Names, st: Store, events: ref seq[DownloadEvent]] =
  let net = Net(
    chile:
      (@[santiago, sanCristobal, pass, lake, road, barrio] & extra).join("\n") & "\n"
  )
  let (st, dir) = fresh(name)
  var events: ref seq[DownloadEvent]
  new(events)
  let sink = proc(ev: DownloadEvent) {.closure, raises: [].} =
    events[].add ev
  (net, newNames(st, dir, envOf(net), sink), st, events)

suite "names: naming a route":
  test "a climb that tops out at a pass is named for the pass":
    let w = world("pass")
    defer:
      w.st.close()
    let r = nameClimb(w.names, lons, lats)
    check r.isSome and r.get.name == "Paso Los Libertadores" and r.get.kind == pkPass
    check r.get.distanceM < 5.0
    # the second time nothing is fetched again
    let gets = w.net.gets.len
    check nameClimb(w.names, lons, lats).isSome
    check w.net.gets.len == gets

  test "a climb that ends at a place is named for it; one a few km away is near it":
    let w = world("town")
    defer:
      w.st.close()
    let ends = nameClimb(w.names, @[-70.54, -70.53, -70.52], @[-33.36, -33.355, -33.35])
      # Lo Barnechea is at -70.52, -33.35
    check ends.isSome and ends.get.name == "Lo Barnechea" and ends.get.tier == 1
    let away = nameClimb(w.names, @[-70.56, -70.555, -70.55], @[-33.35, -33.35, -33.35])
      # about 3 km west of it
    check away.isSome and away.get.name == "near Lo Barnechea" and away.get.tier == 3

  test "a climb with nothing near it is no name, and a position in the sea is nowhere":
    let w = world("nothing")
    defer:
      w.st.close()
    check nameClimb(w.names, @[-71.0, -71.01], @[-40.0, -40.01]).isNone
    check nameClimb(w.names, @[-120.0, -120.01], @[-30.0, -30.01]).isNone
    check nameClimb(w.names, @[], @[]).isNone

  test "without the network it is an error, and nothing is kept":
    let (st, dir) = fresh("offline")
    defer:
      st.close()
    var env = envOf(Net())
    env.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
      FetchResult(ok: false, message: "cannot reach download.geonames.org")
    let names = newNames(st, dir, env, silent())
    expect DownloadError:
      discard nameClimb(names, lons, lats)
    check st.count("coverage") == 0 and st.count("feature") == 0

  test "offline: the answer is nothing, with no fetch and no error":
    let w = world("offlineflag")
    defer:
      w.st.close()
    var names = w.names
    names.offline = true
    check nameClimb(names, lons, lats).isNone
    check w.net.gets.len == 0

  test "a landmark of your own holding the top comes before the pass, and works offline":
    let w = world("landmark")
    defer:
      w.st.close()
    addLandmark(w.st, "Mi paso", -70.12, -32.83, 1000.0)
    let r = nameClimb(w.names, lons, lats)
    check r.isSome and r.get.name == "Mi paso" and r.get.kind == pkLandmark and
      r.get.tier == 0
    check w.net.gets.len == 0 # (nothing was fetched: the landmark answered first)
    var names = w.names
    names.offline = true
    check nameClimb(names, lons, lats).get.name == "Mi paso"
    # a climb that tops out outside the circle is named as before
    let elsewhere =
      nameClimb(w.names, @[-70.54, -70.53, -70.52], @[-33.36, -33.355, -33.35])
    check elsewhere.get.name == "Lo Barnechea"
