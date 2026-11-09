import std/[math, options, strutils, unittest]
import ../support/shims
import nimchoo/packages/db/store
import nimchoo/packages/download/fetch
import nimchoo/core/errors
import nimchoo/landmark/landmarks
import nimchoo/names/[activity, countries, lookup, shape]
import ../support/namesdata

func f(name, code: string, isPlace = false): Found =
  Found(name: name, code: code, isPlace: isPlace)

proc path(
    points: openArray[(float, float)], step = 0.0005
): tuple[lons, lats: seq[float]] =
  ## A route through the points (lon, lat), a position about every 50 m.
  for k in 0 ..< points.high:
    let (x0, y0) = points[k]
    let (x1, y1) = points[k + 1]
    let n = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / step))
    for i in 0 ..< n:
      result.lons.add x0 + (x1 - x0) * i.float / n.float
      result.lats.add y0 + (y1 - y0) * i.float / n.float
  result.lons.add points[^1][0]
  result.lats.add points[^1][1]

proc world(name: string): tuple[names: Names, st: Store, net: Net] =
  let net = Net(chile: @[santiago, sanCristobal, pass, lake, barrio].join("\n") & "\n")
  let (st, dir) = fresh(name)
  (newNames(st, dir, envOf(net), silent()), st, net)

# Santiago (-70.65, -33.46) to Lo Barnechea (-70.52, -33.35), about 18 km
const home = (-70.65, -33.46)
const barnechea = (-70.52, -33.35)

suite "names: an activity's name, the pieces":
  test "the kinds of destination":
    check destKind(f("Santiago", "PPLC", true)) == 1
    check destKind(f("Lo Barnechea", "PPLX", true)) == 2
    check destKind(f("Parque", "PRK")) == 3 and destKind(f("Reserva", "RESN")) == 3
    check destKind(f("Laguna", "LK")) == 4
    check destKind(f("Cajón del Maipo", "VAL")) == 5
    check destKind(f("El Toyo", "FRM")) == 6
    check destKind(f("Viejo", "PPLQ", true)) == 0 and destKind(f("Paso", "PASS")) == 0 and
      destKind(f("Ruta", "RD")) == 0
  test "the first kind wins, however far; the closest within a kind":
    let found = @[
      (f("Cerca", "FRM"), 100.0),
      (f("Barrio", "PPLX", true), 600.0),
      (f("Lejos", "PPL", true), 9000.0),
      (f("Otro", "PPL", true), 8000.0),
    ]
    check choose(found).get.name == "Otro"
      # a town beats a nearer section and a nearer farm
    check choose(found[0 .. 1]).get.name == "Barrio"
    check choose(found[0 .. 0]).get.name == "Cerca"
    check choose(@[(f("Paso", "PASS"), 5.0)]).isNone
    check choose(newSeq[(Found, float)]()).isNone
  test "the start place: plain within 5 km, near within 20 km, none beyond; only populated places":
    check startText(
      @[(f("Santiago", "PPLC", true), 3000.0), (f("Cerro", "HLL"), 100.0)]
    ) == "Santiago"
    check startText(@[(f("Santiago", "PPLC", true), 5000.0)]) == "Santiago"
    check startText(@[(f("Santiago", "PPLC", true), 5001.0)]) == "near Santiago"
    check startText(@[(f("Santiago", "PPLC", true), 20001.0)]) == ""
    check startText(
      @[(f("Viejo", "PPLQ", true), 10.0), (f("Santiago", "PPL", true), 4000.0)]
    ) == "Santiago"
    check startText(newSeq[(Found, float)]()) == ""
    check startText(
      @[(f("Lejos", "PPL", true), 9000.0), (f("Cerca", "PPLX", true), 900.0)]
    ) == "Cerca"
  test "the forms":
    check nameFor(skOutAndBack, "S", "El Toyo", "V") == "El Toyo and back"
    check nameFor(skOneWay, "S", "Lo Barnechea", "V") == "to Lo Barnechea"
    check nameFor(skLoop, "S", "D", "El Peñón") == "loop via El Peñón"
    check nameFor(skMixed, "S", "D", "Recoleta") == "around Recoleta"
    check nameFor(skLocal, "Santiago", "", "") == "at Santiago"
    check nameFor(skLocal, "near Santiago", "", "") == "near Santiago"
    check nameFor(skLocal, "", "", "") == ""
    check nameFor(skOutAndBack, "S", "", "V") == "" and
      nameFor(skLoop, "S", "D", "") == ""

