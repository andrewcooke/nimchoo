## The listing `nch list` prints: a row for each activity and a last line with the
## totals.  Pure (the time zone is a parameter), so tests need no database.
##
##     date        start  sport          distance   active
##     2018-03-04  09:12  cycling/road   102.7 km   4:41
##     2018-07-26  17:40  cycling          5.5 km   0:22
##     2 activities, 108.2 km, 5:03 h
##
## `active` is the time the timer ran (as Strava's moving time), not the time from
## start to finish.  Nothing here is stored: the rows are read from the activities.

import std/[algorithm, math, options, strutils, tables, times]

{.push raises: [].}

type
  ListRow* = object
    startT*: int64                ## Unix seconds, UTC
    sport*, subSport*: string     ## "" if not recorded
    distanceM*, activeS*: Option[float]
    file*, user*: string

func dateOf(d: DateTime): string =
  d.year.intToStr(4) & "-" & ord(d.month).intToStr(2) & "-" & d.monthday.intToStr(2)

func clockOf(d: DateTime): string =
  d.hour.intToStr(2) & ":" & d.minute.intToStr(2)

func sportLabel*(r: ListRow): string =
  ## "cycling/road"; the sub-sport only if it says something (not empty, not
  ## "generic"); "-" if no sport is recorded.
  let sport = if r.sport.len > 0: r.sport else: "-"
  if r.subSport.len > 0 and r.subSport != "generic": sport & "/" & r.subSport else: sport

func km*(metres: float): string =
  ## "102.7 km", with commas from 1,000 km.
  let tenths = int(round(metres / 100.0))
  insertSep($(tenths div 10), ',') & "." & $(tenths mod 10) & " km"

func hours*(seconds: float): string =
  ## "4:41": hours and minutes, rounded to the minute; "98:12" is more than a day.
  let minutes = int(round(seconds / 60.0))
  $(minutes div 60) & ":" & intToStr(minutes mod 60, 2)

proc rowCells(r: ListRow, zone: Timezone): seq[string] =
  let d = fromUnix(r.startT).inZone(zone)
  @[dateOf(d), clockOf(d), sportLabel(r),
    if r.distanceM.isSome: km(r.distanceM.get) else: "-",
    if r.activeS.isSome: hours(r.activeS.get) else: "-"]

proc table*(rows: seq[ListRow], zone: Timezone, showFile, showUser: bool): seq[string] =
  ## The header and a line for each row, columns aligned (distance and active
  ## right-aligned).  A `user` column if `showUser`, a `file` column at the end if
  ## `showFile`.  No lines at all if there are no rows.
  if rows.len == 0: return
  var header = @["date", "start", "sport", "distance", "active"]
  var cells: seq[seq[string]]
  for r in rows: cells.add rowCells(r, zone)
  if showUser:
    header.insert("user", 2)
    for i, r in rows: cells[i].insert(r.user, 2)
  if showFile:
    header.add "file"
    for i, r in rows: cells[i].add r.file
  let right = if showUser: {4, 5} else: {3, 4}      # the columns of numbers
  var widths = newSeq[int](header.len)
  for c in 0 ..< header.len:
    widths[c] = header[c].len
    for row in cells: widths[c] = max(widths[c], row[c].len)
  proc line(row: seq[string]): string =
    var parts: seq[string]
    for c in 0 ..< row.len:
      let last = c == row.len - 1
      parts.add (if c in right: row[c].align(widths[c])
                 elif last: row[c]
                 else: row[c].alignLeft(widths[c]))
    parts.join("  ")
  result.add line(header)
  for row in cells: result.add line(row)

func plural(n: int, one, many: string): string = $n & " " & (if n == 1: one else: many)

func footer*(rows: seq[ListRow], choices = none(int)): string =
  ## "42 of 310 activities, 2,013.4 km, 98:12 h (13 running, 2 swimming)": how many
  ## (of how many there are to choose from, if known), the total distance and active
  ## time (of those that have them), and how many of each sport if there are several.
  var metres, seconds = 0.0
  var bySport: CountTable[string]
  for r in rows:
    if r.distanceM.isSome: metres += r.distanceM.get
    if r.activeS.isSome: seconds += r.activeS.get
    bySport.inc(if r.sport.len > 0: r.sport else: "unknown")
  result = $rows.len & (if choices.isSome: " of " & $choices.get else: "") &
    (if rows.len == 1 and choices.isNone: " activity" else: " activities")
  if rows.len == 0: return
  result.add ", " & km(metres) & ", " & hours(seconds) & " h"
  if bySport.len > 1:
    var parts: seq[(string, int)]
    for k, v in bySport: parts.add (k, v)
    parts.sort do (a, b: (string, int)) -> int:
      result = cmp(b[1], a[1])
      if result == 0: result = cmp(a[0], b[0])
    var text: seq[string]
    for (k, v) in parts: text.add $v & " " & k
    result.add " (" & text.join(", ") & ")"
