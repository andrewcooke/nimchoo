import std/[options, sequtils, strutils, times, unicode, unittest]
import nimchoo/fit/time
import nimchoo/selection/table
import nimchoo/ui/style

let zone = utc()

const
  aug27 = 1535371200'i64            # 2018-08-27 12:00 UTC
  mar4 = 1520154720'i64             # 2018-03-04 09:12 UTC

func row(t: int64, sport = "cycling", sub = "", distance = -1.0, active = -1.0,
         file = "f.fit", user = "default", path = "/x/f.fit", place = "", position = "",
         selected = false, name = ""): ListRow =
  ListRow(startT: UnixTime(t), sport: sport, subSport: sub,
          distanceM: if distance >= 0: some(distance) else: none(float),
          activeS: if active >= 0: some(active) else: none(float), file: file, user: user,
          path: path, place: place, name: name, position: position, selected: selected)

func texts(ls: seq[Line]): seq[string] =
  for l in ls: result.add l.text

suite "list table: the last line":
  test "nothing selected: the plain line":
    let rows = @[row(0, "cycling", "", 1500.0, 600.0), row(1, "cycling", "", 500.0, 60.0)]
    check footerLine(rows, some 5).text == "done: " & footer(rows, some 5)
    check footerLine(rows, some 5).allIt(it.look.colour == white)
  test "some selected: the count in yellow, after the number of activities":
    let rows = @[row(0, "cycling", "", 1500.0, 600.0, selected = true), row(1, "cycling", "", 500.0, 60.0),
                 row(2, "cycling", "", 500.0, 60.0, selected = true)]
    let l = footerLine(rows, some 5)
    check l.text == "done: 3 of 5 activities, 2 match selected, 2.5km, 12m00s"
    check l.filterIt(it.look.colour == yellow).mapIt(it.text) == @[", 2 match selected"]
    check footerLine(rows).text.startsWith("done: 3 activities, 2 match selected, ")
  test "all selected, and a count with no totals":
    let rows = @[row(0, selected = true)]
    check footerLine(rows, some 1).text.startsWith("done: 1 of 1 activities, 1 match selected")
    check footerLine(@[], some 3).text == "done: 0 of 3 activities"

suite "list table: pieces":
  test "the sport; verbose, with the sub-sport only if it says something":
    check sportText("cycling", "road", false) == "cycling"
    check sportText("cycling", "road", true) == "cycling/road"
    check sportText("cycling", "generic", true) == "cycling"
    check sportText("cycling", "", true) == "cycling"
    check sportText("", "", false) == "-"
    check sportText("", "road", true) == "-/road"
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
  test "aligned, oldest first as given, the start in the zone; the distance and the active time to the right":
    let lines = table(@[row(mar4, "cycling", "road", 102650.0, 16860.0),
                        row(aug27, "cycling", "", 5549.0, 1320.0)], zone, false).texts
    check lines == @[
      "start             sport    distance  active  place / name",
      "2018-03-04 09:12  cycling   102.7km   4h41m",
      "2018-08-27 12:00  cycling     5.5km  22m00s"]
  test "the place and the name, joined; whichever there is":
    let lines = table(@[row(mar4, "cycling", "road", 36700.0, 6060.0, place = "Providencia", name = "Lo Barnechea and back"),
                        row(aug27, "cycling", "", 5549.0, 1320.0, place = "Providencia"),
                        row(aug27, "cycling", "", 5549.0, 1320.0, name = "around Recoleta")], zone, false).texts
    check lines[1].endsWith("36.7km   1h41m  Providencia / Lo Barnechea and back")
    check lines[2].endsWith("5.5km  22m00s  Providencia")
    check lines[3].endsWith("5.5km  22m00s  around Recoleta")
  test "not recorded is a dash":
    let lines = table(@[row(aug27, "", "")], zone, false).texts
    check lines[1] == "2018-08-27 12:00  -             -       -"
  test "the zone moves the date and the time":
    let plus2 = newTimezone("+2", proc(t: Time): ZonedTime = ZonedTime(time: t, utcOffset: -7200, isDst: false),
                            proc(t: Time): ZonedTime = ZonedTime(time: t - initDuration(seconds = 7200), utcOffset: -7200, isDst: false))
    check table(@[row(aug27)], plus2, false).texts[1].startsWith("2018-08-27 14:00")
  test "verbose adds the sub-sport and the path, last":
    let rows = @[row(mar4, "cycling", "road", 1000.0, 60.0, "a.fit", "alice", "/x/a.fit"),
                 row(aug27, "running", "", 2000.0, 120.0, "bb.fit", "bob", "/y/bb.fit")]
    let plain = table(rows, zone, false).texts
    check plain[0] == "start             sport    distance  active  place / name"
    check plain[1] == "2018-03-04 09:12  cycling     1.0km   1m00s"
    let verbose = table(rows, zone, true).texts
    check verbose[0] == "start             sport         distance  active  place / name  path"
    check verbose[1] == "2018-03-04 09:12  cycling/road     1.0km   1m00s                /x/a.fit"
    check verbose[2] == "2018-08-27 12:00  running          2.0km   2m00s                /y/bb.fit"
  test "verbose: where it started and what it is called, aligned by characters, not bytes; no GPS said where they would be":
    let rows = @[row(mar4, "cycling", "", 1000.0, 60.0, "a.fit", "alice", "/x/a.fit", "Valparaíso", "-33.0360,-71.6296", name = "Quillota and back"),
                 row(aug27, "cycling", "", 2000.0, 120.0, "b.fit", "alice", "/y/b.fit", "Zürich", "47.3667,8.5500"),
                 row(aug27, "swimming", "", 2000.0, 120.0, "c.fit", "alice", "/z/c.fit", "", "no GPS")]
    let t = table(rows, zone, true).texts
    check t[1].endsWith("1m00s  Valparaíso / Quillota and back  /x/a.fit")
    check t[2].endsWith("2m00s  Zürich" & " ".repeat(24) & "  /y/b.fit")             # (padded to the width of the longest)
    check t[3].endsWith("2m00s  no GPS" & " ".repeat(24) & "  /z/c.fit")
    # the path column starts at the same character in every line (they all end in a path of the same length)
    check t[1].runeLen == t[2].runeLen and t[2].runeLen == t[3].runeLen
  test "no GPS is said only if verbose (the positions are not read otherwise)":
    let r = row(mar4, "cycling", "", 1000.0, 60.0, position = "no GPS")
    check table(@[r], zone, false).texts[1].endsWith("1.0km   1m00s")
    check table(@[r], zone, true).texts[1].contains("no GPS")
  test "no rows, no lines":
    check table(@[], zone, true).len == 0
  test "an activity said in a sentence, the standard way":
    check activityText(row(mar4, "cycling", "road", 36700.0, 6060.0, place = "Providencia", name = "Lo Barnechea and back"), zone) ==
      "2018-03-04 09:12  cycling  36.7km 1h41m  Providencia / Lo Barnechea and back"
    check activityText(row(aug27, "running", "", 0.0, 2.0), zone) == "2018-08-27 12:00  running  0.0km 2s"

