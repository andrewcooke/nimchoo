import std/[options, strutils, times, unicode, unittest]
import db_connector/db_sqlite
import nimchoo/climbs/[report, work]
import nimchoo/db/store
import nimchoo/describe
import nimchoo/ui/style
import ../support/[climbdata, userdata]

func row(activity, sector: int64, rank, total: int, elapsed, best: float, startT = 1535371200'i64): EffortRow =
  EffortRow(activity: activity, startT: startT, sport: "cycling", distanceM: some(62300.0), sector: sector,
            activeS: some(5400.0), atM: 14520.0, lengthM: 1949.0, gainM: 92.6, gradient: 4.8, category: "4", elapsed: elapsed,
            rank: rank, total: total, best: best,
            name: (if sector == 17: "Cerro Calán" else: "La Dehesa"))

suite "climbs report: the words":
  test "a time, to the second":
    check duration(552.4) == "9:12"
    check duration(59.6) == "1:00"
    check duration(0) == "0:00"
    check duration(3723) == "1:02:03"
    check duration(7751.0) == "2:09:11"
  test "kilometres to a tenth, the unit attached":
    check km(14520) == "14.5km"
    check km(1949) == "1.9km"
    check km(50) == "0.1km"

suite "climbs report: the display while they are worked out":
  test "two lines like the import's: plain, then the counts in green joined by grey dots":
    let lines = climbingLines(120, 1986, Worked(activities: 120, sectors: 12, efforts: 40))
    check lines.len == 2
    check lines[0].text == "climbing 120 / 1,986 activities"
    check lines[0][0].look.bold and lines[0][0].look.colour == white and lines[0][1].look.colour == white
    check lines[1].text == "climbs 12 · efforts 40"
    check lines[1][0].look.colour == green and lines[1][2].look.colour == green
    check lines[1][1].text == " · " and lines[1][1].look.colour == grey
  test "the line after the display, as the import has one":
    check doneLine(Worked(activities: 1650, sectors: 138, efforts: 2661)) ==
      "done: 1,650 activities: 138 new climbs, 2,661 efforts"
    check doneLine(Worked(activities: 1, sectors: 1, efforts: 1)) ==
      "done: 1 activity: 1 new climb, 1 effort"

suite "climbs report: the lines":
  test "an activity (the standard way), then the climbs it went up (the standard way, then how it went), lined up":
    let lines = effortLines(@[row(1, 17, 3, 12, 552.4, 521.0), row(1, 8, 12, 12, 3723.0, 3000.0),
                              row(2, 17, 1, 12, 521.0, 521.0, startT = 1535457600)], utc())
    check lines == @[
      "2018-08-27 12:00  cycling  62.3km 1h30m",
      "  Cerro Calán  4  1.9km  +93m  4.8%  at 14.5km     9:12   3 of 12   best 8:41",
      "  La Dehesa    4  1.9km  +93m  4.8%  at 14.5km  1:02:03  12 of 12  best 50:00",
      "2018-08-28 12:00  cycling  62.3km 1h30m",
      "  Cerro Calán  4  1.9km  +93m  4.8%  at 14.5km     8:41   1 of 12   best 8:41"]
  test "the activity heading has its place and name; a climb of no category has a dash":
    var r = row(1, 3, 1, 1, 100.0, 100.0)
    r.place = "Providencia"
    r.activityName = "Lo Barnechea and back"
    r.category = ""
    let lines = effortLines(@[r], utc())
    check lines[0] == "2018-08-27 12:00  cycling  62.3km 1h30m  Providencia / Lo Barnechea and back"
    check lines[1].startsWith("  La Dehesa  -  1.9km  +93m  4.8%  at 14.5km")
  test "an activity without a sport, a distance or an active time shows dashes":
    var r = row(1, 3, 1, 1, 100.0, 100.0)
    r.sport = ""
    r.distanceM = none(float)
    r.activeS = none(float)
    check effortLines(@[r], utc())[0] == "2018-08-27 12:00  -  - -"
  test "the sectors, with headings":
    let lines = sectorLines(@[
      SectorRow(id: 20, lengthM: 14900, gainM: 1109, gradient: 7.4, category: "HC", efforts: 1, name: "unnamed",
                best: some(7751.0), by: "default", yours: some(7751.0)),
      SectorRow(id: 3, lengthM: 4900, gainM: 245, gradient: 5.0, category: "3", efforts: 0, name: "unnamed")])
    check lines[0].startsWith("climb") and "length" in lines[0] and lines[0].endsWith("yours")
    check lines[1].contains("HC   14.9km  +1109m      7.4%") and lines[2].contains("3     4.9km   +245m      5.0%")
    check lines[1].startsWith("unnamed") and "+1109m" in lines[1] and "14.9km" in lines[1] and "7.4%" in lines[1] and "2:09:11" in lines[1] and "default" in lines[1]
    check lines[2].startsWith("unnamed") and lines[2].endsWith("0")         # (no efforts: no time, nobody)
    let named = sectorLines(@[SectorRow(id: 20, lengthM: 14900, gainM: 1109, gradient: 7.4, category: "HC",
                                        name: "near Farellones (1/2)", efforts: 1, best: some(7751.0), by: "default")])
    check named[1].startsWith("near Farellones (1/2)")
  test "the name leads a line, lined up by characters, and a long one is cut":
    check cut("short") == "short"
    check cut("x".repeat(40)) == "x".repeat(27) & "..."
    check cut("é".repeat(31)).runeLen == 30
    check cut("near San Carlos de Apoquindo (1/3)") == "near San Carlos de Ap... (1/3)"
    check cut("near San Carlos de Apoquindo (1/3)").runeLen == 30
    var a = row(1, 17, 3, 12, 552.4, 521.0)
    a.name = "Cerro Calán"
    var b = row(1, 8, 3, 12, 552.4, 521.0)
    b.name = "Alto"
    let lines = effortLines(@[a, b], utc())
    check lines[1][0 ..< lines[1].find("at 14.5")].runeLen == lines[2][0 ..< lines[2].find("at 14.5")].runeLen

suite "climbs report: from the tables":
  test "the rank is among everyone's efforts; the selection chooses the activities":
    let s = fresh("report")
    defer: s.close()
    addUser(s.path, "bob")
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))      # 5 m/s
    addRide(s, "bob", "two", 2_000_000, 4.0, eastbound(4.0))          # slower
    addRide(s, "default", "three", 3_000_000, 6.0, eastbound(6.0))    # faster
    discard ensureClimbs(s)
    check selectedActivities(s) == 0
    check selectedEfforts(s).len == 0
    s.db.exec(sql"insert into selection(user_id, activity_id) select ?, id from activity where start_t in (1000000, 2000000)", s.userId)
    check selectedActivities(s) == 2
    let rows = selectedEfforts(s)       # the selected activities of the default user, whoever rode them
    check rows.len == 2
    check rows[0].startT == 1_000_000 and rows[0].rank == 2 and rows[0].total == 3      # the 3rd ride is faster
    check rows[1].startT == 2_000_000 and rows[1].rank == 3 and rows[1].total == 3
    check rows[0].best < rows[0].elapsed
    check abs(rows[0].gainM - 118.0) < 3.0 and rows[0].category == "4"
    # a retired climb is not listed
    s.db.exec(sql"update sector set retired = 1")
    check selectedEfforts(s).len == 0
  test "the sectors: best, whose, and the user's own":
    let s = fresh("sectors")
    defer: s.close()
    addUser(s.path, "bob")
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "bob", "two", 2_000_000, 6.0, eastbound(6.0))
    discard ensureClimbs(s)
    let rows = allSectors(s)
    check rows.len == 1
    check rows[0].efforts == 2 and rows[0].by == "bob"
    check rows[0].best.get < rows[0].yours.get          # the default user's own best is slower than bob's


