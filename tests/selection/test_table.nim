import std/[options, strutils, times, unittest]
import nimchoo/selection/table

let zone = utc()

const
  aug27 = 1535371200'i64            # 2018-08-27 12:00 UTC
  mar4 = 1520154720'i64             # 2018-03-04 09:12 UTC

func row(t: int64, sport = "cycling", sub = "", distance = -1.0, active = -1.0,
         file = "f.fit", user = "default"): ListRow =
  ListRow(startT: t, sport: sport, subSport: sub,
          distanceM: if distance >= 0: some(distance) else: none(float),
          activeS: if active >= 0: some(active) else: none(float), file: file, user: user)

suite "list table: pieces":
  test "the sport, with the sub-sport only if it says something":
    check sportLabel(row(0, "cycling", "road")) == "cycling/road"
    check sportLabel(row(0, "cycling", "generic")) == "cycling"
    check sportLabel(row(0, "cycling", "")) == "cycling"
    check sportLabel(row(0, "", "")) == "-"
    check sportLabel(row(0, "", "road")) == "-/road"
  test "distances in km, one decimal, commas from 1,000":
    check km(0.0) == "0.0 km"
    check km(102650.0) == "102.7 km"
    check km(5549.0) == "5.5 km"
    check km(99950.0) == "100.0 km"
    check km(1234567.0) == "1,234.6 km"
  test "times as hours and minutes, rounded to the minute":
    check hours(0.0) == "0:00"
    check hours(16860.0) == "4:41"
    check hours(89.0) == "0:01"
    check hours(29.0) == "0:00"
    check hours(353520.0) == "98:12"

suite "list table: the table":
  test "aligned, oldest first as given, the date and start in the zone":
    let lines = table(@[row(mar4, "cycling", "road", 102650.0, 16860.0),
                        row(aug27, "cycling", "", 5549.0, 1320.0)], zone, false, false)
    check lines == @[
      "date        start  sport         distance  active",
      "2018-03-04  09:12  cycling/road  102.7 km    4:41",
      "2018-08-27  12:00  cycling         5.5 km    0:22"]
  test "not recorded is a dash":
    let lines = table(@[row(aug27, "", "")], zone, false, false)
    check lines[1] == "2018-08-27  12:00  -             -       -"
  test "the zone moves the date and the time":
    let plus2 = newTimezone("+2", proc(t: Time): ZonedTime = ZonedTime(time: t, utcOffset: -7200, isDst: false),
                            proc(t: Time): ZonedTime = ZonedTime(time: t - initDuration(seconds = 7200), utcOffset: -7200, isDst: false))
    check table(@[row(aug27)], plus2, false, false)[1].startsWith("2018-08-27  14:00")
  test "a user column, after the start, only if asked; a file column, last":
    let rows = @[row(mar4, "cycling", "", 1000.0, 60.0, "a.fit", "alice"),
                 row(aug27, "running", "", 2000.0, 120.0, "bb.fit", "bob")]
    let withUser = table(rows, zone, false, true)
    check withUser[0] == "date        start  user   sport    distance  active"
    check withUser[1] == "2018-03-04  09:12  alice  cycling    1.0 km    0:01"
    let withFile = table(rows, zone, true, false)
    check withFile[0] == "date        start  sport    distance  active  file"
    check withFile[2].endsWith("0:02  bb.fit")
    check table(rows, zone, true, true)[0].startsWith("date        start  user   sport")
  test "no rows, no lines":
    check table(@[], zone, true, true).len == 0

suite "list table: the last line":
  test "how many, and of how many":
    check footer(@[], some 74) == "0 of 74 activities"
    check footer(@[row(0)], some 1).startsWith("1 of 1 activities")
    check footer(@[row(0)]).startsWith("1 activity")
    check footer(@[row(0), row(1)]).startsWith("2 activities")
  test "totals count only what is recorded":
    check footer(@[row(0, distance = 1500.0, active = 600.0), row(1), row(2, distance = 500.0)]) ==
      "3 activities, 2.0 km, 0:10 h"
  test "a count by sport only when there are several, most first, ties by name":
    check footer(@[row(0, "cycling"), row(1, "cycling")]) == "2 activities, 0.0 km, 0:00 h"
    check footer(@[row(0, "running"), row(1, "cycling"), row(2, "running"), row(3, "swimming")]) ==
      "4 activities, 0.0 km, 0:00 h (2 running, 1 cycling, 1 swimming)"
    check footer(@[row(0, ""), row(1, "cycling")]).endsWith("(1 cycling, 1 unknown)")
