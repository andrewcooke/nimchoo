import std/[math, options, sequtils, strutils, times, unicode, unittest]
import nimchoo/packages/fit/time
import nimchoo/packages/activities/table
import nimchoo/packages/ui/style
import ../support/styles

let zone = utc()

const
  aug27 = 1535371200'i64 # 2018-08-27 12:00 UTC
  mar4 = 1520154720'i64 # 2018-03-04 09:12 UTC

func row(
    t: int64,
    sport = "cycling",
    sub = "",
    distance = -1.0,
    active = 0.0,
    path = "/x/f.fit",
    place = "",
    position = "",
    selected = false,
    name = "",
): ListRow =
  ListRow(
    startT: UnixTime(t),
    sport: sport,
    subSport: sub,
    distanceM:
      if distance >= 0:
        some(distance)
      else:
        none(float),
    activeS: active,
    path: path,
    place: place,
    name: name,
    position: position,
    selected: selected,
  )

func texts(ls: seq[Line]): seq[string] =
  for l in ls:
    result.add l.text

suite "list table: the last line":
  test "found, not the selection: the plain line, whatever rows are selected":
    let rows = @[
      row(0, "cycling", "", 1500.0, 600.0, selected = true),
      row(1, "cycling", "", 500.0, 60.0),
    ]
    check footerLine(rows, some 5).text == "done: 2 of 5 activities, 2.0km, 11m00s"
    check footerLine(rows, some 5).allIt(styleOf(it) == "")
    check "selected" notin footerLine(rows, some 5).text # (the rows' colour says which)
  test "the selection (listed, or just saved): the count in the select style, and nothing more said":
    let rows = @[row(0, selected = true), row(1, selected = true)]
    let l = footerLine(rows, some 1113, isSelection = true)
    check l.text.startsWith("done: 2 of 1,113 activities")
    check l.filterIt(styleOf(it) == "select").mapIt(it.text) == @["2"]
    check footerLine(rows, some 1113, isSelection = true, marks = true).text.startsWith(
      "done: [2] of 1,113 activities"
    ) # (where there is no colour, in brackets)
  test "a count with no totals":
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
    let lines = table(
      @[
        row(mar4, "cycling", "road", 102650.0, 16860.0),
        row(aug27, "cycling", "", 5549.0, 1320.0),
      ],
      zone,
      false,
      120,
    ).texts
    check lines ==
      @[
        "start            │ sport   │ distance │ active │ place / name",
        "─────────────────┼─────────┼──────────┼────────┼─────────────",
        "2018-03-04 09:12 │ cycling │  102.7km │  4h41m",
        "2018-08-27 12:00 │ cycling │    5.5km │ 22m00s",
      ] # (a table, `core/ruled.nim`; nothing in the last column: no line before it)
  test "the place and the name, joined; whichever there is":
    let lines = table(
      @[
        row(
          mar4,
          "cycling",
          "road",
          36700.0,
          6060.0,
          place = "Providencia",
          name = "Lo Barnechea and back",
        ),
        row(aug27, "cycling", "", 5549.0, 1320.0, place = "Providencia"),
        row(aug27, "cycling", "", 5549.0, 1320.0, name = "around Recoleta"),
      ],
      zone,
      false,
      120,
    ).texts
    check lines[2].endsWith("36.7km │  1h41m │ Providencia / Lo Barnechea and back")
    check lines[3].endsWith("5.5km │ 22m00s │ Providencia")
    check lines[4].endsWith("5.5km │ 22m00s │ around Recoleta")
  test "not recorded (the sport, the distance) is a dash":
    let lines = table(@[row(aug27, "", "")], zone, false, 120).texts
    check lines[2] == "2018-08-27 12:00 │ -     │        - │     0s"
  test "the zone moves the date and the time":
    let plus2 = newTimezone(
      "+2",
      proc(t: Time): ZonedTime =
        ZonedTime(time: t, utcOffset: -7200, isDst: false),
      proc(t: Time): ZonedTime =
        ZonedTime(
          time: t - initDuration(seconds = 7200), utcOffset: -7200, isDst: false
        ),
    )
    check table(@[row(aug27)], plus2, false, 120).texts[2].startsWith(
      "2018-08-27 14:00"
    )
  test "verbose adds the sub-sport, the tags and the path, last":
    let rows = @[
      row(mar4, "cycling", "road", 1000.0, 60.0, "/x/a.fit"),
      row(aug27, "running", "", 2000.0, 120.0, "/y/bb.fit"),
    ]
    let plain = table(rows, zone, false, 120).texts
    check plain[0] ==
      "start            │ sport   │ distance │ active │ place / name"
    check plain[2] == "2018-03-04 09:12 │ cycling │    1.0km │  1m00s"
    let verbose = table(rows, zone, true, 120).texts
    check verbose[0] ==
      "start            │ sport        │ distance │ active │ place / name │ tags │ path"
    check verbose[2] ==
      "2018-03-04 09:12 │ cycling/road │    1.0km │  1m00s │              │      │ /x/a.fit"
    check verbose[3] ==
      "2018-08-27 12:00 │ running      │    2.0km │  2m00s │              │      │ /y/bb.fit"
  test "verbose: where it started and what it is called, aligned by characters, not bytes; no GPS said where they would be":
    let rows = @[
      row(
        mar4,
        "cycling",
        "",
        1000.0,
        60.0,
        "/x/a.fit",
        "Valparaíso",
        "-33.0360,-71.6296",
        name = "Quillota and back",
      ),
      row(aug27, "cycling", "", 2000.0, 120.0, "/y/b.fit", "Zürich", "47.3667,8.5500"),
      row(aug27, "swimming", "", 2000.0, 120.0, "/z/c.fit", "", "no GPS"),
    ]
    let t = table(rows, zone, true, 120).texts
    check t[2].endsWith(
      "1m00s │ Valparaíso / Quillota and back │      │ /x/a.fit"
    )
    check t[3].endsWith("2m00s │ Zürich" & " ".repeat(24) & " │      │ /y/b.fit")
      # (padded to the width of the longest)
    check t[4].endsWith("2m00s │ no GPS" & " ".repeat(24) & " │      │ /z/c.fit")
    # the path column starts at the same character in every line (they all end in a path of the same length)
    check t[2].runeLen == t[3].runeLen and t[3].runeLen == t[4].runeLen
  test "no GPS is said only if verbose (the positions are not read otherwise)":
    let r = row(mar4, "cycling", "", 1000.0, 60.0, position = "no GPS")
    check table(@[r], zone, false, 120).texts[2].endsWith("1.0km │  1m00s")
    check table(@[r], zone, true, 120).texts[2].contains("no GPS")
  test "no rows, no lines":
    check table(@[], zone, true, 120).len == 0
  test "an activity said in a sentence, the standard way":
    check activityText(
      row(
        mar4,
        "cycling",
        "road",
        36700.0,
        6060.0,
        place = "Providencia",
        name = "Lo Barnechea and back",
      ),
      zone,
    ) == "2018-03-04 09:12  cycling  36.7km 1h41m  Providencia / Lo Barnechea and back"
    check activityText(row(aug27, "running", "", 0.0, 2.0), zone) ==
      "2018-08-27 12:00  running  0.0km 2s"

