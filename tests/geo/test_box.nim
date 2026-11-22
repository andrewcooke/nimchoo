import std/unittest
import nimchoo/packages/geo/[box, geo]

suite "geo: the box round a circle or some positions":
  test "a box holds the circle":
    let b = circleBoxes(10.0, 0.0, 111_000.0)[0]
    check b.minY < -0.9 and b.maxY > 0.9
    check b.minX < 9.1 and b.maxX > 10.9
  test "the metres are turned into degrees with the one figure":
    let b = circleBoxes(0.0, 0.0, metresPerDegree)[0]
    check abs(b.maxY - 1.0) < 1e-9 and abs(b.minY + 1.0) < 1e-9
  test "one box, unless the circle goes over the date line":
    check circleBoxes(-9.1, 38.7, 50_000.0).len == 1
    let east = circleBoxes(179.9, -17.0, 50_000.0) # Fiji: the circle crosses +180
    check east.len == 2
    check east[0].maxX == 180.0 and east[1].minX == -180.0 and east[1].maxX < -179.0
    let west = circleBoxes(-179.9, -17.0, 50_000.0) # ... and from the other side
    check west.len == 2
    check west[0].minX == -180.0 and west[1].maxX == 180.0 and west[1].minX > 179.0
    check circleBoxes(179.0, 0.0, 1_000.0).len == 1
      # (a small circle that does not cross)
  test "near 180 degrees: both sides hold the points of the circle":
    for lon in [179.99, -179.99, 180.0, -180.0]:
      let boxes = circleBoxes(lon, 10.0, 5_000.0)
      check boxes.len == 2
      for probe in [179.98, -179.98]:
        var inside = false
        for b in boxes:
          if probe >= b.minX and probe <= b.maxX and 10.0 >= b.minY and 10.0 <= b.maxY:
            inside = true
        check inside
  test "longitude widens away from the equator":
    check circleBoxes(0.0, 60.0, 100_000.0)[0].maxX >
      1.5 * circleBoxes(0.0, 0.0, 100_000.0)[0].maxX
  test "over a pole: all longitudes, and never past the poles":
    let b = circleBoxes(10.0, 89.5, 100_000.0)
    check b.len == 1 and b[0].minX == -180.0 and b[0].maxX == 180.0 and b[0].maxY == 90.0
    check circleBoxes(10.0, -89.95, 6_000.0)[0].minY >= -90.0
  test "round some positions, widened by the margin":
    let w = widened([0.0, 1.0], [0.0, 1.0], 1000.0)
    check w.minX < 0.0 and w.maxX > 1.0 and w.minY < 0.0 and w.maxY > 1.0
    check widened([], [], 1000.0) == Box()
    check split(widened([-179.99, -179.9], [0.0, 0.0], 6000.0)).len == 2
  test "a box that starts past the date line is moved a turn":
    let b = split(Box(minX: 181.0, maxX: 182.0, minY: 0.0, maxY: 1.0))
    check b.len == 1 and b[0].minX == -179.0 and b[0].maxX == -178.0
