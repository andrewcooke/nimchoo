import std/[math, unittest]
import nimchoo/climbs/[detect, profile]

const step = 10.0

func shape(points: openArray[(float, float)]): seq[float] =
  ## An altitude every 10 m through the (distance, altitude) corners, joined by straight lines.
  var k = 0
  for i in 0 .. int(points[^1][0] / step):
    let d = float(i) * step
    while k + 2 < points.len and points[k + 1][0] <= d: inc k
    let (d0, e0) = points[k]
    let (d1, e1) = points[k + 1]
    result.add e0 + (e1 - e0) * (d - d0) / (d1 - d0)

func noisy(e: seq[float], amplitude: float): seq[float] =
  ## Deterministic noise (a simple generator), up to `amplitude` metres each way.
  var x = 12345'u32
  for v in e:
    x = x * 1664525'u32 + 1013904223'u32
    result.add v + amplitude * (float(x shr 8) / float(1 shl 24) * 2.0 - 1.0)

suite "climbs: categories":
  test "by the gain, as strava does":
    check categoryFor(79.9) == ""
    check categoryFor(80) == "4"
    check categoryFor(159) == "4"
    check categoryFor(160) == "3"
    check categoryFor(320) == "2"
    check categoryFor(640) == "1"
    check categoryFor(800) == "HC"
    check categoryFor(2000) == "HC"

suite "climbs: finding them":
  test "a flat road, or a gentle slope, has none":
    check findClimbs(shape([(0.0, 100.0), (5000.0, 100.0)]), step).len == 0
    check findClimbs(shape([(0.0, 100.0), (10000.0, 140.0)]), step).len == 0     # 40 m in 10 km
    check findClimbs(@[1.0], step).len == 0
    check findClimbs(newSeq[float](), step).len == 0

  test "one hill, with flat before and after":
    let e = shape([(0.0, 50.0), (1000.0, 50.0), (3000.0, 150.0), (4000.0, 150.0)])
    let cs = findClimbs(e, step)
    check cs.len == 1
    check abs(cs[0].first - 101) <= 2 and abs(cs[0].last - 299) <= 2     # the ramp is samples 100 to 300
    check abs(cs[0].gain - 99.0) < 2.0           # (brought in by a sample at each end)
    check abs(cs[0].length - 1980.0) < 30.0
    check abs(cs[0].gradient - 5.0) < 0.2
    check cs[0].category == "4"

  test "two hills apart are two climbs, in order":
    let e = shape([(0.0, 0.0), (1000.0, 0.0), (3000.0, 100.0), (6000.0, 100.0),
                   (8000.0, 200.0), (9000.0, 200.0)])
    let cs = findClimbs(e, step)
    check cs.len == 2
    check cs[0].last < cs[1].first
    check abs(cs[0].gain - 99.0) < 2.0 and abs(cs[1].gain - 99.0) < 2.0

  test "a descent in the middle of a climb splits it when it is big, not when it is small":
    let big = shape([(0.0, 0.0), (2000.0, 100.0), (2500.0, 70.0), (4500.0, 170.0), (5000.0, 170.0)])
    let two = findClimbs(big, step)               # a 30 m descent in 170 m of gain: over 10 %
    check two.len == 2
    check two[0].last < two[1].first
    let small = shape([(0.0, 0.0), (2000.0, 100.0), (2500.0, 95.0), (4500.0, 195.0), (5000.0, 195.0)])
    check findClimbs(small, step).len == 1        # a 5 m descent: the climb goes through it

  test "a short steep ramp is not a climb, and nor is a cliff":
    check findClimbs(shape([(0.0, 0.0), (500.0, 0.0), (700.0, 30.0), (1500.0, 30.0)]), step).len == 0
    check findClimbs(shape([(0.0, 0.0), (500.0, 0.0), (600.0, 100.0), (1500.0, 100.0)]), step).len == 0

  test "a descent is not a climb; a descent then a climb gives the climb":
    check findClimbs(shape([(0.0, 300.0), (4000.0, 100.0)]), step).len == 0
    let cs = findClimbs(shape([(0.0, 300.0), (3000.0, 100.0), (6000.0, 300.0)]), step)
    check cs.len == 1
    check cs[0].first > 280                       # it starts in the valley (sample 300), not before

  test "a long climb (found by the coarse search first)":
    let e = shape([(0.0, 0.0), (500.0, 0.0), (12500.0, 480.0), (13000.0, 480.0)])     # 12 km at 4 %
    let cs = findClimbs(e, step)
    check cs.len == 1
    check abs(cs[0].gain - 480.0) < 6.0
    check cs[0].category == "2"
    check abs(cs[0].first - 50) <= 12 and abs(cs[0].last - 1250) <= 12

  test "a little noise does not change what is found":
    let clean = shape([(0.0, 50.0), (1000.0, 50.0), (3000.0, 150.0), (4000.0, 150.0)])
    let cs = findClimbs(smoothed(noisy(clean, 1.5)), step)
    check cs.len == 1
    check abs(cs[0].gain - 99.0) < 6.0

  test "a profile with a gap in its altitudes: no climb crosses the gap":
    var e = shape([(0.0, 0.0), (2000.0, 100.0), (4000.0, 200.0)])      # one long climb ...
    e[200] = NaN                                                       # ... with the altitude missing at one sample
    var p = Profile(step: step, elev: e)
    let cs = findClimbs(p)
    for c in cs:
      check c.last < 200 or c.first > 200
