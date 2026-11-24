## The training impulse of an activity's heart rate, by stretch of riding.  Pure.
##
## From the readings (time, beats per minute) of an activity: the heart-rate zone at each
## reading, a number from 1 to 6 (from the threshold heart rate and the zone edges); the zone
## between two readings is a straight line in time; the impulse of an instant is
## `((zone - zero) / (one - zero)) ^ gamma`, clipped at 0; and the impulse of a stretch of riding
## (the importer's `segment`) is the integral of that over the time the readings cover, kept as one
## lump at its centre (the time weighted by the impulse).  Fitness and fatigue are then exact sums
## of decaying lumps: measured against an impulse worked out by the minute, the largest difference
## in a day-end's fatigue over the author's history is 0.1 (dev/ff.md).  Two readings further apart
## than `max_gap_s` cover nothing.  The unit is the Python original's: the impulse "per 10 seconds"
## (a zone-6 effort for 10 seconds is 1).  The original works on a 10-second grid for the sake of
## pandas; this integrates exactly, so an irregular recording interval has no effect.

import std/[math, options]
import ../fit/time
import ../tags/tag
import ../../core/ids

{.push raises: [].}

const unitSeconds* = 10.0 ## the impulse is "per 10 seconds"

type
  Model* = object
    id*: ModelId
    name*: string
    gamma*, zero*, one*: float
    maxSecs*: int
    zones*: array[5, float]
      ## upper limits of zones 1 to 5, percent of the threshold heart rate
    fitnessDays*, fatigueDays*: float
    ceiling*: float
      ## readings above this percentage of the threshold heart rate are a fault of the sensor (a strap that reads 243 bpm
      ## for three hours), and are ignored: a gap in the heart rate
    fitnessScale*, fatigueScale*: float
      ## the weights of the curves in form: `fitnessScale * fitness - fatigueScale * fatigue`
    patterns*: seq[TagPattern]
      ## the activities that count: those with a tag matching every one (none: all of them)
    builtIn*: bool ## made by the program: selected for every user from the start

  Stretch* = tuple[startT, endT: int64]
    ## a stretch of riding: its first and last second (Unix seconds, plain: arithmetic)

  Lump* = tuple[t: int64, value: float]
    ## an impulse counted at one instant (Unix seconds)

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
    fitnessScale: 1,
    fatigueScale: 5,
    ceiling: 125,
    builtIn: true,
  )

func sameImpulse*(a, b: Model): bool =
  ## Whether the two give the same impulses (the decays, the scales and the patterns do not change them).
  a.gamma == b.gamma and a.zero == b.zero and a.one == b.one and a.maxSecs == b.maxSecs and
    a.zones == b.zones and a.ceiling == b.ceiling

func problem*(m: Model): Option[string] =
  ## Why a model cannot be used (none if it can).
  if not (m.gamma > 0):
    return some("gamma must be above 0")
  if not (m.zero < m.one):
    return some("zero must be less than one")
  if m.maxSecs < 1:
    return some("max-gap must be at least 1 second")
  if m.zones[0] <= 0:
    return some("the zone edges must be above 0")
  for i in 1 .. 4:
    if not (m.zones[i - 1] < m.zones[i]):
      return some("the zone edges must increase")
  if not (m.fitnessDays > 0 and m.fatigueDays > 0):
    return some("the decay times must be above 0")
  if not (m.ceiling > m.zones[4]):
    return some("the ceiling must be above the last zone edge")
  if not (m.fitnessScale > 0 and m.fatigueScale > 0):
    return some("the scales must be above 0")

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

func withinCeiling*(
    readings: openArray[(UnixTime, int)], fthr: int, m: Model
): tuple[kept: seq[(UnixTime, int)], dropped: int] =
  ## The readings at or below the model's ceiling (a percentage of the threshold heart rate), and how many were above it:
  ## those are a fault of the sensor, and leave a gap in the heart rate (which counts for nothing if it is longer than
  ## `maxSecs`, as any gap).
  let top = m.ceiling * float(fthr) / 100
  for r in readings:
    if float(r[1]) > top:
      inc result.dropped
    else:
      result.kept.add r

func stretchImpulse*(
    readings: openArray[(UnixTime, int)],
    stretches: openArray[Stretch],
    fthr: int,
    m: Model,
): seq[Lump] =
  ## The impulse of each stretch (in time order), at its centre: one lump a stretch, in the same order.  The heart rate
  ## between two stretches (a pause) goes to the nearer, the cut being half way through the gap; before the first and
  ## after the last, to those.  Each piece between two readings counts at its middle (readings are a second or so apart).
  ## A stretch with no impulse has a lump of 0 at its middle, so that every stretch has one.  Nothing if there are no
  ## stretches.
  if stretches.len == 0:
    return
  var cuts = newSeq[float](stretches.len - 1)
  for k in 0 ..< cuts.len:
    cuts[k] = 0.5 * float(stretches[k].endT + stretches[k + 1].startT)
  var total = newSeq[float](stretches.len)
  var weighted = newSeq[float](stretches.len) # the sum of impulse times time
  var k = 0 # the stretch the current time is in
  for i in 1 ..< readings.len:
    let (u0t, h0) = readings[i - 1]
    let (u1t, h1) = readings[i]
    let (t0, t1) = (float(int64(u0t)), float(int64(u1t)))
    if t1 <= t0 or t1 - t0 > float(m.maxSecs):
      continue
    let u0 = level(zoneOf(float(h0), float(fthr), m.zones), m)
    let u1 = level(zoneOf(float(h1), float(fthr), m.zones), m)
    var cur = t0
    var uCur = u0
    while cur < t1:
      while k < cuts.len and cur >= cuts[k]:
        inc k
      let nxt =
        if k < cuts.len:
          min(t1, cuts[k])
        else:
          t1
      let uNxt = u0 + (u1 - u0) * (nxt - t0) / (t1 - t0)
      let part = powIntegral(uCur, uNxt, nxt - cur, m.gamma) / unitSeconds
      total[k] += part
      weighted[k] += part * 0.5 * (cur + nxt)
      cur = nxt
      uCur = uNxt
  for j, s in stretches:
    let centre =
      if total[j] > 0:
        weighted[j] / total[j]
      else:
        0.5 * float(s.startT + s.endT)
    result.add (int64(round(centre)), total[j])
