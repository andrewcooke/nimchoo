import std/[options, sequtils, strutils, times, unicode, unittest]
import nimchoo/selection/table
import nimchoo/ui/style

let zone = utc()

const
  aug27 = 1535371200'i64            # 2018-08-27 12:00 UTC
  mar4 = 1520154720'i64             # 2018-03-04 09:12 UTC

func row(t: int64, sport = "cycling", sub = "", distance = -1.0, active = -1.0,
         file = "f.fit", user = "default", path = "/x/f.fit", place = "", position = ""): ListRow =
  ListRow(startT: t, sport: sport, subSport: sub,
          distanceM: if distance >= 0: some(distance) else: none(float),
          activeS: if active >= 0: some(active) else: none(float), file: file, user: user,
          path: path, place: place, position: position)

func texts(ls: seq[Line]): seq[string] =
  for l in ls: result.add l.text

suite "list table: pieces":
  test "the sport, with the sub-sport only if it says something":
    check sportLabel(row(0, "cycling", "road")) == "cycling/road"
    check sportLabel(row(0, "cycling", "generic")) == "cycling"
    check sportLabel(row(0, "cycling", "")) == "cycling"
    check sportLabel(row(0, "", "")) == "-"
    check sportLabel(row(0, "", "road")) == "-/road"
  test "distances in km, one decimal, commas from 1,000; with the unit for a sentence":
    check kmNumber(0.0) == "0.0"
    check kmNumber(102650.0) == "102.7"
    check kmNumber(1234567.0) == "1,234.6"
    check km(0.0) == "0.0km"
    check km(102650.0) == "102.7km"
    check km(5549.0) == "5.5km"
    check km(99950.0) == "100.0km"
    check km(1234567.0) == "1,234.6km"

suite "list table: the table":
  test "aligned, oldest first as given, the date and start in the zone":
    let lines = table(@[row(mar4, "cycling", "road", 102650.0, 16860.0),
                        row(aug27, "cycling", "", 5549.0, 1320.0)], zone, false, false).texts
    check lines == @[
      "date        start  sport            km  active",
      "2018-03-04  09:12  cycling/road  102.7   4h41m",
      "2018-08-27  12:00  cycling         5.5  22m00s"]
  test "not recorded is a dash":
    let lines = table(@[row(aug27, "", "")], zone, false, false).texts
    check lines[1] == "2018-08-27  12:00  -       -       -"
  test "the zone moves the date and the time":
    let plus2 = newTimezone("+2", proc(t: Time): ZonedTime = ZonedTime(time: t, utcOffset: -7200, isDst: false),
                            proc(t: Time): ZonedTime = ZonedTime(time: t - initDuration(seconds = 7200), utcOffset: -7200, isDst: false))
    check table(@[row(aug27)], plus2, false, false).texts[1].startsWith("2018-08-27  14:00")
  test "a user column, after the start, only if asked; verbose adds the path, last":
    let rows = @[row(mar4, "cycling", "", 1000.0, 60.0, "a.fit", "alice", "/x/a.fit"),
                 row(aug27, "running", "", 2000.0, 120.0, "bb.fit", "bob", "/y/bb.fit")]
    let withUser = table(rows, zone, true, false).texts
    check withUser[0] == "date        start  user   sport     km  active"
    check withUser[1] == "2018-03-04  09:12  alice  cycling  1.0   1m00s"
    let verbose = table(rows, zone, false, true).texts
    check verbose[0] == "date        start  sport     km  active  position  place  file"
    check verbose[1].endsWith("1m00s" & " ".repeat(19) & "/x/a.fit")     # (no position, no place: blank)
    check verbose[2].endsWith("2m00s" & " ".repeat(19) & "/y/bb.fit")
    check table(rows, zone, true, true).texts[0].startsWith("date        start  user   sport")
  test "verbose: where it started, aligned by characters, not bytes":
    let rows = @[row(mar4, "cycling", "", 1000.0, 60.0, "a.fit", "alice", "/x/a.fit", "Valparaíso, CL", "-33.0360,-71.6296"),
                 row(aug27, "cycling", "", 2000.0, 120.0, "b.fit", "alice", "/y/b.fit", "Zürich, CH (45km)", "47.3667,8.5500"),
                 row(aug27, "cycling", "", 2000.0, 120.0, "c.fit", "alice", "/z/c.fit", "Ñuñoa, CL", "-33.4473,-70.5828")]
    let t = table(rows, zone, false, true).texts
    check t[0] == "date        start  sport     km  active  position" & " ".repeat(9) & "  place" &
      " ".repeat(12) & "  file"
    check t[1].endsWith("1m00s  -33.0360,-71.6296  Valparaíso, CL" & " ".repeat(3) & "  /x/a.fit")   # (14 characters, 17 wide)
    check t[2].endsWith("2m00s  47.3667,8.5500" & " ".repeat(3) & "  Zürich, CH (45km)  /y/b.fit")
    check t[3].endsWith("2m00s  -33.4473,-70.5828  Ñuñoa, CL" & " ".repeat(8) & "  /z/c.fit")
    var starts: seq[int]
    for line in t: starts.add line.toRunes.find('/'.Rune) - 0   # (header has no slash)
    check starts[1] == starts[2] and starts[2] == starts[3]
    # the file column starts at the same character in every line
  test "no rows, no lines":
    check table(@[], zone, true, true).len == 0

