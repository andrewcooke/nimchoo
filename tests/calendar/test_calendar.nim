import std/[options, sequtils, strutils, tables, times, unittest]
import nimchoo/packages/fit/time
import nimchoo/packages/calendar/calendar
import nimchoo/packages/ui/[style, vocabulary]
import ../support/zones
import ../support/styles

proc at(y: int, m: Month, d: int, h = 12, min = 0): int64 =
  dateTime(y, m, d, h, min, 0, 0, utc()).toTime.toUnix

proc row(t: int64): UnixTime =
  ## a mark (the calendar is given instants)
  UnixTime(t)

let colourScreen = Screen(colour: true)
let plainScreen = Screen(colour: false)
let later = UnixTime(2_000_000_000) # ("now", for the tests that do not run to it)

proc monthRow(ls: seq[Line], name: string): Line =
  for l in ls:
    if l.text.startsWith(name & " "):
      return l
  raiseAssert "no row for " & name

proc cellOf(l: Line, k: int): Span =
  ## cell k (0 to 36) of a month row in colour: the spans are the label, a space and a cell 37 times, a space, the year
  l[2 + 2 * k]

proc plainCellOf(l: Line, k: int): Span =
  ## cell k of a month row without colour: after the label (4 columns), each cell is 5 columns
  let text = l.text
  span(text[4 + 5 * k ..< 4 + 5 * (k + 1)])

suite "calendar: the layout":
  test "a header of weekday names (Monday first), then a row for each month with an activity":
    let ls = calendarLines(
      @[row(at(2018, mAug, 27)), row(at(2018, mFeb, 3))],
      @[],
      utc(),
      dtData,
      later,
      colourScreen,
    )
    check ls.len == 3
    check ls[0].text == "    " & "Mo Tu We Th Fr Sa Su ".repeat(5) & "Mo Tu "
    check ls[1].text.startsWith("Feb ") and ls[2].text.startsWith("Aug ")
      # (in time order)
    check ls[1].text.endsWith("  2018") and ls[2].text.endsWith("  2018")
      # the year on every row
  test "days sit in the column of their weekday: 1 August 2018 was a Wednesday":
    let ls =
      calendarLines(@[row(at(2018, mAug, 27))], @[], utc(), dtData, later, colourScreen)
    let aug = ls.monthRow("Aug")
    check aug.cellOf(0).text == "  " and aug.cellOf(1).text == "  "
    check aug.cellOf(2).text == "01" and aug.cellOf(2 + 30).text == "31"
    check aug.cellOf(2 + 31).text == "  "
    # the 27th was a Monday: the same column as the first Monday, 6 August, and 13th, 20th
    check aug.cellOf(2 + 26).text == "27" and (2 + 26) mod 7 == 0
  test "a 31-day month that starts on a Sunday fills all 37 cells (January 2017)":
    let jan = calendarLines(
        @[row(at(2017, mJan, 5))], @[], utc(), dtData, later, colourScreen
      )
      .monthRow("Jan")
    check jan.cellOf(6).text == "01" and jan.cellOf(36).text == "31"
    check jan.len == 1 + 2 * 37 + 1 + 1
  test "February: 28 days, and 29 in a leap year":
    check calendarLines(
      @[row(at(2018, mFeb, 5))], @[], utc(), dtData, later, colourScreen
    )
      .monthRow("Feb").text
      .count("29") == 0
    check calendarLines(
      @[row(at(2016, mFeb, 5))], @[], utc(), dtData, later, colourScreen
    )
      .monthRow("Feb").text
      .contains("29")
  test "months across years, with the year at the right":
    let ls = calendarLines(
      @[row(at(2018, mJan, 2)), row(at(2017, mDec, 30))],
      @[],
      utc(),
      dtData,
      later,
      colourScreen,
    )
    check ls[1].text.startsWith("Dec ") and ls[1].text.endsWith("2017")
    check ls[2].text.startsWith("Jan ") and ls[2].text.endsWith("2018")
  test "only months with data, unless every month is asked for":
    let rs = @[row(at(2018, mMar, 5)), row(at(2018, mJun, 5))]
    check calendarLines(rs, @[], utc(), dtData, later, colourScreen).len == 3
    let all = calendarLines(rs, @[], utc(), dtRange, later, colourScreen)
    check all.len == 1 + 4
    check all.mapIt(it.text[0 .. 2]) == @["   ", "Mar", "Apr", "May", "Jun"]
    check all[2].filterIt(styleOf(it) == "hide").len == 30 and
      all[2].allIt(styleOf(it) != "warn") # April: 30 days, none listed
  test "nothing listed: nothing":
    check calendarLines(@[], @[], utc(), dtRange, later, colourScreen).len == 0

