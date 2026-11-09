## The training impulse of a stretch of heart rate.  Pure.
##
## From the readings (time, beats per minute) of an activity: the heart-rate zone at each
## reading, a number from 1 to 6 (from the threshold heart rate and the zone edges); the zone
## between two readings is a straight line in time; the impulse of an instant is
## `((zone - zero) / (one - zero)) ^ gamma`, clipped at 0; and the impulse of an hour is the
## integral of that over the time the readings cover.  Two readings further apart than
## `max_secs` cover nothing.  The unit is the Python original's: the impulse "per 10 seconds"
## (a zone-6 effort for 10 seconds is 1).  The original works on a 10-second grid for the
## sake of pandas; this integrates exactly, so an irregular recording interval has no effect.

import std/math
import ../packages/fit/time
import ../core/ids

{.push raises: [].}

const
  bucketSeconds* = 3600'i64
    ## The impulses are kept by the hour.  Not a variable: changing it would leave every stored
    ## impulse on the wrong grid.  (A lump counts as at the end of its hour when the curves are
    ## made, as in the original; the error against the true time is at most hour / decay time of
    ## the lump, 0.6% for the 7-day curve, 0.3% on average.)
  unitSeconds* = 10.0 ## the impulse is "per 10 seconds"

type
  Model* = object
    id*: ModelId
    name*: string
    gamma*, zero*, one*: float
    maxSecs*: int
    zones*: array[5, float]
      ## upper limits of zones 1 to 5, percent of the threshold heart rate
    fitnessDays*, fatigueDays*: float

  Hourly* = tuple[hourT: int64, value: float]
    ## the start of the hour, Unix seconds (plain: the curves are arithmetic on a grid of hours)

func defaultModel*(): Model =
  ## The values the original uses (the zone edges are British Cycling's).
  Model(
    name: "default",
    gamma: 2,
    zero: 1,
    one: 6,
    maxSecs: 60,
    zones: [68.0, 83, 94, 105, 121],
    fitnessDays: 42,
    fatigueDays: 7,
  )

func problem*(m: Model): string =
  ## Why a model cannot be used ("" if it can).
  if not (m.gamma > 0):
    return "gamma must be above 0"
  if not (m.zero < m.one):
    return "zero must be less than one"
  if m.maxSecs < 1:
    return "max-secs must be at least 1"
  if m.zones[0] <= 0:
    return "the zone edges must be above 0"
  for i in 1 .. 4:
    if not (m.zones[i - 1] < m.zones[i]):
      return "the zone edges must increase"
  if not (m.fitnessDays > 0 and m.fatigueDays > 0):
    return "the decay times must be above 0"

func zoneOf*(bpm, fthr: float, edges: array[5, float]): float =
  ## The heart-rate zone, from 1 to 6: 1 up to the first edge, then rising from one whole number
  ## to the next across each band, and 6 above the last edge.
  var lower = 0.0
  for i in 0 .. 4:
    let upper = edges[i] * fthr / 100
    if bpm <= upper:
      return
        if i == 0:
          1.0
        else:
          float(i + 1) + (bpm - lower) / (upper - lower)
    lower = upper
  6.0

func level*(zone: float, m: Model): float =
  ## Where a zone lies between `zero` (0) and `one` (1); below zero it is negative.
  (zone - m.zero) / (m.one - m.zero)

func powIntegral*(u0, u1, dt, g: float): float =
  ## The integral over `dt` of `max(u, 0) ^ g`, where u runs in a straight line from u0 to u1.
  if dt <= 0 or (u0 <= 0 and u1 <= 0):
    return 0
  var a = u0
  var b = u1
  var length = dt
  if a < 0: # (then b > 0) only the part after it crosses 0
    length = dt * b / (b - a)
    a = 0
  elif b < 0:
    length = dt * a / (a - b)
    b = 0
  if abs(b - a) <= 1e-9 * max(a, b):
    return length * pow((a + b) / 2, g)
  length * (pow(b, g + 1) - pow(a, g + 1)) / ((g + 1) * (b - a))

func hourlyImpulse*(
    readings: openArray[(UnixTime, int)], fthr: int, m: Model
): seq[Hourly] =
  ## The impulse in each hour that the readings (in time order) cover, in order.  An hour with
  ## readings but nothing above the zero level has value 0, so a row for it records that the
  ## activity was worked out.
  for k in 1 ..< readings.len:
    let (u0t, h0) = readings[k - 1]
    let (u1t, h1) = readings[k]
    let (t0, t1) = (int64(u0t), int64(u1t)) # (plain seconds for the arithmetic)
    if t1 <= t0 or t1 - t0 > m.maxSecs:
      continue
    let u0 = level(zoneOf(float(h0), float(fthr), m.zones), m)
    let u1 = level(zoneOf(float(h1), float(fthr), m.zones), m)
    var cur = t0
    var uCur = u0
    while cur < t1:
      let hour = floorDiv(cur, bucketSeconds) * bucketSeconds
      let nxt = min(t1, hour + bucketSeconds)
      let uNxt = u0 + (u1 - u0) * float(nxt - t0) / float(t1 - t0)
      let part = powIntegral(uCur, uNxt, float(nxt - cur), m.gamma) / unitSeconds
      if result.len > 0 and result[^1].hourT == hour:
        result[^1].value += part
      else:
        result.add (hour, part)
      cur = nxt
      uCur = uNxt
