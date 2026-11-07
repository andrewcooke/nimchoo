import std/[math, unittest]
import nimchoo/fit/time
import nimchoo/model/calc

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

suite "model: the impulse of the readings":
  test "an effort at the top zone is 1 per 10 seconds":
    check hourlyImpulse(@[(UnixTime(0), 121), (UnixTime(60), 121)], 100, m) ==
      @[(0'i64, 6.0)]
  test "zone 3.5 is 0.25 per 10 seconds":
    check near(
      hourlyImpulse(@[(UnixTime(0), 177), (UnixTime(60), 177)], 200, m)[0].value,
      1.5,
      1e-9,
    ) # (3.5-1)/5 = 0.5 squared, 6 periods
  test "a ramp from zone 1 to zone 6 over a minute":
    let r = hourlyImpulse(@[(UnixTime(0), 68), (UnixTime(60), 121)], 100, m)
    check near(r[0].value, 2.0) # 60 s of u^2 from 0 to 1: 20 s-equivalents, /10
  test "below the first edge there is no impulse, but the hour is recorded":
    check hourlyImpulse(@[(UnixTime(0), 60), (UnixTime(30), 60)], 100, m) ==
      @[(0'i64, 0.0)]
  test "a gap longer than max_secs counts for nothing; one of exactly max_secs counts":
    check hourlyImpulse(@[(UnixTime(0), 121), (UnixTime(61), 121)], 100, m).len == 0
    check hourlyImpulse(@[(UnixTime(0), 121), (UnixTime(60), 121)], 100, m).len == 1
    # the readings either side of a long gap still count with their neighbours
    let r = hourlyImpulse(
      @[
        (UnixTime(0), 121),
        (UnixTime(10), 121),
        (UnixTime(100), 121),
        (UnixTime(110), 121),
      ],
      100,
      m,
    )
    check near(r[0].value, 2.0)
  test "irregular recording has no effect on the total":
    let even = hourlyImpulse(
      @[
        (UnixTime(0), 110),
        (UnixTime(10), 110),
        (UnixTime(20), 110),
        (UnixTime(30), 110),
      ],
      100,
      m,
    )
    let sparse = hourlyImpulse(@[(UnixTime(0), 110), (UnixTime(30), 110)], 100, m)
    check near(even[0].value, sparse[0].value)
  test "an interval across the hour is divided between the hours":
    let r = hourlyImpulse(@[(UnixTime(3590), 121), (UnixTime(3610), 121)], 100, m)
    check r == @[(0'i64, 1.0), (3600'i64, 1.0)]
    let s = hourlyImpulse(@[(UnixTime(3590), 68), (UnixTime(3610), 121)], 100, m)
      # a ramp: the second half is worth more
    check s.len == 2 and s[1].value > s[0].value
    check near(
      s[0].value + s[1].value,
      hourlyImpulse(@[(UnixTime(3500), 68), (UnixTime(3500 + 20), 121)], 100, m)[0].value,
    )
  test "hours are by the clock, not by the activity":
    check hourlyImpulse(
      @[(UnixTime(7200 + 5), 121), (UnixTime(7200 + 15), 121)], 100, m
    )[0].hourT == 7200
  test "a different model changes the numbers":
    var f = m
    f.gamma = 1
    check near(
      hourlyImpulse(@[(UnixTime(0), 177), (UnixTime(60), 177)], 200, f)[0].value, 3.0
    ) # 0.5 per 10 s, 6 periods
    f.maxSecs = 10
    check hourlyImpulse(@[(UnixTime(0), 177), (UnixTime(60), 177)], 200, f).len == 0
  test "readings out of order or repeated are skipped, not counted backwards":
    check hourlyImpulse(@[(UnixTime(10), 121), (UnixTime(10), 121)], 100, m).len == 0
    check hourlyImpulse(@[], 100, m).len == 0 and
      hourlyImpulse(@[(UnixTime(1), 121)], 100, m).len == 0

suite "model: variables":
  test "the defaults are the original's and are acceptable":
    check problem(defaultModel()) == ""
    check defaultModel().zones == [68.0, 83, 94, 105, 121]
  test "unacceptable ones are described":
    var x = defaultModel()
    x.zero = 6
    check problem(x) != ""
    x = defaultModel()
    x.gamma = 0
    check problem(x) != ""
    x = defaultModel()
    x.zones = [68.0, 83, 83, 105, 121]
    check problem(x) != ""
    x = defaultModel()
    x.maxSecs = 0
    check problem(x) != ""
    x = defaultModel()
    x.fatigueDays = -1
    check problem(x) != ""