suite "list table: positions":
  test "the start as every position is written; no GPS if there is no start":
    check startText(some(-33.436213), some(-70.608963)) == "-33.4362,-70.6090"
    check startText(none(float), none(float)) == "no GPS"
    check startText(some(-33.4), none(float)) == "no GPS"

suite "list table: the last line":
  test "how many, and of how many; the noun agrees with the last number":
    check footerLine(@[], some 74).text == "done: 0 of 74 activities"
    check footerLine(@[row(0)], some 1).text.startsWith("done: 1 of 1 activity")
    check footerLine(@[row(0)]).text.startsWith("done: 1 activity")
    check footerLine(@[row(0), row(1)]).text.startsWith("done: 2 activities")
    check footerLine(@[row(0)], some 2).text.startsWith("done: 1 of 2 activities")
  test "totals count only what is recorded":
    check footerLine(
      @[row(0, distance = 1500.0, active = 600.0), row(1), row(2, distance = 500.0)]
    ).text == "done: 3 activities, 2.0km, 10m00s"
  test "a count by sport only when there are several, most first, ties by name, with commas":
    check footerLine(@[row(0, "cycling"), row(1, "cycling")]).text ==
      "done: 2 activities, 0.0km, 0s"
    check footerLine(
      @[row(0, "running"), row(1, "cycling"), row(2, "running"), row(3, "swimming")]
    ).text == "done: 4 activities, 0.0km, 0s (2 running, 1 cycling, 1 swimming)"
    check footerLine(@[row(0, ""), row(1, "cycling")]).text.endsWith(
      "(1 cycling, 1 none)"
    ) # (as `--sports none` says it)
    var many: seq[ListRow]
    for k in 0 ..< 1200:
      many.add row(k, "cycling")
    many.add row(1200, "running")
    check footerLine(many).text.endsWith("(1,200 cycling, 1 running)")

