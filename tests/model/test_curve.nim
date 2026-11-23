import std/[math, options, times, unittest]
import nimchoo/packages/fit/time
import nimchoo/packages/model/[calc, curve]

proc near(a, b: float, eps = 1e-9): bool =
  abs(a - b) <= eps

template fixedZone(zoneName: string, east: int): Timezone =
  ## A timezone with a fixed offset east of UTC, in seconds.
  newTimezone(
    zoneName,
    proc(t: Time): ZonedTime {.tags: [], raises: [].} =
      ZonedTime(utcOffset: -east, isDst: false, time: t),
    proc(adj: Time): ZonedTime {.tags: [], raises: [].} =
      ZonedTime(
        utcOffset: -east, isDst: false, time: adj - initDuration(seconds = east)
      ),
  )

suite "model: the curves":
  test "one lump fades as exp(-time / tau)":
    let r = curveAt(@[(0'i64, 1.0)], 1, [0'i64, 3600, 86400, 86400 * 2]) # tau of one day
    check r[0] == 1.0 and near(r[1], exp(-1.0 / 24)) and near(r[2], exp(-1.0)) and
      near(r[3], exp(-2.0))
  test "it is the sum of what each lump has left, at any time":
    let imp = @[(17'i64, 3.0), (7300'i64, 5.0), (25001'i64, 0.5)]
    let times = @[17'i64, 18, 7299, 7300, 99999, 360000]
    let r = curveAt(imp, 7, times)
    for k, t in times:
      var want = 0.0
      for (at, x) in imp:
        if at <= t:
          want += x * exp(-float(t - at) / (7 * 86400))
      check near(r[k], want, 1e-9)
  test "before the first lump it is 0; at a lump, the lump counts":
    check curveAt(@[(100'i64, 2.0)], 7, [0'i64, 99, 100]) == @[0.0, 0.0, 2.0]
  test "nothing if there is nothing":
    check curveAt(@[], 7, [0'i64, 3600]) == @[0.0, 0.0]
  test "a longer decay time is slower":
    let imp = @[(0'i64, 1.0)]
    check curveAt(imp, 42, [86400'i64])[0] > curveAt(imp, 7, [86400'i64])[0]
  test "the ends of the days, from the day of the first instant to the last day":
    check dayEnds(5000, 86400 * 2, utc()) == @[86400'i64, 86400 * 2, 86400 * 3]
    check dayEnds(86400 * 3, 86400 * 2, utc()).len == 0
    let santiago = fixedZone("-03", -3 * 3600)
    check dayEnds(3600, -86400, santiago) ==
      @[3 * 3600'i64] # (01:00 UTC on 1 January is 22:00 on 31 December in Santiago)
  test "the ends of the clock's hours, from the hour of the first instant":
    check hourEnds(5000, 3 * 3600) == @[7200'i64, 10800]
    check hourEnds(3600, 3600).len == 0 and hourEnds(3599, 3600) == @[3600'i64]

suite "model: one lump a stretch is as good as a fine integration":
  test "two hours of varied heart rate, in three stretches with pauses":
    let m = defaultModel()
    var readings: seq[(UnixTime, int)]
    for t in 0 .. 7200:
      if t in 2000 .. 2300 or t in 5000 .. 5100: # (pauses, with no heart rate)
        continue
      readings.add (UnixTime(t), 120 + int(40 * sin(float(t) / 300)))
    let stretches = @[(0'i64, 1999'i64), (2301'i64, 4999'i64), (5101'i64, 7200'i64)]
    let lumps = stretchImpulse(readings, stretches, 154, m)
    # the reference: a lump for every 10 seconds
    var tens: seq[Stretch]
    for t in countup(0'i64, 7200, 10):
      tens.add (t, t + 9)
    let fine = stretchImpulse(readings, tens, 154, m)
    let times = @[7200'i64, 7200 + 3600, 7200 + 86400, 7200 + 86400 * 10]
    for tau in [m.fatigueDays, m.fitnessDays]:
      let a = curveAt(lumps, tau, times)
      let b = curveAt(fine, tau, times)
      for k in 0 ..< times.len:
        check abs(a[k] - b[k]) <= 1e-4 * b[k]

suite "model: where a curve is drawn":
  test "the end of each day, and either side of each lump, within the period":
    let lumps = @[(86400'i64 + 3600, 5.0), (86400'i64 * 2 + 7200, 1.0)]
    check sampleTimes(lumps, none(int64), 86400 * 4, utc()) ==
      @[
        86400'i64 + 3599,
        86400 + 3600,
        86400 * 2,
        86400 * 2 + 7199,
        86400 * 2 + 7200,
        86400 * 3,
        86400 * 4,
      ]
    check sampleTimes(lumps, some(86400'i64 * 2), 86400 * 3, utc()) ==
      @[86400'i64 * 2, 86400 * 2 + 7199, 86400 * 2 + 7200, 86400 * 3]
    check sampleTimes(@[], none(int64), 86400, utc()).len == 0
