## Marks on a calendar: a row for each month, the days of the month in a row, each in the
## column of its weekday, so that days line up in columns (weeks start on Monday).
##
##         Mo Tu We Th Fr Sa Su Mo Tu We Th Fr Sa Su Mo Tu We Th Fr Sa Su ...
##     Jan                01 02 03 04 05 06 07 08 09 10 11 12 ...                      2018
##     Feb       01 02 03 04 05 06 07 08 ...                                           2018
##
## A day is in the selection's style if a mark (an instant: when a selected activity started, say) falls on it, plain if
## only one of the background does (any activity started on it), and hidden if neither does.  Days are the days of
## the time zone given (the user's, for display).  Pure: the marks, the zone and the screen are parameters.
##
## Only the months with a mark are shown (all the months from the first to the last with
## `allMonths`); `skippedMonths` says how many the first leaves out, and the names of the months
## either side of a gap are in the warning style (with a `*` after them when there is no colour).
##
## Without colour (a pipe, NO_COLOR) the cells are wider and carry marks, so nothing is lost: a day
## with a mark `" [34]"`, a day of the background `"  34 "`, a day with neither `"  -- "`.

import std/[algorithm, options, sequtils, sets, strformat, strutils, times]
import ../fit/time
import ../ui/[markup, style]
import ../ui/vocabulary

{.push raises: [].}

type Screen* = object
  colour*: bool ## colours can be used (else marks)
  width*: Option[int] ## columns of the terminal; none: no limit (a file, a pipe)

const
  monthNames =
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  weekdayNames = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
  cells* = 37
    ## a month starting on a Sunday has 31 days in 37 cells (Monday-first weeks)
  labelWidth = 4
  yearWidth = 6

func cellWidth*(s: Screen): int =
  ## The width of a day in the calendar: 3 with colour (the day is coloured), 5 without.
  (if s.colour: 3 else: 5)

func calendarWidth*(s: Screen): int =
  ## How many columns a line of the calendar takes.
  labelWidth + cells * cellWidth(s) + yearWidth

func two(n: int): string =
  intToStr(n, 2)

type DayKind = enum
  dkNone ## nothing on it
  dkBackground ## a day of the background (an activity), not marked
  dkMarked ## a mark falls on it

func dayCell(day: int, kind: DayKind, s: Screen): Line =
  ## A day, by what falls on it.  With colour it is the two digits (the spaces between days are the line's: see
  ## `calendarLines`); without, five columns, a marked day in brackets as every selected thing is (`line.bracketed`).
  if s.colour:
    case kind
    of dkMarked:
      ~"<{selectedStyle} {two(day)}>"
    of dkBackground:
      ~"{two(day)}"
    of dkNone:
      ~"<hide {two(day)}>"
  else:
    let text = (if kind == dkNone: "--" else: two(day))
    let marked = kind == dkMarked
    ~" " & bracketed(plain(text), marked) & (if marked: @[] else: ~" ")

proc monthsOf(marks: seq[UnixTime], zone: Timezone): seq[int] =
  ## The months (year * 12 + month - 1) with a mark, in order.
  for t in marks:
    let d = t.toTime.inZone(zone)
    let m = d.year * 12 + ord(d.month) - 1
    if m notin result:
      result.add m
  result.sort

proc skippedMonths*(marks: seq[UnixTime], zone: Timezone): int =
  ## How many months between the first and the last have no mark (so a calendar of only
  ## the months with data leaves them out).
  let months = monthsOf(marks, zone)
  if months.len > 0:
    result = months[^1] - months[0] + 1 - months.len

proc calendarLines*(
    marks, background: seq[UnixTime], zone: Timezone, allMonths: bool, screen: Screen
): seq[Line] =
  ## The calendar of the marks, over the days of the `background`: a header of weekday names, then a row for each month
  ## that has a mark (or, with `allMonths`, for every month from the first to the last).  If the lines are wider than the
  ## screen, a warning comes first and each line is cut to the screen.
  if marks.len == 0:
    return
  proc daysOf(ts: seq[UnixTime], zone: Timezone): HashSet[int] =
    ## the days the instants fall on: year*10000 + month*100 + day
    for t in ts:
      let d = t.toTime.inZone(zone)
      result.incl d.year * 10000 + ord(d.month) * 100 + d.monthday

  let listed = daysOf(marks, zone)
  let active = daysOf(background, zone)
  var months = monthsOf(marks, zone) # year*12 + (month - 1)
  if allMonths:
    months = toSeq(months[0] .. months[^1])
  let cw = cellWidth(screen)
  let margin = " ".repeat(labelWidth)
  var header: Line = ~"{margin}"
  for k in 0 ..< cells:
    let name = weekdayNames[k mod 7]
    header.add (if screen.colour: ~"{name} " else: ~"  {name} ")
  result.add header
  for m in months:
    let year = m div 12
    let month = Month(m mod 12 + 1)
    let offset = ord(getDayOfWeek(1, month, year)) # Monday is 0
    let days = getDaysInMonth(month, year)
    # the months either side of a gap are marked: names in the warning style (a "*" without colour)
    let gap =
      months.find(m) > 0 and m - months[months.find(m) - 1] > 1 or
      months.find(m) < months.high and months[months.find(m) + 1] - m > 1
    var line: Line =
      if screen.colour:
        (if gap: ~"<warn {monthNames[m mod 12]}>" else: ~"{monthNames[m mod 12]}")
      elif gap:
        ~"{monthNames[m mod 12]}*"
      else:
        ~"{monthNames[m mod 12]} "
    for k in 0 ..< cells:
      let day = k - offset + 1
      if screen.colour:
        line.add ~" " # (the space before each day: see below)
      if day < 1 or day > days:
        line.add ~"{' '.repeat(if screen.colour: 2 else: cw)}"
      else:
        let key = year * 10000 + (m mod 12 + 1) * 100 + day
        let kind =
          if key in listed:
            dkMarked
          elif key in active:
            dkBackground
          else:
            dkNone
        line.add dayCell(day, kind, screen)
    if screen.colour:
      line.add ~" "
      # a space next to a marked day is marked too, so that a marked day, or a run of them, is a band (" 05 06 "), not
      # the digits and the space after them
      for i in 1 ..< line.high:
        if line[i].text == " " and (
          line[i - 1].styles == @[selectedStyle] or
          line[i + 1].styles == @[selectedStyle]
        ):
          line[i] = span(" ", selectedStyle)
    line.add ~"  {year}"
    result.add line
  if screen.width.isSome and calendarWidth(screen) > screen.width.get:
    result = result.mapIt(it.truncated(screen.width.get))
    result.insert ~"<warn the calendar needs {calendarWidth(screen)} columns and the screen has {screen.width.get}: the lines are cut>",
      0