suite "calendar: colours and marks":
  let rs = @[
    row(at(2018, mAug, 27)),
    row(at(2018, mAug, 28)),
    row(at(2018, mAug, 29)),
    row(at(2018, mAug, 29)),
  ]
  test "select: listed; hide: none":
    let aug = calendarLines(rs, @[], utc(), dtData, later, colourScreen).monthRow("Aug")
    check styleOf(aug.cellOf(2 + 26)) == "select" # the 27th
    check styleOf(aug.cellOf(2 + 27)) == "select" # the 28th
    check styleOf(aug.cellOf(2 + 28)) == "select" # the 29th: two activities
    check styleOf(aug.cellOf(2 + 25)) == "hide" # the 26th: nothing
    check styleOf(aug.cellOf(2)) == "hide" # the 1st
  test "without colour the cells are 5 wide and marked":
    let aug = calendarLines(rs, @[], utc(), dtData, later, plainScreen).monthRow("Aug")
    check aug.plainCellOf(2 + 26).text == " [27]"
    check aug.plainCellOf(2 + 27).text == " [28]"
    check aug.plainCellOf(2 + 25).text == "  -- "
    check aug.plainCellOf(0).text == "     "
    check aug.text.len == 4 + 37 * 5 + 6

  test "a day of the background (an activity, not marked) is plain, with colour and without":
    let background = @[row(at(2018, mAug, 26)), row(at(2018, mAug, 27))]
    let aug =
      calendarLines(rs, background, utc(), dtData, later, colourScreen).monthRow("Aug")
    check styleOf(aug.cellOf(2 + 25)) == "" # the 26th: an activity, not marked
    check styleOf(aug.cellOf(2 + 26)) == "select"
      # the 27th: marked, whatever the background
    check styleOf(aug.cellOf(2 + 24)) == "hide" # the 25th: nothing
    let plain =
      calendarLines(rs, background, utc(), dtData, later, plainScreen).monthRow("Aug")
    check plain.plainCellOf(2 + 25).text == "  26 "
    check calendarLines(rs, @[], utc(), dtData, later, plainScreen)[0].text.startsWith(
      "      Mo "
    )
  test "everything is plain text that stays the same width":
    for screen in [colourScreen, plainScreen]:
      let ls = calendarLines(rs, @[], utc(), dtRange, later, screen)
      for l in ls[1 .. ^1]:
        check l.width == calendarWidth(screen)

suite "calendar: months left out":
  test "how many months between the first and the last have nothing":
    proc rowsIn(ms: seq[(int, Month)]): seq[UnixTime] =
      for (y, m) in ms:
        result.add row(at(y, m, 5))

    check skippedMonths(rowsIn(@[(2018, mMar), (2018, mJul)]), utc()) == 3
      # April, May, June
    check skippedMonths(rowsIn(@[(2017, mDec), (2018, mFeb)]), utc()) == 1 # January
    check skippedMonths(rowsIn(@[(2018, mMar), (2018, mApr), (2018, mMay)]), utc()) == 0
    check skippedMonths(rowsIn(@[(2018, mMar)]), utc()) == 0
    check skippedMonths(@[], utc()) == 0
    check skippedMonths(rowsIn(@[(2018, mMar), (2018, mMar), (2018, mJul)]), utc()) == 3
      # (a month once, however many days)