suite "list table: looks":
  test "a row in the selection is in the select style all through; the others are not":
    let rows = @[
      row(aug27, "cycling", "", 1000.0, 60.0, selected = true),
      row(aug27, "running", "", 2000.0, 90.0),
      row(aug27, "transition", "", -1.0, -1.0, selected = true),
    ]
    let t = table(rows, zone, false, 120)
    for sp in t[2]:
      check styleOf(sp) == "select" or sp.text.strip == ""
    for sp in t[3]:
      check styleOf(sp) != "select" or sp.text.strip == ""
    for sp in t[4]:
      check styleOf(sp) == "hide" or sp.text.strip == ""
      # (a transition stays dim)
    for sp in t[0]:
      check styleOf(sp) == ""
      # (the header is plain)
  test "a selected row with a missing value is in the select style too, not hidden":
    let t =
      table(@[row(aug27, "cycling", "", -1.0, -1.0, selected = true)], zone, false, 120)
    for sp in t[2]:
      check styleOf(sp) == "select" or sp.text.strip == ""
  test "no GPS is dim; a position and a place name are not":
    let rows = @[
      row(aug27, "cycling", "", 1000.0, 60.0, position = "no GPS"),
      row(
        aug27,
        "cycling",
        "",
        1000.0,
        60.0,
        place = "Santiago, CL",
        position = "-33.4362,-70.6090",
      ),
    ]
    let t = table(rows, zone, true, 120)
    proc lookOfText(i: int, text: string): string =
      for sp in t[i]:
        if sp.text.contains(text):
          return styleOf(sp)
      raiseAssert "no cell with " & text

    check lookOfText(2, "no GPS") == "hide"
    check lookOfText(3, "Santiago") != "hide"
  proc lookOf(lines: seq[Line], rowIndex: int, prefix: string): string =
    for sp in lines[rowIndex]:
      if sp.text.strip.startsWith(prefix) or (" " & prefix) in sp.text:
        return styleOf(sp) # (cells of the same style side by side are one span)
    raiseAssert "no cell " & prefix

  test "a plain row has no style at all":
    let lines = table(@[row(aug27, "cycling", "road", 5000.0, 600.0)], zone, false, 120)
    for sp in lines[2]:
      check sp.styles.len == 0
  test "a transition is dim all through, even with zeros":
    let lines = table(@[row(aug27, "transition", "", 0.0, 0.0)], zone, false, 120)
    for sp in lines[2]:
      check styleOf(sp) == "hide" or sp.text.strip == ""
    check lookOf(lines, 2, "0.0") == "hide"
  test "not recorded is dim":
    let lines = table(@[row(aug27, "cycling", "", -1.0, 600.0)], zone, false, 120)
    check lookOf(lines, 2, "-") == "hide"
    check lines[2].filterIt(styleOf(it) == "hide").mapIt(it.text.count('-')).sum == 1
  test "a distance or active time that shows as zero is a warning; others are not":
    let zeros = table(@[row(aug27, "running", "", 0.0, 0.0)], zone, false, 120)
    check lookOf(zeros, 2, "0.0") == "warn"
    check lookOf(zeros, 2, "0s") == "warn"
    let small = table(@[row(aug27, "running", "", 2.49, 2.1)], zone, false, 120)
      # shows as 0.0, 2s
    check small.texts[2].contains("0.0") and small.texts[2].endsWith("2s")
    check lookOf(small, 2, "0.0") == "warn"
    check lookOf(small, 2, "2s") == "warn"
    let notYet = table(@[row(aug27, "running", "", 60.0, 40.0)], zone, false, 120)
      # 0.1, 40s
    check lookOf(notYet, 2, "0.1") == ""
    check lookOf(notYet, 2, "40s") == ""
    let onlyActive = table(@[row(aug27, "running", "", 5000.0, 0.0)], zone, false, 120)
    check lookOf(onlyActive, 2, "5.0") == ""
    check lookOf(onlyActive, 2, "0s") == "warn"
  test "the header has no style":
    for sp in table(@[row(aug27)], zone, false, 120)[0]:
      check sp.styles.len == 0

suite "activities table: marks where there is no colour":
  test "the selected rows are in brackets, and every line is a column further in":
    var picked = row(aug27, "cycling", "road", 5000.0, 600.0)
    picked.selected = true
    let other = row(aug27, "running", "", 3000.0, 900.0)
    let plainLines = table(@[picked, other], zone, false, 120)
    let marked = table(@[picked, other], zone, false, 120, marks = true)
    check marked[0].text == " " & plainLines[0].text
    check marked[1].text == " " & plainLines[1].text # (the rule)
    check marked[2].text == "[" & plainLines[2].text & "]"
    check marked[3].text == " " & plainLines[3].text