suite "names: an activity's name, from a route":
  test "out and back to a place: '<destination> and back', and the start":
    let w = world("outback")
    defer:
      w.st.close()
    let r = path([home, barnechea, home])
    let got = nameActivity(w.names, [(r.lons, r.lats)])
    check got.shape == skOutAndBack
    check got.name == "Lo Barnechea and back" and got.start == "Santiago"
  test "one way: 'to <destination>'":
    let w = world("oneway")
    defer:
      w.st.close()
    let r = path([home, barnechea])
    let got = nameActivity(w.names, [(r.lons, r.lats)])
    check got.shape == skOneWay and got.name == "to Lo Barnechea" and
      got.start == "Santiago"
  test "a loop: 'loop via <feature>', a feature well away from the start along the route":
    let w = world("loop")
    defer:
      w.st.close()
    # east, north to Lo Barnechea's latitude, west along it (past Lo Barnechea), and south home
    let r = path([home, (-70.40, -33.46), (-70.40, -33.35), (-70.65, -33.35), home])
    let got = nameActivity(w.names, [(r.lons, r.lats)])
    check got.shape == skLoop
    check got.name == "loop via Lo Barnechea"
  test "a stretch with a bad fix is left out, and costs no download; the others are still searched":
    let r = path([home, (-70.40, -33.46), (-70.40, -33.35), (-70.65, -33.35), home])
    let clean = world("loop clean")
    defer:
      clean.st.close()
    discard nameActivity(clean.names, [(r.lons, r.lats)])
    let w = world("loop bad fix")
    defer:
      w.st.close()
    # (a fix at the other side of the world, between two real ones)
    let bad: Part = (@[-70.45, 110.0, -70.46], @[-33.40, 10.0, -33.41])
    let got = nameActivity(w.names, [(r.lons, r.lats), bad])
    check got.gpsErrors == 1
    check w.net.gets.len == clean.net.gets.len
  test "a short ride is 'at <start>'":
    let w = world("local")
    defer:
      w.st.close()
    let r = path([home, (-70.65, -33.455), (-70.645, -33.455), home])
    let got = nameActivity(w.names, [(r.lons, r.lats)])
    check got.shape == skLocal and got.name == "at Santiago" and got.start == "Santiago"
  test "a landmark at the turning point comes first, and names the ride without any fetch":
    let w = world("landmark")
    defer:
      w.st.close()
    addLandmark(w.st, "Mi destino", barnechea[0], barnechea[1], 1500.0)
    var names = w.names
    names.offline = true # (no names at all: the landmark still answers)
    let r = path([home, barnechea, home])
    let got = nameActivity(names, [(r.lons, r.lats)])
    check got.name == "Mi destino and back" and got.start == ""
    check w.net.gets.len == 0
  test "a landmark along a loop is 'loop via <landmark>'":
    let w = world("loop landmark")
    defer:
      w.st.close()
    addLandmark(w.st, "Mi cuesta", -70.40, -33.40, 1000.0)
    var names = w.names
    names.offline = true
    let r = path([home, (-70.40, -33.46), (-70.40, -33.35), (-70.65, -33.35), home])
    check nameActivity(names, [(r.lons, r.lats)]).name == "loop via Mi cuesta"
  test "offline: no start, no name (nothing is fetched)":
    let w = world("offline")
    defer:
      w.st.close()
    var names = w.names
    names.offline = true
    let r = path([home, barnechea, home])
    let got = nameActivity(names, [(r.lons, r.lats)])
    check got.name == "" and got.start == "" and got.shape == skOutAndBack
    check w.net.gets.len == 0
  test "no positions: nothing":
    let w = world("none")
    defer:
      w.st.close()
    check nameActivity(w.names, newSeq[Part]()) == ActivityNames()
  test "no network: an error that says why":
    let (st, dir) = fresh("nonet")
    defer:
      st.close()
    var env = envOf(Net())
    env.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
      FetchResult(ok: false, message: "cannot reach download.geonames.org")
    let names = newNames(st, dir, env, silent())
    let r = path([home, barnechea, home])
    expect DownloadError:
      discard nameActivity(names, [(r.lons, r.lats)])