suite "calendar: the months either side of a gap":
  proc rowsIn(ms: seq[(int, Month)]): seq[UnixTime] =
    for (y, m) in ms:
      result.add row(at(y, m, 5))

  proc labelColours(ls: seq[Line]): seq[string] =
    for l in ls[1 .. ^1]:
      result.add styleOf(l[0])

  test "their names are in the warning style; the others are not":
    # Jan Feb | Apr | Jun Jul Aug | Dec: gaps after Feb, around Apr, after Aug
    let rs = rowsIn(
      @[
        (2018, mJan),
        (2018, mFeb),
        (2018, mApr),
        (2018, mJun),
        (2018, mJul),
        (2018, mAug),
        (2018, mDec),
      ]
    )
    let ls = calendarLines(rs, @[], utc(), dtData, later, colourScreen)
    check ls[1 ..^ 1].mapIt(it.text[0 .. 2]) ==
      @["Jan", "Feb", "Apr", "Jun", "Jul", "Aug", "Dec"]
    check labelColours(ls) == @["", "warn", "warn", "warn", "", "warn", "warn"]
  test "no gap, no warning; with every month asked for, none either":
    let rs = rowsIn(@[(2018, mMar), (2018, mApr), (2018, mMay)])
    check labelColours(calendarLines(rs, @[], utc(), dtData, later, colourScreen)).allIt(
      it == ""
    )
    let gappy = rowsIn(@[(2018, mMar), (2018, mJun)])
    check labelColours(calendarLines(gappy, @[], utc(), dtRange, later, colourScreen))
      .allIt(it == "")
    check labelColours(calendarLines(gappy, @[], utc(), dtData, later, colourScreen)) ==
      @["warn", "warn"]
  test "a gap between years counts (December to February)":
    let ls = calendarLines(
      rowsIn(@[(2017, mDec), (2018, mFeb)]), @[], utc(), dtData, later, colourScreen
    )
    check labelColours(ls) == @["warn", "warn"]
  test "without colour a star follows the name, and the width does not change":
    let ls = calendarLines(
      rowsIn(@[(2018, mMar), (2018, mJun)]), @[], utc(), dtData, later, plainScreen
    )
    check ls[1].text.startsWith("Mar*") and ls[2].text.startsWith("Jun*")
    check ls[1].width == calendarWidth(plainScreen) and
      ls[2].width == calendarWidth(plainScreen)
    check calendarLines(
      rowsIn(@[(2018, mMar), (2018, mApr)]), @[], utc(), dtData, later, plainScreen
    )[1].text.startsWith("Mar ")

suite "calendar: time zones":
  test "a day is the day where the user is, not in UTC":
    # 20:00 UTC on the 27th is 06:00 on the 28th at +10, and 17:00 on the 27th at -03
    let t = at(2018, mAug, 27, 20)
    let east = calendarLines(
        @[row(t)], @[], fixedZone("+10", 10 * 3600), dtData, later, colourScreen
      )
      .monthRow("Aug")
    check styleOf(east.cellOf(2 + 27)) == "select" and
      styleOf(east.cellOf(2 + 26)) == "hide"
    let west = calendarLines(
        @[row(t)], @[], fixedZone("-03", -3 * 3600), dtData, later, colourScreen
      )
      .monthRow("Aug")
    check styleOf(west.cellOf(2 + 26)) == "select" and
      styleOf(west.cellOf(2 + 27)) == "hide"
  test "near the end of a month, the month changes with the zone":
    let t = at(2018, mAug, 31, 20) # 06:00 on 1 September at +10
    let ls = calendarLines(
      @[row(t)], @[], fixedZone("+10", 10 * 3600), dtData, later, colourScreen
    )
    check ls.len == 2 and ls[1].text.startsWith("Sep ")

