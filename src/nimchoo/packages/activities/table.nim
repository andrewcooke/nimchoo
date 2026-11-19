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

import std/[algorithm, math, options, sequtils, strformat, strutils, tables, times]
import ../fit/time
import ../geo/position
import ../importer/describe
import ../ui/interval
import ../ui/style
import ../../core/ruled
import ../ui/units
import ../ui/vocabulary
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
  position*: string ## its start as `startText` (no GPS if it has none)
  selected*: bool ## it is in the selection (of the current user)

func startText*(lat, lon: Option[float]): string =
  ## Where an activity started, as every position is written (`geo/position`: "-33.4362,-70.6090", which Google Maps takes
  ## too); "no GPS" if there is no start.
  if lat.isNone or lon.isNone:
    return noGps
  positionText((lon: lon.get, lat: lat.get))

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

proc table*(
    rows: seq[ListRow], zone: Timezone, verbose: bool, width: int, marks = false
): seq[Line] =
  ## The header and a line for each row, as a table (`core/ruled.nim`, the last column wrapped to `width`; distance and
  ## active to the right): the start, the sport, the distance, the active time and "place / name" of each activity
  ## (describe.nim), and if `verbose` the sub-sport after the sport and the path of the file last.  No lines at all if
  ## there are no rows.
  ##
  ## Styles: a row in the selection is `select` all through (a band, the lines between the columns too); a transition row
  ## is `hide` all through; "-" (not recorded) is `hide`; a distance or an active time that shows as zero is `warn`.  With
  ## `marks` (for where there is no colour) a row in the selection is also in brackets, `[...]`, as a day of the calendar
  ## is, and every line is one column further in.
  if rows.len == 0:
    return
  var header = @["start", "sport", "distance", "active", "place / name"]
  if verbose:
    header.add "path"
  const first = 2 # the distance column; the active time follows (`right` below)
  var cells: seq[seq[Line]]
  var styles: seq[seq[StyleName]]
  for r in rows:
    let texts = activityCells(info(r, verbose), zone, verbose)
    var line: seq[Line]
    for c, text in texts:
      var style = none(StyleName) # (plain; a row in a style of its own has no others)
      if not (r.isTransition or r.selected):
        if text == notRecorded or text == noGps:
          style = some(styleName"hide")
        elif (c == first and r.zeroDistance) or (c == first + 1 and r.zeroActive):
          style = some(styleName"warn")
      line.add(
        if style.isSome:
          @[span(text, style.get)]
        else:
          plain(text)
      )
    cells.add line
    styles.add(
      if r.isTransition:
        @[styleName"hide"]
      elif r.selected:
        @[selectedStyle]
      else:
        @[]
    )
  for l in ruledRows(header, cells, width, right = {2, 3}, rowStyles = styles):
    result.add(
      if marks:
        bracketed(l.line, l.row >= 0 and rows[l.row].selected)
      else:
        l.line
    )

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
  let ofAll =
    if choices.isSome:
      fmt" of {choices.get}"
    else:
      ""
  let noun = if rows.len == 1 and choices.isNone: "activity" else: "activities"
  result = fmt"{rows.len}{ofAll} {noun}"
  if rows.len == 0:
    return
  result.add fmt", {km(metres)}, {interval(seconds)}"
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
      text.add fmt"{v} {k}"
    result.add fmt" ({text.join("", "")})"

func footerLine*(
    rows: seq[ListRow], choices = none(int), style = selectedStyle, saved = none(int)
): Line =
  ## The last line (`footer`) as styled spans, after "done: " like the end of an import: if some of
  ## the activities are in the selection, ", 35 match selected" follows the count, the words (not the comma) in the style
  ## the selected ones have in the display (the rows of the table, the days of the calendar):
  ## "done: 1112 of 1112 activities, 35 match selected, 57,529.0km, 114d08h22m".
  ## With `saved` (the listing was kept as the selection) it says so there, in one line with the rest:
  ## "done: 1 of 1112 activities, 1 saved as the selection, 95.4km, 5h24m".
  let text = footer(rows, choices)
  let selected = rows.countIt(it.selected)
  if selected == 0 and saved.isNone:
    return plain(fmt"done: {text}")
  let split = text.find(", ") # the count comes first; the rest follows a comma
  let head =
    if split < 0:
      text
    else:
      text[0 ..< split]
  let said =
    if saved.isSome:
      fmt"{saved.get} saved as the selection"
    else:
      fmt"{selected} match selected"
  result =
    @[span(fmt"done: {head}, "), span(said, style)] # (the comma is not in the style)
  if split >= 0:
    result.add span(text[split .. ^1])
