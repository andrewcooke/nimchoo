import std/[options, times, unittest]
import nimchoo/fit/time
import nimchoo/importer/describe

let zone = utc()

func ride(
    place = "Providencia", name = "Lo Barnechea and back", path = "/x/a.fit"
): ActivityInfo =
  ActivityInfo(
    startT: UnixTime(1597384860),
    sport: "cycling",
    subSport: "road",
    distanceM: some(36700.0),
    activeS: some(6060.0),
    place: place,
    name: name,
    path: path,
  )

suite "importer: saying an activity":
  test "the line: start, sport, distance and active time, then place / name":
    check activityLine(ride(), zone) ==
      "2020-08-14 06:01  cycling  36.7km 1h41m  Providencia / Lo Barnechea and back"
  test "verbose: the sub-sport, and the path last":
    check activityLine(ride(), zone, verbose = true) ==
      "2020-08-14 06:01  cycling/road  36.7km 1h41m  Providencia / Lo Barnechea and back  /x/a.fit"
  test "the cells, to be lined up":
    check activityCells(ride(), zone, false) ==
      @[
        "2020-08-14 06:01", "cycling", "36.7km", "1h41m",
        "Providencia / Lo Barnechea and back",
      ]
    check activityCells(ride(), zone, true)[1] == "cycling/road" and
      activityCells(ride(), zone, true).len == 6
  test "place and name, whichever there are; nothing to say leaves the line short":
    check whereText("Providencia", "") == "Providencia"
    check whereText("", "around Recoleta") == "around Recoleta"
    check whereText("", "") == ""
    check activityLine(ride("", ""), zone) == "2020-08-14 06:01  cycling  36.7km 1h41m"
  test "no GPS is said where the place and name would be, only if there is nothing else":
    check whereText("", "", noPositions = true) == noGps
    check whereText("Providencia", "", noPositions = true) == "Providencia"
  test "the sport: the sub-sport only if verbose and it says something":
    check sportText("cycling", "road", false) == "cycling"
    check sportText("cycling", "road", true) == "cycling/road"
    check sportText("cycling", "generic", true) == "cycling"
    check sportText("", "", true) == "-"
  test "not recorded is a dash, in a line too":
    let a = ActivityInfo(startT: UnixTime(1597384860))
    check activityLine(a, zone) == "2020-08-14 06:01  -  - -"
  test "the zone moves the time":
    let plus2 = newTimezone(
      "+2",
      proc(t: Time): ZonedTime =
        ZonedTime(time: t, utcOffset: -7200, isDst: false),
      proc(t: Time): ZonedTime =
        ZonedTime(
          time: t - initDuration(seconds = 7200), utcOffset: -7200, isDst: false
        ),
    )
    check dateTimeText(UnixTime(1597384860), plus2) == "2020-08-14 08:01"
