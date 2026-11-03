## Fitness and fatigue: what the hourly impulses (model/calc.nim) add up to, with each hour's
## effort fading away exponentially.  Pure.
##
## Both curves are the same calculation with a different decay time (42 days for fitness, 7 for
## fatigue in the default model): `y[h] = y[h-1] * exp(-1 hour / tau) + x[h]`, where `x[h]` is
## the impulse of hour `h` and the curve starts from 0.  (The original has a starting value and a
## scale; see TODO.md, task 7, for why they are gone.  The scale is an option of the command.)
## An hour's impulse counts as at the end of that hour, as in the original.
## (The hours are those of the clock in UTC; days are the timezone's.)

import std/[math, times]
import ../model/calc

{.push raises: [].}

const
  secondsPerDay* = 86400'i64

func decayPerHour*(tauDays: float): float =
  ## How much of a value is left an hour later.
  exp(-1.0 / (tauDays * 24.0))

func response*(impulses: openArray[Hourly], tauDays: float, lastHour: int64): seq[Hourly] =
  ## The curve for every hour from the first with an impulse to `lastHour` (the start of an
  ## hour, Unix seconds), each value that at the end of its hour.  `impulses` are in time order,
  ## one to an hour.  Empty if there are none, or they all come after `lastHour`.
  if impulses.len == 0 or impulses[0].hourT > lastHour: return
  let decay = decayPerHour(tauDays)
  var y = 0.0
  var k = 0
  var h = impulses[0].hourT
  while h <= lastHour:
    y *= decay
    if k < impulses.len and impulses[k].hourT == h:
      y += impulses[k].value
      inc k
    result.add (h, y)
    h += bucketSeconds

proc localDate*(t: int64, tz: Timezone): string =
  ## The date at an instant, in a timezone, like `2018-08-27`.
  fromUnix(t).inZone(tz).format("yyyy-MM-dd")

proc dayEnds*(series: openArray[Hourly], tz: Timezone): seq[Hourly] =
  ## The values at the end of each day of the timezone: for each date, the last hour that ends
  ## before midnight is over (in a timezone with a half-hour offset that is the hour ending half
  ## an hour before it).  The key is the start of that hour.
  for k, x in series:
    if k + 1 == series.len or
       localDate(x.hourT + bucketSeconds - 1, tz) != localDate(series[k + 1].hourT + bucketSeconds - 1, tz):
      result.add x
