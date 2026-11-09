## The listing `nch activities` prints: a row for each activity and a last line with the
## totals.  Pure (the time zone is a parameter, the rows are styled lines), so tests
## need no database or terminal.  An activity is said the standard way (describe.nim).
##
##     start             sport    distance  active  place / name
##     2018-03-04 09:12  cycling   102.7km   4h41m  Providencia / Lo Barnechea and back
##     2018-07-26 17:40  cycling     5.5km  22m05s  Providencia
##     2 activities, 108.2km, 5h03m
##
## `active` is the time the timer ran (as Strava's moving time), not the time from
## start to finish.  Nothing here is stored: the rows are read from the activities.

import std/[algorithm, math, options, sequtils, strutils, tables, times, unicode]
import ../packages/fit/time
import ../importer/describe
import ../packages/ui/interval
import ../packages/ui/style
import ../packages/ui/units
export describe, units

{.push raises: [].}

type ListRow* = object
  startT*: UnixTime
  sport*, subSport*: string ## "" if not recorded
  distanceM*, activeS*: Option[float]
  file*, user*: string ## the file's name; who it belongs to
  path*: string ## where the file was imported from (its name if not known)
  place*: string ## where it started, as text ("" if not known)
  name*: string ## what it is called ("" if nothing)
  position*: string ## its start as `positionText` (no GPS if it has none)
  selected*: bool ## it is in the selection (of the current user)

func positionText*(lat, lon: Option[float]): string =
  ## The start as "-33.4362,-70.6090": latitude, longitude, four decimals (about 10 metres), as
  ## Google Maps takes them; "no GPS" if there is no start.
  if lat.isNone or lon.isNone:
    return noGps
  formatFloat(lat.get, ffDecimal, 4) & "," & formatFloat(lon.get, ffDecimal, 4)

func padRight*(s: string, width: int): string =
  ## `s` padded with spaces to `width` characters (not bytes: "Valparaíso" is 10).
  s & ' '.repeat(max(0, width - s.runeLen))

func padLeft*(s: string, width: int): string =
  ## The text with blanks before it, to the width (by characters, not bytes).
  ' '.repeat(max(0, width - s.runeLen)) & s

const transition = "transition" ## the sport of the gaps between the legs of a triathlon

func info*(r: ListRow, verbose = false): ActivityInfo =
  ## The row as the standard description takes it.  ("no GPS" is said only if verbose: otherwise the positions are not read.)
  ActivityInfo(
    startT: r.startT,
    sport: r.sport,
    subSport: r.subSport,
    distanceM: r.distanceM,
    activeS: r.activeS,
    place: r.place,
    name: r.name,
    path: r.path,
    noPositions: verbose and r.position == noGps,
  )

func isTransition(r: ListRow): bool =
  r.sport == transition

func zeroDistance(r: ListRow): bool =
  ## A distance that shows as "0.0" (under 50 m; not "not recorded"): often a stray
  ## recording, so the number is marked.  Not for transitions, which are like that.
  not r.isTransition and r.distanceM.isSome and r.distanceM.get < 50.0

func zeroActive(r: ListRow): bool =
  ## ... and an active time under 30 s.
  not r.isTransition and r.activeS.isSome and r.activeS.get < 30.0

proc activityText*(r: ListRow, zone: Timezone): string =
  ## One activity in a sentence, the standard way: "2019-05-21 14:04  running  0.0km 2s".
  activityLine(info(r), zone)

