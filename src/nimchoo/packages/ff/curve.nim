## Fitness and fatigue: what the impulses (model/calc.nim: one lump a stretch of riding) add up to, each fading away
## exponentially, and the times they are wanted at.  Pure, but for the timezone.
##
## Both curves are the same calculation with a different decay time (42 days for fitness, 7 for fatigue in the default
## model): the value at a time is the sum, over the lumps at or before it, of `value * exp(-(time - lump's time) / tau)`,
## worked out exactly at the times wanted, on no grid.  The curve starts from 0.  (The original has a starting value and
## a scale; see dev/HISTORY.md, task 7, for why they are gone.  The scale is an option of the command.)  Days are the
## timezone's; hours are those of the clock in UTC.

import std/[math, times]
import ../model/calc

{.push raises: [].}

const
  secondsPerDay* = 86400'i64
  secondsPerHour* = 3600'i64

func curveAt*(
    lumps: openArray[Lump], tauDays: float, times: openArray[int64]
): seq[float] =
  ## The curve at each of `times` (in order), from `lumps` (in time order).  A lump counts from its own instant: at it,
  ## and after.
  let tau = tauDays * float(secondsPerDay)
  var y = 0.0 # the value just after the last lump counted
  var at = 0'i64 # that lump's time
  var k = 0
  for t in times:
    while k < lumps.len and lumps[k].t <= t:
      y = y * exp(-float(lumps[k].t - at) / tau) + lumps[k].value
      at = lumps[k].t
      inc k
    result.add(
      if k == 0:
        0.0
      else:
        y * exp(-float(t - at) / tau)
    )

proc localDate*(t: int64, tz: Timezone): string =
  ## The date at an instant, in a timezone, like `2018-08-27`.
  fromUnix(t).inZone(tz).format("yyyy-MM-dd")

proc civilOf*(t: int64, tz: Timezone): int64 =
  ## The date at an instant in a timezone, as Unix seconds at its start in UTC (the form of the days of `Params`).
  let d = fromUnix(t).inZone(tz)
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, 0, utc()).toTime.toUnix

proc dayStart*(civil: int64, tz: Timezone): int64 =
  ## The instant a calendar date (as `civilOf` gives it) starts in a timezone.
  let d = fromUnix(civil).utc
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, 0, tz).toTime.toUnix

proc dayEnds*(first, lastCivil: int64, tz: Timezone): seq[int64] =
  ## The instant each day ends (the next midnight of the timezone), for every day from the one the instant `first` is in
  ## to the date `lastCivil` (as `civilOf` gives it).  None if `first` is in a later day.
  var civil = civilOf(first, tz)
  while civil <= lastCivil:
    result.add dayStart(civil + secondsPerDay, tz)
    civil += secondsPerDay

func hourEnds*(first, last: int64): seq[int64] =
  ## The ends of the hours of the clock (UTC), from the hour the instant `first` is in, up to `last`.
  var h = floorDiv(first, secondsPerHour) * secondsPerHour + secondsPerHour
  while h <= last:
    result.add h
    h += secondsPerHour
