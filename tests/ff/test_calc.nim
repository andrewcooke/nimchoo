import std/[math, options, unittest]
import nimchoo/packages/fit/time
import nimchoo/packages/ff/calc
import nimchoo/packages/tags/tag

proc near(a, b: float, eps = 1e-9): bool =
  abs(a - b) <= eps

let m = defaultModel() # gamma 2, zero 1, one 6, 60 s, edges 68 83 94 105 121 %

suite "model: the zone":
  test "1 up to the first edge, rising across each band, 6 above the last":
    # with a threshold of 100 the edges are 68 83 94 105 121 bpm
    for (bpm, z) in [
      (50.0, 1.0),
      (68.0, 1.0),
      (75.5, 2.5),
      (83.0, 3.0),
      (88.5, 3.5),
      (94.0, 4.0),
      (99.5, 4.5),
      (105.0, 5.0),
      (113.0, 5.5),
      (121.0, 6.0),
      (150.0, 6.0),
    ]:
      check near(zoneOf(bpm, 100, m.zones), z)
  test "the edges are percentages of the threshold":
    check near(zoneOf(154 * 0.83, 154, m.zones), 3.0)
    check near(zoneOf(154 * 1.21, 154, m.zones), 6.0)
    check near(zoneOf(154 * 1.21 + 1, 154, m.zones), 6.0)
  test "the zone never goes down as the heart rate goes up":
    var last = 0.0
    for bpm in 40 .. 220:
      let z = zoneOf(float(bpm), 154, m.zones)
      check z >= last and z >= 1.0 and z <= 6.0
      last = z

suite "model: the integral of a power along a straight line":
  test "constant, and straight lines worked by hand":
    check near(powIntegral(1, 1, 60, 2), 60)
    check near(powIntegral(0.5, 0.5, 60, 2), 15)
    check near(powIntegral(0, 1, 1, 2), 1.0 / 3) # ∫ x^2 dx
    check near(powIntegral(0, 1, 60, 1), 30)
    check near(powIntegral(1, 0, 60, 3), 15) # ∫ (1-x)^3 dx = 1/4
  test "only the part above zero counts":
    check near(powIntegral(-1, 1, 2, 1), 0.5)
      # u > 0 for the last half: ∫ x dx over 0..1
    check near(powIntegral(1, -1, 2, 1), 0.5)
    check powIntegral(-2, -1, 10, 2) == 0 and powIntegral(0, 0, 10, 2) == 0
    check powIntegral(1, 1, 0, 2) == 0
  test "it agrees with adding up small steps":
    for (u0, u1, g) in [
      (0.1, 0.9, 2.0),
      (0.9, 0.2, 1.5),
      (-0.3, 0.8, 2.0),
      (0.5, -0.4, 3.0),
      (0.2, 0.2000000001, 2.0),
    ]:
      var sum = 0.0
      const n = 200000
      for i in 0 ..< n:
        let u = u0 + (u1 - u0) * (float(i) + 0.5) / n
        if u > 0:
          sum += pow(u, g)
      check near(powIntegral(u0, u1, 7, g), sum * 7 / n, 1e-5)

proc rs(pairs: openArray[(int, int)]): seq[(UnixTime, int)] =
  ## readings from (second, bpm)
  for (t, bpm) in pairs:
    result.add (UnixTime(t), bpm)

proc steady(t0, t1, bpm: int): seq[(UnixTime, int)] =
  ## a reading every 10 seconds from t0 to t1, all at bpm
  var t = t0
  while t <= t1:
    result.add (UnixTime(t), bpm)
    t += 10

proc whole(readings: openArray[(UnixTime, int)], fthr: int, model = m): Lump =
  ## the impulse of readings that are all one stretch
  let ls = stretchImpulse(readings, @[(-1000'i64, 100000'i64)], fthr, model)
  doAssert ls.len == 1
  ls[0]

