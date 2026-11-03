## The listing `nch list` prints: a row for each activity and a last line with the
## totals.  Pure (the time zone is a parameter, the rows are styled lines), so tests
## need no database or terminal.
##
##     date        start  sport             km    active
##     2018-03-04  09:12  cycling/road   102.7     4h41m
##     2018-07-26  17:40  cycling          5.5    22m05s
##     2 activities, 108.2km, 5h03m
##
## `active` is the time the timer ran (as Strava's moving time), not the time from
## start to finish.  Nothing here is stored: the rows are read from the activities.

import std/[algorithm, math, options, strutils, tables, times, unicode]
import ../ui/[interval, style]

{.push raises: [].}

type
  ListRow* = object
    startT*: int64                ## Unix seconds, UTC
    sport*, subSport*: string     ## "" if not recorded
    distanceM*, activeS*: Option[float]
    file*, user*: string          ## the file's name; who it belongs to
    path*: string                 ## where the file was imported from (its name if not known)
    place*: string                ## where it started, as `placeText` ("" if not known)

func dateOf(d: DateTime): string =
  d.year.intToStr(4) & "-" & ord(d.month).intToStr(2) & "-" & d.monthday.intToStr(2)

func clockOf(d: DateTime): string =
  d.hour.intToStr(2) & ":" & d.minute.intToStr(2)

const noGps* = "no GPS"                ## said of an activity with no positions

func placeText*(name: string, distanceM: float): string =
  ## "Santiago, CL" (the name as the places list has it, with the country); if the nearest
  ## place is more than 10 km away, how far: "Coyhaique, CL (180km)".  "" without a name.
  if name.len == 0: return ""
  if distanceM > 10_000: name & " (" & $int(round(distanceM / 1000.0)) & "km)" else: name

func startText*(placeName: string, distanceM: float, lat, lon: string): string =
  ## What to say of where an activity started: the place (`placeText`); if no place is known,
  ## its coordinates ("-33.4362,-70.6090": four decimals, about 10 metres, as Google Maps takes
  ## them); if it has no start at all, "no GPS".  `lat` and `lon` are "" if there is no start.
  if placeName.len > 0: return placeText(placeName, distanceM)
  if lat.len == 0 or lon.len == 0: return noGps
  try:
    formatFloat(parseFloat(lat), ffDecimal, 4) & "," & formatFloat(parseFloat(lon), ffDecimal, 4)
  except ValueError:
    noGps

func padRight*(s: string, width: int): string =
  ## `s` padded with spaces to `width` characters (not bytes: "Valparaíso" is 10).
  s & ' '.repeat(max(0, width - s.runeLen))

func padLeft*(s: string, width: int): string =
  ' '.repeat(max(0, width - s.runeLen)) & s

func sportLabel*(r: ListRow): string =
  ## "cycling/road"; the sub-sport only if it says something (not empty, not
  ## "generic"); "-" if no sport is recorded.
  let sport = if r.sport.len > 0: r.sport else: "-"
  if r.subSport.len > 0 and r.subSport != "generic": sport & "/" & r.subSport else: sport

func kmNumber*(metres: float): string =
  ## "102.7": kilometres to a tenth, with commas from 1,000.  (The unit is in the header.)
  let tenths = int(round(metres / 100.0))
  insertSep($(tenths div 10), ',') & "." & $(tenths mod 10)

func km*(metres: float): string =
  ## "102.7km": for a sentence, where a bare number would not say what it is.  (No space,
  ## as in 4h41m.)
  kmNumber(metres) & "km"

const transition = "transition"      ## the sport of the gaps between the legs of a triathlon

proc rowCells(r: ListRow, zone: Timezone): seq[string] =
  let d = fromUnix(r.startT).inZone(zone)
  @[dateOf(d), clockOf(d), sportLabel(r),
    if r.distanceM.isSome: kmNumber(r.distanceM.get) else: "-",
    if r.activeS.isSome: interval(r.activeS.get) else: "-"]

func isTransition(r: ListRow): bool = r.sport == transition

func zeroDistance(r: ListRow): bool =
  ## A distance that shows as "0.0" (under 50 m; not "not recorded"): often a stray
  ## recording, so the number is marked.  Not for transitions, which are like that.
  not r.isTransition and r.distanceM.isSome and r.distanceM.get < 50.0

func zeroActive(r: ListRow): bool =
  ## ... and an active time under 30 s.
  not r.isTransition and r.activeS.isSome and r.activeS.get < 30.0

proc activityText*(r: ListRow, zone: Timezone): string =
  ## One activity in a sentence: "2019-05-21 14:04 running 0.0km 2s".
  let c = rowCells(r, zone)
  c[0] & " " & c[1] & " " & c[2] & " " &
    (if r.distanceM.isSome: km(r.distanceM.get) else: "-") & " " & c[4]

proc table*(rows: seq[ListRow], zone: Timezone, showUser, verbose: bool): seq[Line] =
  ## The header and a line for each row, columns aligned (distance and active
  ## right-aligned).  A `user` column after `start` if `showUser`; if `verbose`, a `file`
  ## columns at the end: `place` (where it started) and `file` (the path the file was
  ## imported from).  No lines at all if
  ## there are no rows.
  ##
  ## Looks: a transition row is dim all through; "-" (not recorded) is dim; a distance
  ## or an active time that shows as zero is yellow.
  if rows.len == 0: return
  var header = @["date", "start", "sport", "km", "active"]
  var cells: seq[seq[string]]
  for r in rows: cells.add rowCells(r, zone)
  if showUser:
    header.insert("user", 2)
    for i, r in rows: cells[i].insert(r.user, 2)
  if verbose:
    header.add "place"
    for i, r in rows: cells[i].add (if r.place.len > 0: r.place else: "-")
    header.add "file"
    for i, r in rows: cells[i].add r.path
  let first = if showUser: 4 else: 3                  # the first number column
  var widths = newSeq[int](header.len)
  for c in 0 ..< header.len:
    widths[c] = header[c].runeLen
    for row in cells: widths[c] = max(widths[c], row[c].runeLen)
  proc padded(text: string, c: int): string =
    if c == first or c == first + 1: text.padLeft(widths[c])
    elif c == header.len - 1: text
    else: text.padRight(widths[c])
  proc line(row: seq[string], r: Option[ListRow]): Line =
    for c in 0 ..< row.len:
      if c > 0: result.add span("  ")
      var look = Look()
      if r.isSome:
        if r.get.isTransition: look.dim = true
        elif row[c] == "-" or row[c] == noGps: look.dim = true
        elif (c == first and r.get.zeroDistance) or (c == first + 1 and r.get.zeroActive):
          look.fg = cYellow
      result.add Span(text: padded(row[c], c), look: look)
  result.add line(header, none(ListRow))
  for i, row in cells: result.add line(row, some(rows[i]))

func plural(n: int, one, many: string): string = $n & " " & (if n == 1: one else: many)

func footer*(rows: seq[ListRow], choices = none(int)): string =
  ## "42 of 310 activities, 2,013.4km, 4d02h12m (13 running, 2 swimming)": how many
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
  result.add ", " & km(metres) & ", " & interval(seconds)
  if bySport.len > 1:
    var parts: seq[(string, int)]
    for k, v in bySport: parts.add (k, v)
    parts.sort do (a, b: (string, int)) -> int:
      result = cmp(b[1], a[1])
      if result == 0: result = cmp(a[0], b[0])
    var text: seq[string]
    for (k, v) in parts: text.add $v & " " & k
    result.add " (" & text.join(", ") & ")"
