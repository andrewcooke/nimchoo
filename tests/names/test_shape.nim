import std/[math, unittest]
import nimchoo/names/shape

# routes on a flat patch near the equator: metres east/north turned into positions
const mDeg = 360.0 / (2.0 * PI * 6_371_008.8)

proc route(points: seq[(float, float)]): tuple[lons, lats: seq[float]] =
  for (x, y) in points:
    result.lons.add x * mDeg
    result.lats.add y * mDeg

proc line(a, b: (float, float), step = 20.0): seq[(float, float)] =
  let n = max(1, int(hypot(b[0] - a[0], b[1] - a[1]) / step))
  for i in 0 .. n: result.add (a[0] + (b[0] - a[0]) * i.float / n.float, a[1] + (b[1] - a[1]) * i.float / n.float)

proc shapeOfPoints(p: seq[(float, float)]): Shape =
  let r = route(p)
  shapeOf(r.lons, r.lats)

suite "names: the shape of an activity":
  test "nothing, or one point, is local":
    check shapeOf([], []).kind == skLocal
    check shapeOf([1.0], [1.0]).kind == skLocal
  test "a ride that never gets far is local, even if it is a loop":
    var p = line((0.0, 0.0), (500.0, 0.0)) & line((500.0, 0.0), (500.0, 500.0)) & line((500.0, 500.0), (0.0, 0.0))
    check shapeOfPoints(p).kind == skLocal
  test "out and back over the same road":
    let p = line((0.0, 0.0), (10_000.0, 0.0)) & line((10_000.0, 0.0), (0.0, 0.0))
    let s = shapeOfPoints(p)
    check s.kind == skOutAndBack
    check s.retraced > 0.95
    check abs(s.farM - 10_000.0) < 100.0 and abs(s.lengthM - 20_000.0) < 200.0
  test "out and back on slightly different lines (a road with two sides)":
    let p = line((0.0, 0.0), (10_000.0, 0.0)) & line((10_000.0, 10.0), (0.0, 10.0))
    check shapeOfPoints(p).kind == skOutAndBack
  test "a loop: back by another road":
    let p = line((0.0, 0.0), (8_000.0, 0.0)) & line((8_000.0, 0.0), (8_000.0, 6_000.0)) &
            line((8_000.0, 6_000.0), (0.0, 6_000.0)) & line((0.0, 6_000.0), (0.0, 0.0))
    let s = shapeOfPoints(p)
    check s.kind == skLoop
    check s.retraced < 0.1
  test "a lollipop is mixed: part of the way back is over the way out, part is not":
    let p = line((0.0, 0.0), (5_000.0, 0.0)) & line((5_000.0, 0.0), (5_000.0, 6_000.0)) &
            line((5_000.0, 6_000.0), (9_000.0, 6_000.0)) & line((9_000.0, 6_000.0), (9_000.0, 0.0)) &
            line((9_000.0, 0.0), (5_000.0, 0.0)) & line((5_000.0, 0.0), (0.0, 0.0))
    let s = shapeOfPoints(p)
    check s.kind == skMixed
    check s.retraced >= loopBelow and s.retraced < outAndBackFrom
  test "out along the road and back, but home another way for the last part: still out and back":
    # out 10 km east, back 7 km along the same road, then a different road (a parallel one 3 km north) home
    let p = line((0.0, 0.0), (10_000.0, 0.0)) & line((10_000.0, 0.0), (3_000.0, 0.0)) &
            line((3_000.0, 0.0), (3_000.0, 3_000.0)) & line((3_000.0, 3_000.0), (0.0, 3_000.0)) &
            line((0.0, 3_000.0), (0.0, 0.0))
    let s = shapeOfPoints(p)
    check s.kind == skOutAndBack
    check s.retracedNear > 0.95 and s.retraced < 0.9
  test "a rectangle: the way back starts on a new road, so not out and back":
    # out 6 km east, north 5 km, then west 5 km and south: nothing of the way back is over the way out
    let p = line((0.0, 0.0), (6_000.0, 0.0)) & line((6_000.0, 0.0), (6_000.0, 5_000.0)) &
            line((6_000.0, 5_000.0), (0.0, 5_000.0)) & line((0.0, 5_000.0), (0.0, 0.0))
    check shapeOfPoints(p).kind == skLoop
  test "from one place to another":
    let p = line((0.0, 0.0), (30_000.0, 4_000.0))
    let s = shapeOfPoints(p)
    check s.kind == skOneWay
    check s.endM > 0.9 * s.farM
  test "a ride that ends a little way from the start still closes; further off it does not":
    let near = line((0.0, 0.0), (10_000.0, 0.0)) & line((10_000.0, 0.0), (1_500.0, 0.0))    # ends 1.5 km short: 15 % of 10 km
    check shapeOfPoints(near).kind == skOutAndBack
    let far = line((0.0, 0.0), (10_000.0, 0.0)) & line((10_000.0, 0.0), (6_000.0, 0.0))     # 60 %
    check shapeOfPoints(far).kind == skOneWay
  test "the route is taken every 50 m, so the number of points does not depend on how it was recorded":
    let sparse = shapeOfPoints(line((0.0, 0.0), (10_000.0, 0.0), step = 500.0))
    let dense = shapeOfPoints(line((0.0, 0.0), (10_000.0, 0.0), step = 2.0))
    check abs(sparse.points.len - dense.points.len) <= 1
