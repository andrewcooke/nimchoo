import nimchoo/packages/db/statement
import ../support/shims
import ../support/env
import std/[math, options, os, strutils, times, unittest]
import nimchoo/core/globals
import nimchoo/packages/user/session
import nimchoo/packages/util/bytes/bytes
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/heartrate/step
import nimchoo/packages/fit/load
import nimchoo/packages/util/warnings/warnings
import nimchoo/packages/ff/curve
import nimchoo/packages/ff/params
import nimchoo/packages/util/args/args
import nimchoo/packages/ff/command as ffCommand
import nimchoo/packages/model/calc
import nimchoo/packages/fit/time

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

suite "ff: the decay":
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

suite "ff: one lump a stretch is as good as a fine integration":
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

suite "ff: the command line":
  test "defaults, and everything given":
    let p = parseArgs(@[])
    check p.problem == "" and p.params.model.isNone and not p.params.hourly and
      p.params.fitnessScale == 1 and p.params.fatigueScale == 1
    let q = parseArgs(
      @[
        "--model", "flat", "--after", "2018-08-01", "--before", "2018-09-01",
        "--hourly", "--fitness-scale", "2", "--fatigue-scale", "5",
      ]
    )
    check q.problem == "" and q.params.model == some("flat") and q.params.hourly and
      q.params.fitnessScale == 2 and q.params.fatigueScale == 5
    check q.params.firstDay == some(1533081600'i64) and
      q.params.lastDay == some(1535673600'i64)
  test "--stdout":
    check parseArgs(@["--stdout"]).params.stdout and not parseArgs(@[]).params.stdout
  test "problems":
    check parseArgs(@["--after", "yesterday"]).problem.contains("is a day")
    check parseArgs(@["--before", "2018-13-01"]).problem.contains("is a day")
    check parseArgs(@["--after", "2018-09-01", "--before", "2018-08-02"]).problem
      .contains("after")
    check parseArgs(@["--fitness-scale", "0"]).problem.contains("above 0")
    check parseArgs(@["--fatigue-scale", "x"]).problem.contains("above 0")
    check parseArgs(@["--model"]).problem.contains("needs a value")
    check parseArgs(@["x"]).problem.contains("unexpected argument")
    check parseArgs(@["-h"]).help

suite "ff: the rows":
  let m = defaultModel()
  let imp = @[(86400'i64 * 10, 10.0)] # day 10, 00:00 (UTC)
  let u = utc()
  let santiago = fixedZone("-03", -3 * 3600) # (a fixed offset: -03:00)
  let india = fixedZone("+0530", 5 * 3600 + 1800) # +05:30
  test "one a day, the value at the end of the day, scaled":
    let p = Params(lastDay: some(86400'i64 * 12), fitnessScale: 1, fatigueScale: 5)
    let r = rows(imp, m, p, 0, u)
    check r.len == 3
    check r[0] ==
      "1970-01-11," & formatFloat(10 * exp(-24.0 / (42 * 24)), ffDecimal, 4) & "," &
      formatFloat(50 * exp(-24.0 / (7 * 24)), ffDecimal, 4)
    check r[2].startsWith("1970-01-13,")
  test "--from drops the early days; --to defaults to today":
    let p = Params(firstDay: some(86400'i64 * 11), fitnessScale: 1, fatigueScale: 1)
    let r = rows(imp, m, p, 86400'i64 * 12 + 5000, u)
    check r.len == 2 and r[0].startsWith("1970-01-12,")
  test "hourly rows are labelled by the end of the hour":
    let p = Params(
      lastDay: some(86400'i64 * 10), hourly: true, fitnessScale: 1, fatigueScale: 1
    )
    let r = rows(imp, m, p, 0, u)
    check r.len == 24
    check r[0] ==
      "1970-01-11T01:00:00Z," & formatFloat(10 * exp(-1.0 / (42 * 24)), ffDecimal, 4) &
      "," & formatFloat(10 * exp(-1.0 / (7 * 24)), ffDecimal, 4)
    check r[23].startsWith("1970-01-12T00:00:00Z,")
  test "in another timezone the days end at its midnight":
    # the lump is at 21:00 on the 10th in Santiago (midnight UTC on the 11th); the 10th ends three hours later
    let p = Params(lastDay: some(86400'i64 * 9), fitnessScale: 1, fatigueScale: 1)
    let r = rows(imp, m, p, 0, santiago)
    check r ==
      @[
        "1970-01-10," & formatFloat(10 * exp(-3.0 / (42 * 24)), ffDecimal, 4) & "," &
          formatFloat(10 * exp(-3.0 / (7 * 24)), ffDecimal, 4)
      ]
    let none = rows(
      imp,
      m,
      Params(
        lastDay: some(86400'i64 * 8), hourly: true, fitnessScale: 1, fatigueScale: 1
      ),
      0,
      santiago,
    )
    check none.len == 0 # (nothing has happened by the end of the 9th)
    let h = rows(
      imp,
      m,
      Params(
        lastDay: some(86400'i64 * 9), hourly: true, fitnessScale: 1, fatigueScale: 1
      ),
      0,
      santiago,
    )
    check h.len == 3 and h[0].startsWith("1970-01-10T22:00:00-03:00,") and
      h[2].startsWith("1970-01-11T00:00:00-03:00,")
  test "no lumps, no rows":
    check rows(@[], m, Params(fitnessScale: 1, fatigueScale: 1), 86400 * 5, u).len == 0
  test "today is today where you are":
    let p = Params(fitnessScale: 1, fatigueScale: 1)
    # 02:00 UTC on the 13th is still the 12th in Santiago
    check rows(imp, m, p, 86400'i64 * 12 + 7200, u)[^1].startsWith("1970-01-13,")
    check rows(imp, m, p, 86400'i64 * 12 + 7200, santiago)[^1].startsWith("1970-01-12,")
  test "a half-hour timezone's day ends at its midnight":
    # the 11th ends at 18:30 UTC on the 11th, 18.5 hours after the lump
    let p = Params(lastDay: some(86400'i64 * 10), fitnessScale: 1, fatigueScale: 1)
    check rows(imp, m, p, 0, india) ==
      @[
        "1970-01-11," & formatFloat(10 * exp(-18.5 / (42 * 24)), ffDecimal, 4) & "," &
          formatFloat(10 * exp(-18.5 / (7 * 24)), ffDecimal, 4)
      ]

suite "nch ff":
  test "a file in the cache, named by the options and made again each time; --stdout prints; errors are reported":
    let path = getTempDir() / "nch-test-ff.db"
    let cache = getTempDir() / "nch-test-ff-cache"
    removeFile(path)
    removeDir(cache)
    putEnv("NCH_CACHE", cache)
    let g = Globals(dbPath: some(path), fragments: allFragments, access: allAccess)
    check ffCommand.run(g, @["--before", "2018-09-06", "--file"]) == exitFailure
      # nothing yet
    let s = openSession(path, allFragments, access = allAccess)
    var ws: seq[Warning]
    discard s.importFile(
      loadProfile("../choochoo/data/sdk/Profile.xlsx"),
      "r.fit",
      readBytes("../choochoo/data/test/source/personal/2018-08-27-rec.fit"),
      ws,
      @[heartrateStep],
    )
    check ffCommand.run(g, @["--before", "2018-09-06", "--file"]) == exitFailure
      # (no FTHR: refused, with a reason)
    s.db.execute(
      "insert into user_profile(user_id, fthr) values (:userId, 154)", userId = s.userId
    )
    s.close()
    check not dirExists(cache / "user")
      # (nothing made yet; the database has unpacked its list of places)
    check ffCommand.run(g, @["--before", "2018-09-06", "--utc", "--file"]) == exitOk
    var files: seq[string]
    for f in walkFiles(cache / "user" / "*.csv"):
      files.add f
    check files.len == 1
    let name = extractFilename(files[0])
    check name == "ff-default-to-2018-09-05-utc.csv"
    let first = readFile(files[0])
    check first.startsWith("time,fitness,fatigue\n2018-08-27,")
    let t = openSession(path, allFragments, access = allAccess)
    check t.db.scalar(int, "select count(*) from impulse") == 1
      # (worked out by the command)
    t.db.execute("delete from impulse")
    t.close()
    # the same request again makes the file again, from the data as they are, and works the impulses out again
    writeFile(files[0], "marker")
    check ffCommand.run(g, @["--before", "2018-09-06", "--utc", "--file"]) == exitOk
    check readFile(files[0]) == first
    let u2 = openSession(path, allFragments, access = allAccess)
    check u2.db.scalar(int, "select count(*) from impulse") == 1
    u2.close()
    # other options, other files
    check ffCommand.run(g, @["--before", "2018-09-06", "--utc", "--hourly", "--file"]) ==
      exitOk
    check ffCommand.run(
      g, @["--before", "2018-09-06", "--utc", "--fatigue-scale", "5", "--file"]
    ) == exitOk
    check ffCommand.run(
      g, @["--before", "2018-09-06", "--utc", "--after", "2018-08-28", "--file"]
    ) == exitOk
    var n = 0
    for f in walkFiles(cache / "user" / "*.csv"):
      inc n
    check n == 4
    # a different FTHR is different data: the same file, with other values
    let v = openSession(path, allFragments, access = allAccess)
    v.db.execute("update user_profile set fthr = 160")
    v.close()
    check ffCommand.run(g, @["--before", "2018-09-06", "--utc", "--file"]) == exitOk
    n = 0
    for f in walkFiles(cache / "user" / "*.csv"):
      inc n
    check n == 4
    check readFile(files[0]) != first
    # --stdout makes no file
    check ffCommand.run(g, @["--before", "2018-09-07", "--utc", "--stdout"]) == exitOk
    n = 0
    for f in walkFiles(cache / "user" / "*.csv"):
      inc n
    check n == 4
    check ffCommand.run(g, @["--model", "nope", "--file"]) == exitFailure
    check ffCommand.run(g, @["--before", "x"]) == exitUsage
    useTestCache()
