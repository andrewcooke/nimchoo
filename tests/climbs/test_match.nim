import std/[math, options, unittest]
import nimchoo/packages/climbs/match
import nimchoo/packages/geo/geo
import ../support/paths

proc noisy(p: Path, wander: float): Path =
  ## The same route as a gps would give it: the position wanders slowly by up to `wander` metres
  ## and jitters by up to a metre (a simple generator).
  result = p
  var x = 987654321'u32
  for i in 0 ..< p.len:
    x = x * 1664525'u32 + 1013904223'u32
    let dx =
      wander * sin(float(i) / 23.0) + (float(x shr 8) / float(1 shl 24) * 2.0 - 1.0)
    x = x * 1664525'u32 + 1013904223'u32
    let dy =
      wander * sin(float(i) / 17.0) + (float(x shr 8) / float(1 shl 24) * 2.0 - 1.0)
    let (lon, lat) = pr.unproject(
      XY(
        x: pr.project(p.lon[i], p.lat[i]).x + dx,
        y: pr.project(p.lon[i], p.lat[i]).y + dy,
      )
    )
    result.lon[i] = lon
    result.lat[i] = lat

let sector = pathOf([(0.0, 0.0), (2000.0, 0.0)], 10.0) # 2 km due east

suite "climbs: a ride over a sector":
  test "the times are where the gates are crossed":
    let ride =
      pathOf([(-500.0, 0.0), (2500.0, 0.0)], 5.0, speed = 5.0, t0 = 1000.0, slope = 0.1)
    let es = overPaths(sector, ride)
    check es.len == 1
    check abs(es[0].startT - 1100.0) < 0.01 # 500 m at 5 m/s
    check abs(es[0].finishT - 1500.0) < 0.01
    check abs(es[0].elapsed - 400.0) < 0.01
    check abs(es[0].startDist - 500.0) < 0.1

  test "the ride need not be on the exact route, but within the gates":
    for off in [-20.0, 0.0, 15.0, 24.0]:
      let ride = pathOf([(-500.0, off), (2500.0, off)], 5.0, speed = 5.0, t0 = 1000.0)
      check overPaths(sector, ride).len == 1
    for off in [30.0, 40.0, -60.0]:
      let ride = pathOf([(-500.0, off), (2500.0, off)], 5.0, speed = 5.0, t0 = 1000.0)
      check overPaths(sector, ride).len == 0

  test "gps noise does not matter":
    let ride =
      noisy(pathOf([(-500.0, 0.0), (2500.0, 0.0)], 5.0, speed = 5.0, t0 = 1000.0), 10.0)
    let es = overPaths(sector, ride)
    check es.len == 1
    check abs(es[0].elapsed - 400.0) < 8.0 # (a few metres at each gate, at 5 m/s)

  test "the wrong way, or not the whole way, is not a pass":
    check overPaths(sector, pathOf([(2500.0, 0.0), (-500.0, 0.0)], 5.0, speed = 5.0)).len ==
      0
    check overPaths(sector, pathOf([(100.0, 0.0), (2500.0, 0.0)], 5.0, speed = 5.0)).len ==
      0 # starts late
    check overPaths(sector, pathOf([(-500.0, 0.0), (1900.0, 0.0)], 5.0, speed = 5.0)).len ==
      0 # stops early
    check overPaths(
      sector, pathOf([(-500.0, 500.0), (2500.0, 500.0)], 5.0, speed = 5.0)
    ).len == 0 # elsewhere

  test "the ground covered must be within 5 % of the sector's length":
    # from the start gate to the finish gate by way of a point y metres to the side
    proc via(y: float): Path =
      pathOf(
        [(-500.0, 0.0), (0.0, 0.0), (1000.0, y), (2000.0, 0.0), (2500.0, 0.0)],
        5.0,
        speed = 5.0,
      )

    check overPaths(sector, via(150.0)).len == 1 # 2022 m: 1 % too long
    check overPaths(sector, via(300.0)).len == 1 # 2088 m: 4.4 %
    check overPaths(sector, via(500.0)).len == 0 # 2236 m: 12 %

  test "laps are separate passes; the way back is not one":
    # out, back, out again: the first and the last are passes
    let ride = pathOf(
      [(-500.0, 0.0), (2500.0, 0.0), (-500.0, 0.0), (2500.0, 0.0)],
      5.0,
      speed = 5.0,
      t0 = 0.0,
    )
    let es = overPaths(sector, ride)
    check es.len == 2
    check es[0].startT < es[0].finishT and es[0].finishT < es[1].startT
    check abs(es[0].elapsed - 400.0) < 0.01 and abs(es[1].elapsed - 400.0) < 0.01

  test "a ride that does not go near, and degenerate routes":
    check overPaths(
      sector, pathOf([(0.0, 10000.0), (2000.0, 10000.0)], 5.0, speed = 5.0)
    ).len == 0
    check overPaths(Path(), pathOf([(0.0, 0.0), (10.0, 0.0)], 5.0)).len == 0
    check overPaths(sector, Path()).len == 0
    check overPaths(
      pathOf([(0.0, 0.0), (0.0, 0.0)], 5.0), pathOf([(-5.0, 0.0), (5.0, 0.0)], 5.0)
    ).len == 0

  test "where the road folds back through the start gate, the first crossing is the start":
    # east 60 m, a hairpin back west across the gate (at 130 m along the road), then a long way east
    let road = [
      (0.0, 0.0),
      (60.0, 0.0),
      (60.0, 10.0),
      (-50.0, 10.0),
      (-50.0, 40.0),
      (3900.0, 40.0),
    ]
    let switchback = pathOf(road, 10.0)
    let ride = pathOf(
      @[(-100.0, 0.0)] & @road & @[(3950.0, 40.0)], 5.0, speed = 5.0, t0 = 1000.0
    ) # starts 100 m before the gate and goes on past the finish gate
    let es = overPaths(switchback, ride)
    check es.len == 1
    check abs(es[0].startT - 1020.0) < 0.5
      # the first crossing, not the one coming back at 1048 s
    check abs(es[0].startDist - 100.0) < 1.0

  test "a climb that bends is matched along its bend":
    let bend = pathOf([(0.0, 0.0), (1000.0, 0.0), (1000.0, 1000.0)], 10.0)
      # east, then north
    let ride = pathOf(
      [(-300.0, 0.0), (1000.0, 0.0), (1000.0, 1300.0)], 5.0, speed = 4.0, t0 = 0.0
    )
    let es = overPaths(bend, ride)
    check es.len == 1
    check abs(es[0].elapsed - 500.0) < 0.5 # 2000 m at 4 m/s