proc table*(rows: seq[ListRow], zone: Timezone, verbose: bool): seq[Line] =
  ## The header and a line for each row, columns aligned (distance and active right-aligned): the start, the sport, the
  ## distance, the active time and "place / name" of each activity (describe.nim), and if `verbose` the sub-sport after the
  ## sport and the path of the file last.  No lines at all if there
  ## are no rows.
  ##
  ## Looks: a row in the selection is blue all through; a
  ## transition row is dim all through; "-" (not recorded) is dim; a distance
  ## or an active time that shows as zero is yellow.
  if rows.len == 0:
    return
  var header = @["start", "sport", "distance", "active", "place / name"]
  if verbose:
    header.add "path"
  var cells: seq[seq[string]]
  for r in rows:
    cells.add activityCells(info(r, verbose), zone, verbose)
  let first = 2 # the distance column; the active time follows
  var widths = newSeq[int](header.len)
  for c in 0 ..< header.len:
    widths[c] = header[c].runeLen
    for row in cells:
      widths[c] = max(widths[c], row[c].runeLen)
  proc padded(text: string, c: int): string =
    if c == first or c == first + 1:
      text.padLeft(widths[c])
    elif c == header.len - 1:
      text
    else:
      text.padRight(widths[c])

  proc line(row: seq[string], r: Option[ListRow]): Line =
    for c in 0 ..< row.len:
      if c == row.len - 1 and row[c].len == 0 and c > 0:
        break # (nothing to say last: no trailing blanks)
      if c > 0:
        result.add span("  ")
      var look = Look()
      if r.isSome:
        if r.get.isTransition:
          look.colour = grey
        elif r.get.selected:
          look.colour = blue # the whole row: it is in the selection
        elif row[c] == notRecorded or row[c] == noGps:
          look.colour = grey
        elif (c == first and r.get.zeroDistance) or (
          c == first + 1 and r.get.zeroActive
        ):
          look.colour = yellow
      result.add Span(text: padded(row[c], c), look: look)

  result.add line(header, none(ListRow))
  for i, row in cells:
    result.add line(row, some(rows[i]))

func footer*(rows: seq[ListRow], choices = none(int)): string =
  ## "42 of 310 activities, 2,013.4km, 4d02h12m (13 running, 2 swimming)": how many
  ## (of how many there are to choose from, if known), the total distance and active
  ## time (of those that have them), and how many of each sport if there are several.
  var metres, seconds = 0.0
  var bySport: CountTable[string]
  for r in rows:
    if r.distanceM.isSome:
      metres += r.distanceM.get
    if r.activeS.isSome:
      seconds += r.activeS.get
    bySport.inc(if r.sport.len > 0: r.sport else: "unknown")
  result =
    $rows.len & (if choices.isSome: " of " & $choices.get else: "") &
    (if rows.len == 1 and choices.isNone: " activity" else: " activities")
  if rows.len == 0:
    return
  result.add ", " & km(metres) & ", " & interval(seconds)
  if bySport.len > 1:
    var parts: seq[(string, int)]
    for k, v in bySport:
      parts.add (k, v)
    parts.sort do(a, b: (string, int)) -> int:
      result = cmp(b[1], a[1])
      if result == 0:
        result = cmp(a[0], b[0])
    var text: seq[string]
    for (k, v) in parts:
      text.add $v & " " & k
    result.add " (" & text.join(", ") & ")"

func footerLine*(
    rows: seq[ListRow], choices = none(int), selectedColour = blue, saved = none(int)
): Line =
  ## The last line (`footer`) as styled spans, after "done: " like the end of an import: if some of
  ## the activities are in the selection, ", 35 match selected" follows the count, in the colour
  ## the selected ones have in the display (blue rows in the table, blue days in the calendar):
  ## "done: 1112 of 1112 activities, 35 match selected, 57,529.0km, 114d08h22m".
  ## With `saved` (the listing was kept as the selection) it says so there, in one line with the rest:
  ## "done: 1 of 1112 activities, 1 saved as the selection, 95.4km, 5h24m".
  let text = footer(rows, choices)
  let selected = rows.countIt(it.selected)
  if selected == 0 and saved.isNone:
    return plain("done: " & text)
  let split = text.find(", ") # the count comes first; the rest follows a comma
  let head =
    if split < 0:
      text
    else:
      text[0 ..< split]
  let said =
    if saved.isSome:
      ", " & $saved.get & " saved as the selection"
    else:
      ", " & $selected & " match selected"
  result = @[span("done: " & head), span(said, selectedColour)]
  if split >= 0:
    result.add span(text[split .. ^1])