suite "list table: positions and padding":
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
  test "a row in the selection is yellow all through; the others are not":
    let rows = @[row(aug27, "cycling", "", 1000.0, 60.0, selected = true),
                 row(aug27, "running", "", 2000.0, 90.0),
                 row(aug27, "transition", "", -1.0, -1.0, selected = true)]
    let t = table(rows, zone, false)
    for sp in t[1]: check sp.look.colour == yellow or sp.text.strip == ""
    for sp in t[2]: check sp.look.colour != yellow or sp.text.strip == ""
    for sp in t[3]: check sp.look.colour == grey or sp.text.strip == ""          # (a transition stays dim)
    for sp in t[0]: check sp.look.colour == white                                  # (the header is plain)
  test "a selected row with a missing value is yellow too, not grey":
    let t = table(@[row(aug27, "cycling", "", -1.0, -1.0, selected = true)], zone, false)
    for sp in t[1]: check sp.look.colour == yellow or sp.text.strip == ""
  test "no GPS is dim; a position and a place name are not":
    let rows = @[row(aug27, "cycling", "", 1000.0, 60.0, position = "no GPS"),
                 row(aug27, "cycling", "", 1000.0, 60.0, place = "Santiago, CL", position = "-33.4362,-70.6090")]
    let t = table(rows, zone, true)
    proc lookOfText(i: int, text: string): Look =
      for sp in t[i]:
        if sp.text.contains(text): return sp.look
      raiseAssert "no cell with " & text
    check lookOfText(1, "no GPS").colour == grey
    check lookOfText(2, "Santiago").colour != grey
  proc lookOf(lines: seq[Line], rowIndex: int, prefix: string): Look =
    for sp in lines[rowIndex]:
      if sp.text.strip.startsWith(prefix): return sp.look
    raiseAssert "no cell " & prefix

  test "a plain row has no look at all":
    let lines = table(@[row(aug27, "cycling", "road", 5000.0, 600.0)], zone, false)
    for sp in lines[1]: check sp.look == Look()
  test "a transition is dim all through, even with zeros":
    let lines = table(@[row(aug27, "transition", "", 0.0, 0.0)], zone, false)
    for sp in lines[1]: check sp.look == Look(colour: grey) or sp.text.strip == ""
    check lookOf(lines, 1, "0.0").colour == grey
  test "not recorded is dim":
    let lines = table(@[row(aug27, "cycling", "", -1.0, -1.0)], zone, false)
    check lookOf(lines, 1, "-").colour == grey
    check lines[1].countIt(it.look.colour == grey and it.text.strip == "-") == 2
  test "a distance or active time that shows as zero is yellow; others are not":
    let zeros = table(@[row(aug27, "running", "", 0.0, 0.0)], zone, false)
    check lookOf(zeros, 1, "0.0").colour == yellow
    check lookOf(zeros, 1, "0s").colour == yellow
    let small = table(@[row(aug27, "running", "", 2.49, 2.1)], zone, false)     # shows as 0.0, 2s
    check small.texts[1].contains("0.0") and small.texts[1].endsWith("2s")
    check lookOf(small, 1, "0.0").colour == yellow
    check lookOf(small, 1, "2s").colour == yellow
    let notYet = table(@[row(aug27, "running", "", 60.0, 40.0)], zone, false)   # 0.1, 40s
    check lookOf(notYet, 1, "0.1").colour == white
    check lookOf(notYet, 1, "40s").colour == white
    let onlyActive = table(@[row(aug27, "running", "", 5000.0, 0.0)], zone, false)
    check lookOf(onlyActive, 1, "5.0").colour == white
    check lookOf(onlyActive, 1, "0s").colour == yellow
  test "the header has no look":
    for sp in table(@[row(aug27)], zone, false)[0]: check sp.look == Look()
