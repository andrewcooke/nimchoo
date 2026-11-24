## The breaks of a ride: what happened between two neighbouring timer segments, and the stretches of riding that the
## breaks leave.
##
## A Garmin stops the timer by itself ("auto-pause") when the rider slows
## down, at a junction or to drink, and starts it again when they move.  That
## is not a break in the ride: a climb with a drink stop half way is one
## climb, and a time from gate to gate includes the stop (a rider who does not
## stop earns the faster time).  What is a break is a gap in which the rider
## was carried (a car, a train) or the timer was stopped by hand.  The rule
## here tells them apart from what the file says (who stopped and restarted
## the timer) and what the rider did (how far they were from where they
## stopped, in how long).  Measured on 55,171 gaps of the author's rides it
## joins 99.4%; the rest are manual stops, long gaps that moved, and short
## ones that moved too far to be explained by the rider's own speed.
##
## Each gap is kept with its kind (`BreakKind`, decided with the author 2026-11-25, dev/plot-activity.md step 1b):
## `manual` (the rider stopped the timer, or the file does not say who), `carried` (a car, a train), `pause` (the device
## paused and the rider stayed put); a blink (the timer off for moments while the rider rode on) is the device's noise and
## no break at all.  A fourth kind, `error`, is not a gap of the timer: the GPS jumped and never came back (clean.nim), so
## no line of positions may cross it.  Each user of the breaks takes the kinds it needs: the stretches of riding (the
## climbs, the impulses, the route's parts) end at `manual`, `carried` and `error` (`stretchBreaks`); a plot over time
## breaks at `manual`, `carried` and `pause` (`timeBreaks`).
##
## Pure: the importer measures the gap and asks.

import std/options
import ../fit/time

{.push raises: [].}

const
  stillM* = 30.0
    ## A gap in which the rider ended less than this far from where they
    ## stopped is a pause, however long (a drink, a photo, a café).
  quickS* = 30'i64
    ## A gap shorter than this is the timer blinking off while the rider
    ## carried on, if the speed it implies is one a bicycle can do.  The limit
    ## is short so that a vehicle cannot hide in it: the longest jump it can
    ## join is `quickS` times `ridingMps`.
  ridingMps* = 15.0 ## 54 km/h: a fast descent, not a car.

type
  BreakKind* = enum ## What a break of a ride was.
    bkManual = "manual" ## the rider stopped the timer (or the file does not say who)
    bkCarried = "carried" ## auto-stopped, then too far or too fast: a car, a train
    bkPause = "pause"
      ## auto-stopped, and the rider stayed put (or had nowhere to go: no positions)
    bkError = "error" ## the GPS jumped and never came back: no time is missing

  Break* = object
    ## A break of a ride: from the end of one timer segment to the start of the next.
    startT*, endT*: UnixTime
    kind*: BreakKind

  Span* = object ## A closed interval of a ride's time: its riding, or a stretch of it.
    startT*, endT*: UnixTime

  Trigger* = enum
    ## Who stopped or restarted the timer (the `timer_trigger` of the FIT
    ## event).
    trAuto
    trManual
    trOther ## not said (older devices), or another kind (fitness equipment)

  Gap* = object ## The time between one timer segment and the next.
    seconds*: int64 ## from the stop to the restart
    metres*: float ## from the last position before the stop to the first after
    stoppedBy*, restartedBy*: Trigger

const
  stretchBreaks* = {bkManual, bkCarried, bkError}
    ## where a stretch of riding ends: a line of positions (a climb, the route) does not cross them
  timeBreaks* = {bkManual, bkCarried, bkPause}
    ## where nothing was recorded for a while: a line over time breaks there

func stoppedByDevice(stoppedBy, restartedBy: Trigger): bool =
  ## The timer must have been stopped by the device: a stop by hand is the rider's way to say "this is apart", and what
  ## the file does not say we do not assume.  It may have been restarted by hand, which is what a rider does when the
  ## device did not notice they were off again.  (Measured on the author's rides: 97 of the gaps are an auto stop and a
  ## manual restart, 72 of them under 20 m; a stop by hand is never followed by an automatic restart.)
  stoppedBy == trAuto and restartedBy in {trAuto, trManual}

func kindOf*(g: Gap): Option[BreakKind] =
  ## The kind of break `g` is, or none for a blink (no break: the timer was off for moments while the rider rode on).
  doAssert g.seconds >= 0 and g.metres >= 0, "a gap has a length and a duration"
  if not stoppedByDevice(g.stoppedBy, g.restartedBy):
    return some(bkManual)
  if g.metres < stillM:
    return some(bkPause)
  if g.seconds < quickS and g.metres / float(max(g.seconds, 1)) < ridingMps:
    return none(BreakKind)
  some(bkCarried)

func unmeasuredKind*(stoppedBy, restartedBy: Trigger): BreakKind =
  ## The kind of a gap in a ride with no positions, where how far the rider went cannot be measured: a pause if the device
  ## stopped the timer (on a trainer there is nowhere to go), else manual.
  if stoppedByDevice(stoppedBy, restartedBy): bkPause else: bkManual

func stretchesOf*(riding: Span, breaks: seq[Break]): seq[Span] =
  ## The stretches of riding: the riding cut at the breaks of `stretchBreaks` (in time order, each inside the riding).
  var start = riding.startT
  for b in breaks:
    if b.kind in stretchBreaks:
      result.add Span(startT: start, endT: b.startT)
      start = b.endT
  result.add Span(startT: start, endT: riding.endT)
