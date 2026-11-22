import std/[options, os, strutils, unittest]
import nimchoo/packages/ui/[interval, units]

suite "units: a number and its unit":
  test "distances in km, one decimal, commas from 1,000; the unit follows with no space":
    check kmNumber(0.0) == "0.0"
    check kmNumber(102650.0) == "102.7"
    check kmNumber(1234567.0) == "1,234.6"
    check km(0.0) == "0.0km"
    check km(5549.0) == "5.5km"
    check km(99950.0) == "100.0km"
    check km(1234567.0) == "1,234.6km"
  test "sizes in bytes, kB and MB; the unit follows with no space":
    check humanBytes(1_400_000) == "1.4MB" and humanBytes(85_000) == "85kB" and
      humanBytes(12) == "12B"
  test "not recorded is a dash":
    check notRecorded == "-"
  test "a number without a pointless decimal part":
    check plainNumber(5.0) == "5" and plainNumber(1.25) == "1.25" and
      plainNumber(0.5) == "0.5" and plainNumber(100.0) == "100"

suite "units: counts":
  test "a count has commas from 1,000; counted says what it counts, singular for one":
    check count(1113) == "1,113" and count(7) == "7"
    check counted(1, "activity", "activities") == "1 activity"
    check counted(1113, "activity", "activities") == "1,113 activities"
    check counted(0, "file", "files") == "0 files"

  test "no other code writes commas into a count itself: every count is count() or counted()":
    var found: seq[string]
    let top = currentSourcePath().parentDir.parentDir.parentDir / "src"
    for path in walkDirRec(top):
      if path.endsWith(".nim") and not path.endsWith("ui/units.nim") and
          "insertSep" in readFile(path):
        found.add path.relativePath(top)
    check found.len == 0
    if found.len > 0:
      echo "commas written by hand: ", found.join(", ")

suite "units: a distance and a duration read with their units":
  test "a distance is a number and km or m, in metres":
    check parseDistance("100m").get.inMetres == 100.0
    check parseDistance("1.5km").get.inMetres == 1500.0
    check parseDistance("0.25km").get.inKm == 0.25
    check parseDistance("10km") == parseDistance("10000m")
  test "a distance with no unit, an unknown one, or not positive and finite is none":
    for bad in [
      "", "3", "km", "m", "-1km", "0km", "0m", "0.0m", "nankm", "infkm", "nan", "inf",
      "1e3km", "+1km", "1,5km", "1.2.3km", "3 km", "3mi", "3KM", "3h", ".km", "1e999km",
    ]:
      check parseDistance(bad).isNone
    check parseDistance("9".repeat(400) & "km").isNone # too big for a float
  test "a duration is d h m s, the largest first, as interval writes them":
    check parseTimeSpan("60s").get.inSeconds == 60.0
    check parseTimeSpan("42d").get.inDays == 42.0
    check parseTimeSpan("2h30m").get.inSeconds == 9000.0
    check parseTimeSpan("2d03h07m").get.inSeconds == 2 * 86400.0 + 3 * 3600.0 + 420.0
    check parseTimeSpan("1.5h").get.inSeconds == 5400.0
    check parseTimeSpan("5m").get.inSeconds == 300.0
  test "what interval writes is read back":
    for secs in [45.0, 1325.0, 16860.0, 183600.0]:
      check parseTimeSpan(interval(secs)).get.inSeconds == secs
  test "a duration with no unit, an unknown one, out of order or not positive is none":
    for bad in [
      "", "60", "s", "h30m", "-1s", "0s", "0d00h", "nans", "infs", "30m2h", "1s1s",
      "2h30", "1w", "1H", "1 h", "1h 30m", "1e3s", "+1s", "1..5s", "1,5h",
    ]:
      check parseTimeSpan(bad).isNone
