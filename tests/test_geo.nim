import std/[math, options, unittest]
import nimchoo/geo

proc xy(x, y: float): XY =
  XY(x: x, y: y)

suite "geo: the route grid":
  test "it gives the distance to the nearest point of the line when that is near, and none when it is not":
    let line = @[xy(0, 0), xy(1000, 0), xy(1000, 1000)]
    let g = newRouteGrid(line, 500.0)
    check abs(g.distanceWithin(xy(500, 30), 100.0).get - 30.0) < 1e-9
    check abs(g.distanceWithin(xy(1030, 500), 100.0).get - 30.0) < 1e-9
    check g.distanceWithin(xy(500, 300), 100.0).isNone
    check g.distanceWithin(xy(500, 300), 400.0).get == 300.0
    check newRouteGrid(@[], 500.0).distanceWithin(xy(0, 0), 100.0).isNone
  test "a single point is a line of no length; a long segment is found from any cell it crosses":
    check abs(
      newRouteGrid(@[xy(10, 10)], 500.0).distanceWithin(xy(13, 14), 10.0).get - 5.0
    ) < 1e-9
    let g = newRouteGrid(@[xy(0, 0), xy(20_000, 0)], 500.0) # (a segment 40 cells long)
    check abs(g.distanceWithin(xy(12_345, 40), 100.0).get - 40.0) < 1e-9
  test "it agrees with measuring to every segment, on a route made of many short steps":
    var line: seq[XY]
    var seed = 12345'u32
    proc next(): float =
      seed = seed * 1664525'u32 + 1013904223'u32
      float(seed shr 8) / float(1 shl 24)

    var p = xy(0, 0)
    for i in 0 ..< 800:
      line.add p
      let a = next() * 2 * PI
      p = xy(p.x + 50 * cos(a), p.y + 50 * sin(a))
    let g = newRouteGrid(line, 2500.0)
    for k in 0 ..< 400:
      let q = xy((next() - 0.5) * 6000, (next() - 0.5) * 6000)
      let exact = pointLineDistance(q, line)
      let got = g.distanceWithin(q, 2000.0)
      if exact <= 2000.0:
        check got.isSome and abs(got.get - exact) < 1e-9
      else:
        check got.isNone
