## The standard way to say an activity or a climb, wherever one is shown (the list, the climbs, the sector commands):
## like `__str__` for the two kinds of thing, so that they look the same everywhere.
##
##     an activity   2020-08-14 06:01  cycling  36.7km 1h41m  Providencia / Lo Barnechea and back
##     (verbose)     2020-08-14 06:01  cycling/road  36.7km 1h41m  Providencia / Lo Barnechea and back  /home/andrew/fit/x.fit
##     a climb       Cerro San Luis (4/5)  4 0.5km +89m 17.8%
##
## The start (date and time), the sport (with the sub-sport if verbose), the distance, the active time, then where it
## started and what it is called, joined by " / " (and, if verbose, the path of the file it came from).  A climb: its name,
## its category, its length, its gain and its gradient.  There is no space between a number and its unit.
##
## Each has a `...Cells` form for tables, where the columns are lined up, and a `...Line` form for one line.  Pure.

import std/[math, options, strutils, times]
import ./fit/time
import ./ui/interval

{.push raises: [].}

type
  ActivityInfo* = object
    startT*: UnixTime
    sport*, subSport*: string        ## "" if not recorded
    distanceM*, activeS*: Option[float]
    place*: string                   ## where it started ("" if not known)
    name*: string                    ## what it is called ("" if nothing)
    path*: string                    ## where the file was imported from (shown if verbose)
    noPositions*: bool               ## it has no positions: "no GPS" is said where the place and name would be

  ClimbInfo* = object
    name*: string                    ## as shown ("Cerro San Luis (4/5)"), cut to fit if need be by the caller
    category*: string                ## "4", "3", "2", "1" or "HC"; "" if too small to have one
    lengthM*, gainM*, gradient*: float   ## metres, metres, percent

const
  noGps* = "no GPS"                  ## said of an activity with no positions
  notRecorded* = "-"                 ## said of a value that is not there

# --- the numbers

func kmNumber*(metres: float): string =
  ## "102.7": kilometres to a tenth, with commas from 1,000.
  let tenths = int(round(metres / 100.0))
  insertSep($(tenths div 10), ',') & "." & $(tenths mod 10)

func km*(metres: float): string =
  ## "102.7km": the unit follows the number with no space (as in 4h41m).
  kmNumber(metres) & "km"

func gainText*(metres: float): string = "+" & $int(metres + 0.5) & "m"

func gradientText*(percent: float): string = formatFloat(percent, ffDecimal, 1) & "%"

# --- an activity

func sportText*(sport, subSport: string, verbose: bool): string =
  ## "cycling"; verbose: "cycling/road", the sub-sport only if it says something (not empty, not "generic");
  ## "-" if no sport is recorded.
  let s = if sport.len > 0: sport else: notRecorded
  if verbose and subSport.len > 0 and subSport != "generic": s & "/" & subSport else: s

func whereText*(place, name: string, noPositions = false): string =
  ## "Providencia / Lo Barnechea and back": the place it started and what it is called, whichever there are; "no GPS" if
  ## there is neither because the activity has no positions; "" if there is nothing to say.
  if place.len > 0 and name.len > 0: place & " / " & name
  elif place.len > 0: place
  elif name.len > 0: name
  elif noPositions: noGps
  else: ""

proc dateTimeText*(startT: UnixTime, zone: Timezone): string =
  ## "2020-08-14 06:01", in the time zone.
  startT.toTime.inZone(zone).format("yyyy-MM-dd HH:mm")

proc activityCells*(a: ActivityInfo, zone: Timezone, verbose: bool): seq[string] =
  ## The parts of an activity, to be lined up in columns: start, sport, distance, active time, place / name; with the
  ## path last if verbose.
  result = @[dateTimeText(a.startT, zone), sportText(a.sport, a.subSport, verbose),
             if a.distanceM.isSome: km(a.distanceM.get) else: notRecorded,
             if a.activeS.isSome: interval(a.activeS.get) else: notRecorded,
             whereText(a.place, a.name, a.noPositions)]
  if verbose: result.add a.path

proc activityLine*(a: ActivityInfo, zone: Timezone, verbose = false): string =
  ## The activity on one line: "2020-08-14 06:01  cycling  36.7km 1h41m  Providencia / Lo Barnechea and back".
  let c = activityCells(a, zone, verbose)
  result = c[0] & "  " & c[1] & "  " & c[2] & " " & c[3]
  if c[4].len > 0: result.add "  " & c[4]
  if verbose and c[5].len > 0: result.add "  " & c[5]

# --- a climb

func climbCells*(c: ClimbInfo): seq[string] =
  ## The parts of a climb, to be lined up in columns: name, category, length, gain, gradient.
  @[c.name, if c.category.len > 0: c.category else: notRecorded, km(c.lengthM), gainText(c.gainM), gradientText(c.gradient)]

func climbLine*(c: ClimbInfo): string =
  ## The climb on one line: "Cerro San Luis (4/5)  4 0.5km +89m 17.8%".
  let x = climbCells(c)
  x[0] & "  " & x[1] & " " & x[2] & " " & x[3] & " " & x[4]