suite "climbs: reading a stored route":
  test "the positions of a LINESTRING Z, altitudes ignored":
    let p =
      parseLineString("LINESTRING Z(-70.1 -32.8 100, -70.2 -32.9 110.5, -70.3 -33 120)")
    check p.isSome
    check p.get.lon == @[-70.1, -70.2, -70.3] and p.get.lat == @[-32.8, -32.9, -33.0]
  test "extra spaces are fine":
    check parseLineString("LINESTRING Z( 1 2 3 ,  4   5 6 )").get.len == 2
  test "anything that is not a route is none, never an empty route":
    for bad in [
      "",
      "LINESTRING EMPTY",
      "LINESTRING Z(1 2 3)", # (one point)
      "LINESTRING Z(1 2 3, 4)", # a point with one number
      "LINESTRING Z(1 2 3, a b c)",
      "LINESTRING Z(1 2 3, 4 nan 6)",
      "LINESTRING Z(1 2 3, inf 5 6)",
      "POINT(1 2",
      "LINESTRING Z(1 2 3, 4 5 6",
      "LINESTRING Z(, )",
    ]:
      check parseLineString(bad).isNone

suite "climbs: the gates of a sector, for drawing":
  test "a gate is across the route, 25 m each side, at its first and last points":
    let g = gateLines(sector).get # (2 km due east: the gates run north and south)
    for gate in [g.start, g.finish]:
      check abs(gate[0].lon - gate[1].lon) < 1e-9
        # (the same longitude: across a route that runs east)
      let across = haversine(gate[0].lon, gate[0].lat, gate[1].lon, gate[1].lat)
      check abs(across - 50.0) < 0.1
    check abs(g.start[0].lon - sector.lon[0]) < 1e-9
    check abs(g.finish[0].lon - sector.lon[^1]) < 1e-9
    check abs((g.start[0].lat + g.start[1].lat) / 2 - sector.lat[0]) < 1e-9
  test "a sector with no length has no gates":
    check gateLines(Path()).isNone
