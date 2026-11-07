import ../support/env
import std/[math, options, os, strutils, times, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/fit/bytes
import nimchoo/importer/importer
import nimchoo/modules
import nimchoo/profile/load
import nimchoo/warnings
import nimchoo/ff/[curve, params]
import nimchoo/ff/command as ffCommand
import nimchoo/model/calc

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
  test "one impulse fades by the hour, as exp(-hours / tau)":
    let r = response(@[(0'i64, 1.0)], 1, 3600 * 48) # tau of one day
    check r.len == 49 and r[0] == (0'i64, 1.0)
    for k in [1, 5, 24, 48]:
      check near(r[k].value, exp(-float(k) / 24))
      check r[k].hourT == int64(k) * 3600
  test "it is the sum of what each impulse has left":
    let imp = @[(0'i64, 3.0), (3600'i64 * 2, 5.0), (3600'i64 * 7, 0.5)]
    let r = response(imp, 7, 3600 * 100)
    for h in [0, 2, 3, 7, 50, 100]:
      var want = 0.0
      for (t, x) in imp:
        let j = int(t div 3600)
        if j <= h:
          want += x * exp(-float(h - j) / (7 * 24))
      check near(r[h].value, want, 1e-9)
  test "it starts at the first impulse, not before":
    let r = response(@[(3600'i64 * 10, 2.0)], 7, 3600 * 12)
    check r.len == 3 and r[0] == (3600'i64 * 10, 2.0)
  test "nothing if there is nothing, or it all comes later":
    check response(@[], 7, 3600).len == 0
    check response(@[(7200'i64, 1.0)], 7, 3600).len == 0
  test "a longer decay time is slower, and the two are the same shape":
    let imp = @[(0'i64, 1.0)]
    check response(imp, 42, 3600 * 24)[24].value > response(imp, 7, 3600 * 24)[24].value
    check near(decayPerHour(7), exp(-1.0 / 168))
  test "the day's end is its last hour":
    let r = response(@[(0'i64, 1.0)], 7, 86400 * 3 - 3600)
    let d = dayEnds(r, utc())
    check d.len == 3 and d[0].hourT == 86400 - 3600 and d[2].hourT == 86400 * 3 - 3600
    check near(d[0].value, exp(-23.0 / 168))

suite "ff: the command line":
  test "defaults, and everything given":
    let p = parseArgs(@[])
    check p.problem == "" and p.model == "" and not p.hourly and p.fitnessScale == 1 and
      p.fatigueScale == 1
    let q = parseArgs(
      @[
        "--model", "flat", "--from", "2018-08-01", "--to", "2018-08-31", "--hourly",
        "--fitness-scale", "2", "--fatigue-scale", "5",
      ]
    )
    check q.problem == "" and q.model == "flat" and q.hourly and q.fitnessScale == 2 and
      q.fatigueScale == 5
    check q.fromDay == some(1533081600'i64) and q.toDay == some(1535673600'i64)
  test "--stdout":
    check parseArgs(@["--stdout"]).stdout and not parseArgs(@[]).stdout
  test "problems":
    check parseArgs(@["--from", "yesterday"]).problem.contains("is a day")
    check parseArgs(@["--to", "2018-13-01"]).problem.contains("is a day")
    check parseArgs(@["--from", "2018-09-01", "--to", "2018-08-01"]).problem.contains(
      "after"
    )
    check parseArgs(@["--fitness-scale", "0"]).problem.contains("above 0")
    check parseArgs(@["--fatigue-scale", "x"]).problem.contains("above 0")
    check parseArgs(@["--model"]).problem.contains("needs a value")
    check parseArgs(@["x"]).problem.contains("unexpected argument")
    check parseArgs(@["-h"]).help

suite "ff: the rows":
  let m = defaultModel()
  let imp = @[(86400'i64 * 10, 10.0)] # day 10, hour 0 (UTC)
  let u = utc()
  let santiago = fixedZone("-03", -3 * 3600) # (a fixed offset: -03:00)
  let india = fixedZone("+0530", 5 * 3600 + 1800) # +05:30
  test "one a day, the value at the end of the day, scaled":
    let p = Params(toDay: some(86400'i64 * 12), fitnessScale: 1, fatigueScale: 5)
    let r = rows(imp, m, p, 0, u)
    check r.len == 3
    check r[0] ==
      "1970-01-11," & formatFloat(10 * exp(-23.0 / (42 * 24)), ffDecimal, 4) & "," &
      formatFloat(50 * exp(-23.0 / (7 * 24)), ffDecimal, 4)
    check r[2].startsWith("1970-01-13,")
  test "--from drops the early days; --to defaults to today":
    let p = Params(fromDay: some(86400'i64 * 11), fitnessScale: 1, fatigueScale: 1)
    let r = rows(imp, m, p, 86400'i64 * 12 + 5000, u)
    check r.len == 2 and r[0].startsWith("1970-01-12,")
  test "hourly rows are labelled by the end of the hour":
    let p = Params(
      toDay: some(86400'i64 * 10), hourly: true, fitnessScale: 1, fatigueScale: 1
    )
    let r = rows(imp, m, p, 0, u)
    check r.len == 24
    check r[0].startsWith("1970-01-11T01:00:00Z,10.0000,10.0000")
    check r[23].startsWith("1970-01-12T00:00:00Z,")
  test "in another timezone the days end at its midnight":
    # the impulse is at 21:00 on the 10th in Santiago (midnight UTC on the 11th); the 10th ends three hours later
    let p = Params(toDay: some(86400'i64 * 9), fitnessScale: 1, fatigueScale: 1)
    let r = rows(imp, m, p, 0, santiago)
    check r ==
      @[
        "1970-01-10," & formatFloat(10 * exp(-2.0 / (42 * 24)), ffDecimal, 4) & "," &
          formatFloat(10 * exp(-2.0 / (7 * 24)), ffDecimal, 4)
      ] # (three hours in: two decays)
    let none = rows(
      imp,
      m,
      Params(toDay: some(86400'i64 * 8), hourly: true, fitnessScale: 1, fatigueScale: 1),
      0,
      santiago,
    )
    check none.len == 0 # (nothing has happened by the end of the 9th)
    let h = rows(
      imp,
      m,
      Params(toDay: some(86400'i64 * 9), hourly: true, fitnessScale: 1, fatigueScale: 1),
      0,
      santiago,
    )
    check h.len == 3 and h[0].startsWith("1970-01-10T22:00:00-03:00,") and
      h[2].startsWith("1970-01-11T00:00:00-03:00,")
  test "today is today where you are":
    let p = Params(fitnessScale: 1, fatigueScale: 1)
    # 02:00 UTC on the 13th is still the 12th in Santiago
    check rows(imp, m, p, 86400'i64 * 12 + 7200, u)[^1].startsWith("1970-01-13,")
    check rows(imp, m, p, 86400'i64 * 12 + 7200, santiago)[^1].startsWith("1970-01-12,")
  test "a half-hour timezone uses the last whole hour before its midnight":
    # the 11th ends at 18:30 UTC on the 11th; the last whole hour ends at 18:00, 17 hours after the impulse's hour starts
    let p = Params(toDay: some(86400'i64 * 10), fitnessScale: 1, fatigueScale: 1)
    check rows(imp, m, p, 0, india) ==
      @[
        "1970-01-11," & formatFloat(10 * exp(-17.0 / (42 * 24)), ffDecimal, 4) & "," &
          formatFloat(10 * exp(-17.0 / (7 * 24)), ffDecimal, 4)
      ]

suite "nch ff":
  test "a file in the cache, made once from the same data; --stdout prints; errors are reported":
    let path = getTempDir() / "nch-test-ff.db"
    let cache = getTempDir() / "nch-test-ff-cache"
    removeFile(path)
    removeDir(cache)
    putEnv("NCH_CACHE", cache)
    let g = Globals(dbPath: path, fragments: allFragments, importSteps: allImportSteps)
    check ffCommand.run(g, @["--to", "2018-09-05"]) == exitFailure # nothing yet
    let s = store.openStore(path, allFragments)
    var ws: seq[Warning]
    discard s.importFile(
      loadProfile("../choochoo/data/sdk/Profile.xlsx"),
      "r.fit",
      readBytes("../choochoo/data/test/source/personal/2018-08-27-rec.fit"),
      ws,
      allImportSteps,
    )
    check ffCommand.run(g, @["--to", "2018-09-05"]) == exitFailure
      # (no FTHR: refused, with a reason)
    s.db.exec(sql"insert into user_profile(user_id, fthr) values (?, 154)", s.userId)
    s.close()
    check not dirExists(cache / "user")
      # (nothing made yet; the database has unpacked its list of places)
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc"]) == exitOk
    var files: seq[string]
    for f in walkFiles(cache / "user" / "*.csv"):
      files.add f
    check files.len == 1
    let name = extractFilename(files[0])
    check name.startsWith("ff--") and name.endsWith(".csv") and
      "--model-default--" in name and "--to-2018-09-05--" in name and "--tz-utc" in name
    let first = readFile(files[0])
    check first.startsWith("time,fitness,fatigue\n2018-08-27,")
    let t = store.openStore(path, allFragments)
    check t.db.getValue(sql"select count(*) from impulse") == "2"
      # (worked out by the command)
    t.db.exec(sql"delete from impulse")
    t.close()
    # the same request again finds the file, and does not work the impulses out again
    writeFile(files[0], "marker")
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc", "--worker"]) == exitOk
      # (a program: nothing more is done)
    check readFile(files[0]) == "marker"
    let u = store.openStore(path, allFragments)
    check u.db.getValue(sql"select count(*) from impulse") == "0"
    u.close()
    # at a terminal the latest values are worked out as well, which needs the impulses
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc"]) == exitOk
    check readFile(files[0]) == "marker" # (the file is still not made again)
    let u2 = store.openStore(path, allFragments)
    check u2.db.getValue(sql"select count(*) from impulse") == "2"
    u2.close()
    # other options, other files
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc", "--hourly"]) == exitOk
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc", "--fatigue-scale", "5"]) ==
      exitOk
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc", "--from", "2018-08-28"]) ==
      exitOk
    var n = 0
    for f in walkFiles(cache / "user" / "*.csv"):
      inc n
    check n == 4
    # a different FTHR is different data: a new file
    let v = store.openStore(path, allFragments)
    v.db.exec(sql"update user_profile set fthr = 160")
    v.close()
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc"]) == exitOk
    n = 0
    for f in walkFiles(cache / "user" / "*.csv"):
      inc n
    check n == 5
    check readFile(files[0]) == "marker"
    # --stdout makes no file
    check ffCommand.run(g, @["--to", "2018-09-06", "--utc", "--stdout"]) == exitOk
    n = 0
    for f in walkFiles(cache / "user" / "*.csv"):
      inc n
    check n == 5
    check ffCommand.run(g, @["--model", "nope"]) == exitFailure
    check ffCommand.run(g, @["--to", "x"]) == exitUsage
    useTestCache()

suite "nch ff: the key":
  test "--key asks for a file by the key of its data; an old key can not be made again":
    let path = getTempDir() / "nch-test-ff-key.db"
    let cache = getTempDir() / "nch-test-ff-key-cache"
    removeFile(path)
    removeDir(cache)
    putEnv("NCH_CACHE", cache)
    let g = Globals(dbPath: path, fragments: allFragments, importSteps: allImportSteps)
    let s = store.openStore(path, allFragments)
    var ws: seq[Warning]
    discard s.importFile(
      loadProfile("../choochoo/data/sdk/Profile.xlsx"),
      "r.fit",
      readBytes("../choochoo/data/test/source/personal/2018-08-27-rec.fit"),
      ws,
      allImportSteps,
    )
    s.db.exec(sql"insert into user_profile(user_id, fthr) values (?, 154)", s.userId)
    s.close()
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc"]) == exitOk
    var name = ""
    for f in walkFiles(cache / "user" / "*.csv"):
      name = extractFilename(f)
    let key = name.split("--check-")[1].split("--")[0]
    check key.len == 12
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc", "--check", key]) == exitOk
      # the current data
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc", "--check", "ffffffffffff"]) ==
      exitFailure # not made, not current
    check ffCommand.run(
      g, @["--to", "2018-09-05", "--utc", "--check", "ffffffffffff", "--stdout"]
    ) == exitFailure
    # a file that was made stays available under its key after the data change
    let t = store.openStore(path, allFragments)
    t.db.exec(sql"update user_profile set fthr = 160")
    t.close()
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc", "--check", key]) == exitOk
    check ffCommand.run(g, @["--to", "2018-09-05", "--utc", "--check", key, "--hourly"]) ==
      exitFailure # (that one was never made)
    useTestCache()