suite "calendar: too narrow a screen":
  test "a warning first, then every line cut to the screen":
    let rs = @[row(at(2018, mAug, 27))]
    let ls = calendarLines(
      rs, @[], utc(), dtData, later, Screen(colour: true, width: some(60))
    )
    check ls.len == 3
    check styleOf(ls[0][0]) == "warn" and
      ls[0].text.startsWith("the calendar needs 121 columns and the screen has 60")
    for l in ls[1 .. ^1]:
      check l.width == 60 and l.text.endsWith("…")
  test "wide enough, or no limit: no warning, no cutting":
    let rs = @[row(at(2018, mAug, 27))]
    check calendarLines(
      rs, @[], utc(), dtData, later, Screen(colour: true, width: some(121))
    ).len == 2
    check calendarLines(
      rs, @[], utc(), dtData, later, Screen(colour: true, width: none(int))
    ).len == 2
    check calendarLines(
      rs, @[], utc(), dtData, later, Screen(colour: false, width: some(150))
    ).len == 3 # plain is 185 wide

suite "calendar: a marked day is a band":
  test "the spaces either side of a marked day are marked too, and a run of days is one band":
    let rs =
      @[row(at(2018, mAug, 27)), row(at(2018, mAug, 28)), row(at(2018, mAug, 30))]
    let aug = calendarLines(rs, @[], utc(), dtData, later, colourScreen).monthRow("Aug")
    var marked = ""
    for sp in aug:
      if styleOf(sp) == "select":
        marked.add sp.text
      elif marked.len > 0 and not marked.endsWith("|"):
        marked.add "|"
    check marked == " 27 28 | 30 |"

suite "calendar: detail and shades":
  test "--detail 3 runs from the first month with data to the month of now":
    let ls = calendarLines(
      @[row(at(2018, mMar, 5))],
      @[],
      utc(),
      dtToNow,
      row(at(2018, mJun, 10)),
      colourScreen,
    )
    check ls.len == 1 + 4 # (March to June)
    check monthsShown(@[row(at(2018, mMar, 5))], utc(), dtData, row(at(2018, mJun, 10))).len ==
      1
  test "a shaded day: each column in its third's shade, the day's own style over the digits":
    var sh = Shading(style: "fitness")
    let key = dayKey(2018, mAug, 27)
    sh.fractions[thirdKey(key, 0)] = 0.0
    sh.fractions[thirdKey(key, 1)] = 0.5
    sh.fractions[thirdKey(key, 2)] = 1.0
    let aug = calendarLines(
        @[row(at(2018, mAug, 27))], @[], utc(), dtData, later, colourScreen, some(sh)
      )
      .monthRow("Aug")
    check aug.anyIt(
      it.text == "2" and it.styles == @[shaded("fitness", 0.0), selectedStyle]
    )
    check aug.anyIt(
      it.text == "7" and it.styles == @[shaded("fitness", 0.5), selectedStyle]
    )
    check aug.anyIt(it.text == " " and it.styles == @[shaded("fitness", 1.0)])
    # the label and the space after it are never shaded: "Aug " and then the days
    check aug[0].text == "Aug" and aug[1].text == " " and aug[1].styles.len == 0
    # a day with no value is not shaded
    check not aug.anyIt(
      it.text == "8" and it.styles.len > 0 and ($it.styles[0]).contains(',')
    )
  test "without colour there is no shade":
    var sh = Shading(style: "fitness")
    sh.fractions[thirdKey(dayKey(2018, mAug, 27), 1)] = 0.5
    let aug = calendarLines(
        @[row(at(2018, mAug, 27))], @[], utc(), dtData, later, plainScreen, some(sh)
      )
      .monthRow("Aug")
    check aug.allIt(it.styles.allIt(',' notin $it))
  test "the legend: what, the lowest, the colours from low to high, the highest":
    let l = legendLine(Shading(style: "form"), "form of default", -12.25, 40.0)
    check l.text.startsWith("shade: form of default, -12.2 ") and
      l.text.endsWith(" 40.0")
    check l.filterIt(it.styles.len > 0 and ($it.styles[0]).startsWith("form,")).len == 16