suite "list table: places and padding":
  test "the place as text: its name, and how far if it is not close":
    check placeText("Santiago, CL", 3_000.0) == "Santiago, CL"
    check placeText("Santiago, CL", 10_000.0) == "Santiago, CL"
    check placeText("Coyhaique, CL", 180_400.0) == "Coyhaique, CL (180km)"
    check placeText("Coyhaique, CL", 10_001.0) == "Coyhaique, CL (10km)"
    check placeText("", 5.0) == ""
  test "the start as coordinates: lat,lon, four decimals; no GPS if there is no start":
    check positionText("-33.436213", "-70.608963") == "-33.4362,-70.6090"
    check positionText("38.7", "-9.1") == "38.7000,-9.1000"
    check positionText("0", "0") == "0.0000,0.0000"
    check positionText("", "") == "no GPS" and positionText("-33.4", "") == "no GPS"
    check positionText("x", "y") == "no GPS"                                 # (not numbers)
  test "padding counts characters":
    check padRight("Zürich", 8) == "Zürich  "
    check padLeft("Zürich", 8) == "  Zürich"
    check padRight("abc", 2) == "abc" and padLeft("abc", 2) == "abc"
    check padRight("日本", 4) == "日本  "

suite "list table: the last line":
  test "how many, and of how many":
    check footer(@[], some 74) == "0 of 74 activities"
    check footer(@[row(0)], some 1).startsWith("1 of 1 activities")
    check footer(@[row(0)]).startsWith("1 activity")
    check footer(@[row(0), row(1)]).startsWith("2 activities")
  test "totals count only what is recorded":
    check footer(@[row(0, distance = 1500.0, active = 600.0), row(1), row(2, distance = 500.0)]) ==
      "3 activities, 2.0km, 10m00s"
  test "a count by sport only when there are several, most first, ties by name":
    check footer(@[row(0, "cycling"), row(1, "cycling")]) == "2 activities, 0.0km, 0s"
    check footer(@[row(0, "running"), row(1, "cycling"), row(2, "running"), row(3, "swimming")]) ==
      "4 activities, 0.0km, 0s (2 running, 1 cycling, 1 swimming)"
    check footer(@[row(0, ""), row(1, "cycling")]).endsWith("(1 cycling, 1 unknown)")

suite "list table: looks":
  test "no GPS is dim; a position and a place name are not":
    let rows = @[row(aug27, "cycling", "", 1000.0, 60.0, position = "no GPS"),
                 row(aug27, "cycling", "", 1000.0, 60.0, place = "Santiago, CL", position = "-33.4362,-70.6090")]
    let t = table(rows, zone, false, true)
    proc lookOfText(i: int, text: string): Look =
      for sp in t[i]:
        if sp.text.contains(text): return sp.look
      raiseAssert "no cell with " & text
    check lookOfText(1, "no GPS").dim
    check not lookOfText(2, "Santiago").dim and not lookOfText(2, "-33.4362").dim
  proc lookOf(lines: seq[Line], rowIndex: int, prefix: string): Look =
    for sp in lines[rowIndex]:
      if sp.text.strip.startsWith(prefix): return sp.look
    raiseAssert "no cell " & prefix

  test "a plain row has no look at all":
    let lines = table(@[row(aug27, "cycling", "road", 5000.0, 600.0)], zone, false, false)
    for sp in lines[1]: check sp.look == Look()
  test "a transition is dim all through, even with zeros":
    let lines = table(@[row(aug27, "transition", "", 0.0, 0.0)], zone, false, false)
    for sp in lines[1]: check sp.look == Look(dim: true) or sp.text.strip == ""
    check lookOf(lines, 1, "0.0").fg == cNone
  test "not recorded is dim":
    let lines = table(@[row(aug27, "cycling", "", -1.0, -1.0)], zone, false, false)
    check lookOf(lines, 1, "-").dim
    check lines[1].countIt(it.look.dim and it.text.strip == "-") == 2
  test "a distance or active time that shows as zero is yellow; others are not":
    let zeros = table(@[row(aug27, "running", "", 0.0, 0.0)], zone, false, false)
    check lookOf(zeros, 1, "0.0").fg == cYellow
    check lookOf(zeros, 1, "0s").fg == cYellow
    let small = table(@[row(aug27, "running", "", 2.49, 2.1)], zone, false, false)     # shows as 0.0, 2s
    check small.texts[1].contains("0.0") and small.texts[1].endsWith("2s")
    check lookOf(small, 1, "0.0").fg == cYellow
    check lookOf(small, 1, "2s").fg == cYellow
    let notYet = table(@[row(aug27, "running", "", 60.0, 40.0)], zone, false, false)   # 0.1, 40s
    check lookOf(notYet, 1, "0.1").fg == cNone
    check lookOf(notYet, 1, "40s").fg == cNone
    let onlyActive = table(@[row(aug27, "running", "", 5000.0, 0.0)], zone, false, false)
    check lookOf(onlyActive, 1, "5.0").fg == cNone
    check lookOf(onlyActive, 1, "0s").fg == cYellow
  test "the header has no look":
    for sp in table(@[row(aug27)], zone, false, false)[0]: check sp.look == Look()
