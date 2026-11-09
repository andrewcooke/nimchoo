## The listing as a calendar: a row for each month, the days of the month in a row, each in the
## column of its weekday, so that days line up in columns (weeks start on Monday).
##
##         Mo Tu We Th Fr Sa Su Mo Tu We Th Fr Sa Su Mo Tu We Th Fr Sa Su ...
##     Jan                01 02 03 04 05 06 07 08 09 10 11 12 ...                      2018
##     Feb       01 02 03 04 05 06 07 08 ...                                           2018
##
## A day is white if an activity that was listed falls on it, blue if one of them is also in the
## selection, grey if none was listed.  Days are the days of the time zone given (the user's, for
## display).  Pure: the rows, the zone and the screen are parameters.
##
## Only the months with an activity are shown (all the months from the first to the last with
## `allMonths`); `skippedMonths` says how many the first leaves out, and the names of the months
## either side of a gap are yellow (with a `*` after them when there is no colour).
##
## Without colour (a pipe, NO_COLOR) the cells are wider and carry marks, so nothing is lost: a day
## with data `"  12 "`, a selected day `" [34]"`, a day with none `"  -- "`.

import std/[algorithm, sequtils, strutils, tables, times]
import ../fit/time
import ../ui/style
import ./table

{.push raises: [].}

type Screen* = object
  colour*: bool ## colours can be used (else marks)
  width*: int ## columns; 0: no limit

const
  dataColour* = white ## a day with a listed activity
  selectedColour* = blue ## ... and one of them is in the selection
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

func dayCell(day: int, state: int, s: Screen): Span =
  ## `state`: 0 no activity, 1 some, 2 some in the selection.
  if s.colour:
    case state
    of 0:
      span(two(day) & " ", grey)
    of 1:
      span(two(day) & " ", dataColour)
    else:
      span(two(day) & " ", selectedColour)
  else:
    case state
    of 0:
      span("  -- ")
    of 1:
      span("  " & two(day) & " ")
    else:
      span(" [" & two(day) & "]")

proc monthsOf(rows: seq[ListRow], zone: Timezone): seq[int] =
  ## The months (year * 12 + month - 1) with a listed activity, in order.
  for r in rows:
    let d = r.startT.toTime.inZone(zone)
    let m = d.year * 12 + ord(d.month) - 1
    if m notin result:
      result.add m
  result.sort

proc skippedMonths*(rows: seq[ListRow], zone: Timezone): int =
  ## How many months between the first and the last have no activity (so a calendar of only
  ## the months with data leaves them out).
  let months = monthsOf(rows, zone)
  if months.len > 0:
    result = months[^1] - months[0] + 1 - months.len

proc calendarLines*(
    rows: seq[ListRow], zone: Timezone, allMonths: bool, screen: Screen
): seq[Line] =
  ## The calendar of the rows: a header of weekday names, then a row for each month that has an
  ## activity (or, with `allMonths`, for every month from the first to the last).  If the lines
  ## are wider than the screen, a warning comes first and each line is cut to the screen.
  if rows.len == 0:
    return
  var state: Table[int, int] # year*10000 + month*100 + day -> 1 or 2
  for r in rows:
    let d = r.startT.toTime.inZone(zone)
    let key = d.year * 10000 + ord(d.month) * 100 + d.monthday
    state[key] = max(state.getOrDefault(key), if r.selected: 2 else: 1)
  var months = monthsOf(rows, zone) # year*12 + (month - 1)
  if allMonths:
    months = toSeq(months[0] .. months[^1])
  let cw = cellWidth(screen)
  var header: Line = @[span(" ".repeat(labelWidth))]
  for k in 0 ..< cells:
    let name = weekdayNames[k mod 7]
    header.add span((if screen.colour: name & " " else: "  " & name & " "))
  result.add header
  for m in months:
    let year = m div 12
    let month = Month(m mod 12 + 1)
    let offset = ord(getDayOfWeek(1, month, year)) # Monday is 0
    let days = getDaysInMonth(month, year)
    # the months either side of a gap are marked: yellow names (a "*" without colour)
    let gap =
      months.find(m) > 0 and m - months[months.find(m) - 1] > 1 or
      months.find(m) < months.high and months[months.find(m) + 1] - m > 1
    var line: Line =
      if not gap:
        @[span(monthNames[m mod 12] & " ")]
      elif screen.colour:
        @[span(monthNames[m mod 12], yellow), span(" ")]
      else:
        @[span(monthNames[m mod 12] & "*")]
    for k in 0 ..< cells:
      let day = k - offset + 1
      if day < 1 or day > days:
        line.add span(" ".repeat(cw))
      else:
        line.add dayCell(
          day, state.getOrDefault(year * 10000 + (m mod 12 + 1) * 100 + day), screen
        )
    line.add span("  " & $year)
    result.add line
  if screen.width > 0 and calendarWidth(screen) > screen.width:
    result = result.mapIt(it.truncated(screen.width))
    result.insert @[
      span(
        "the calendar needs " & $calendarWidth(screen) & " columns and the screen has " &
          $screen.width & ": the lines are cut",
        yellow,
      )
    ], 0