suite "model: the impulse of the readings":
  test "an effort at the top zone is 1 per 10 seconds, at its middle":
    check whole(rs([(0, 121), (60, 121)]), 100) == (30'i64, 6.0)
  test "zone 3.5 is 0.25 per 10 seconds":
    check near(whole(rs([(0, 177), (60, 177)]), 200).value, 1.5)
      # (3.5-1)/5 = 0.5 squared, 6 periods
  test "a ramp from zone 1 to zone 6 over a minute":
    check near(whole(rs([(0, 68), (60, 121)]), 100).value, 2.0)
      # 60 s of u^2 from 0 to 1: 20 s-equivalents, /10
  test "the centre is weighted by the impulse":
    # 30 s at the top, then 30 s at zone 3.5 (a quarter as much): the centre is nearer the start
    let l = whole(rs([(0, 121), (30, 121), (31, 88), (61, 88)]), 100)
    check l.t > 15 and l.t < 31
  test "below the first edge there is no impulse, but the stretch has a lump, at its middle":
    check stretchImpulse(rs([(0, 60), (30, 60)]), @[(0'i64, 40'i64)], 100, m) ==
      @[(20'i64, 0.0)]
  test "a gap longer than max_secs counts for nothing; one of exactly max_secs counts":
    check whole(rs([(0, 121), (61, 121)]), 100).value == 0
    check near(whole(rs([(0, 121), (60, 121)]), 100).value, 6.0)
    # the readings either side of a long gap still count with their neighbours
    check near(whole(rs([(0, 121), (10, 121), (100, 121), (110, 121)]), 100).value, 2.0)
  test "irregular recording has no effect on the total":
    check near(
      whole(rs([(0, 110), (10, 110), (20, 110), (30, 110)]), 100).value,
      whole(rs([(0, 110), (30, 110)]), 100).value,
    )
  test "one lump a stretch; what is between two stretches goes to the nearer":
    # stretches 0-100 and 200-300, heart rate all the way through: the cut is at 150
    let ls = stretchImpulse(
      steady(0, 300, 121), @[(0'i64, 100'i64), (200'i64, 300'i64)], 100, m
    )
    check ls.len == 2
    check near(ls[0].value, 15.0) and ls[0].t == 75
    check near(ls[1].value, 15.0) and ls[1].t == 225
  test "an interval across the cut is divided between the stretches":
    let ls = stretchImpulse(
      rs([(145, 121), (155, 121)]), @[(0'i64, 100'i64), (200'i64, 300'i64)], 100, m
    )
    check near(ls[0].value, 0.5) and near(ls[1].value, 0.5)
  test "before the first stretch and after the last go to them; a stretch with nothing has 0":
    let ls = stretchImpulse(
      rs([(0, 121), (10, 121), (990, 121), (1000, 121)]),
      @[(100'i64, 200'i64), (400'i64, 500'i64), (800'i64, 900'i64)],
      100,
      m,
    )
    check ls == @[(5'i64, 1.0), (450'i64, 0.0), (995'i64, 1.0)]
  test "a different model changes the numbers":
    var f = m
    f.gamma = 1
    check near(whole(rs([(0, 177), (60, 177)]), 200, f).value, 3.0)
      # 0.5 per 10 s, 6 periods
    f.maxSecs = 10
    check whole(rs([(0, 177), (60, 177)]), 200, f).value == 0
  test "readings out of order or repeated are skipped, not counted backwards":
    check whole(rs([(10, 121), (10, 121)]), 100).value == 0
    check whole(rs([(20, 121), (10, 121)]), 100).value == 0
    check whole(@[], 100).value == 0 and whole(rs([(1, 121)]), 100).value == 0
  test "no stretches, no lumps":
    check stretchImpulse(rs([(0, 121), (60, 121)]), @[], 100, m).len == 0

suite "model: variables":
  test "the defaults are the original's and are acceptable":
    check problem(defaultModel()).isNone
    check defaultModel().zones == [68.0, 83, 94, 105, 121]
  test "unacceptable ones are described":
    var x = defaultModel()
    x.zero = 6
    check problem(x).isSome
    x = defaultModel()
    x.gamma = 0
    check problem(x).isSome
    x = defaultModel()
    x.zones = [68.0, 83, 83, 105, 121]
    check problem(x).isSome
    x = defaultModel()
    x.maxSecs = 0
    check problem(x).isSome
    x = defaultModel()
    x.fatigueDays = -1
    check problem(x).isSome
    x = defaultModel()
    x.fatigueScale = 0
    check problem(x).isSome
  test "what changes the impulses: not the decays, the scales or the patterns":
    var x = defaultModel()
    x.fitnessDays = 10
    x.fatigueScale = 2
    x.patterns = @[TagPattern("sport:cycling*")]
    check sameImpulse(defaultModel(), x)
    x.zones[4] = 130
    check not sameImpulse(defaultModel(), x)
