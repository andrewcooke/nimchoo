## Finding the climbs in a profile: a port of choochoo's detector (py/ch2/data/climb.py), whose
## parameters worked well and are not tuned further.
##
## A candidate climb is a start and an end on the profile.  Its score is
##
##     gain / distance ** phi
##
## (phi 0: the gain; phi 1: the gradient; in between, a climb that is both big and steep).  The
## best candidate in a stretch is found (a search of every length, O(n^2): for a long stretch first
## on every 10th sample, then round the hit on every sample), and the stretch before it and the
## stretch after it are searched in the same way.  A climb that has a big descent inside it (more
## than 10 % of its gain) is cut at the descent and the parts are searched again.  Climbs steeper
## than 40 % are errors in the data and are dropped.  Pure.

import std/math
import ./profile

{.push raises: [].}

const
  phi = 0.7                      ## between pure gain (0) and pure gradient (1)
  minGain = 80.0                 ## metres: roughly a strava score of 8000
  minGradient = 3.0              ## percent
  maxGradient = 40.0             ## percent: steeper is an error in the data
  maxReversal = 0.1              ## the descent allowed in a climb, as a fraction of its gain
  grid = 10                      ## the coarse search looks at every 10th sample
  coarseAbove = 100 * grid       ## ... for a stretch of more than this many samples
  categories = [(80.0, "4"), (160.0, "3"), (320.0, "2"), (640.0, "1"), (800.0, "HC")]

type Climb* = object
  first*, last*: int             ## the samples it starts and ends on (indexes in the profile)
  gain*: float                   ## metres
  length*: float                 ## metres
  gradient*: float               ## percent
  category*: string              ## "4" (the smallest), "3", "2", "1" or "HC"; "" if too small

func categoryFor*(gain: float): string =
  ## By the gain, as strava does: 80 m is a 4, 160 a 3, 320 a 2, 640 a 1 and 800 hors catégorie.
  for (height, name) in categories:
    if gain >= height: result = name

type Found = tuple[score: float, lo, hi: int]   # lo = -1 if nothing

func search(e: openArray[float], a, b, stride: int, d: float, shrink: bool): Found =
  ## The best candidate among the samples `a`, `a + stride`... below `b` (spaced `d` metres).
  ## For a fine search the ends are brought in by one sample so that neighbouring climbs touch.
  result = (0.0, -1, -1)
  let m = (b - a + stride - 1) div stride
  if m < 2: return
  let vd = d * float(stride)
  for offset in countdown(m - 1, 1):
    let distance = vd * float(offset)
    let need = max(minGain, minGradient / 100.0 * distance)
    var best = -Inf
    var bestI = -1
    for i in offset ..< m:
      let delta = e[a + i * stride] - e[a + (i - offset) * stride]
      if delta > best:
        best = delta
        bestI = i
    if best > need:
      let score = best / pow(distance, phi)
      if score > result.score:
        var lo = bestI - offset
        var hi = bestI
        if shrink:
          inc lo
          dec hi
        if hi > lo: result = (score, a + lo * stride, a + hi * stride)

func biggestClimb(e: openArray[float], a, b: int, d: float): Found =
  if b - a > coarseAbove:
    let rough = search(e, a, b, grid, d, shrink = false)
    if rough.lo < 0: return (0.0, -1, -1)
    # round it, on every sample
    let wa = max(a, rough.lo - grid)
    let wb = min(rough.hi + grid, b - 1)
    search(e, wa, wb, 1, d, shrink = true)
  else:
    search(e, a, b, 1, d, shrink = true)

func biggestReversal(e: openArray[float], a, b: int): tuple[down: float, trough, peak: int] =
  ## The biggest drop from one sample to a later one: its size, and where it ends and starts.
  result = (0.0, -1, -1)
  for offset in 1 .. b - a - 2:
    var best = -Inf
    var bestI = -1
    for i in a ..< b - offset:
      let drop = e[i] - e[i + offset]
      if drop > best:
        best = drop
        bestI = i
    if best > result.down: result = (best, bestI + offset, bestI)

func find(e: openArray[float], a, b: int, d: float, found: var seq[(int, int)])

func contiguous(e: openArray[float], a, b: int, d: float, found: var seq[(int, int)]) =
  ## `a ..< b` holds one climb, if it holds one: it is cut where a big descent splits it.
  if b - a < 2: return
  let up = e[b - 1] - e[a]
  if up < minGain: return
  let (down, trough, peak) = biggestReversal(e, a, b)
  if down > 0 and down > maxReversal * up:
    contiguous(e, a, peak + 1, d, found)
    find(e, peak + 1, trough, d, found)
    contiguous(e, trough, b, d, found)
  else:
    let along = float(b - 1 - a) * d
    if along > 0 and 100.0 * up / along < maxGradient: found.add (a, b - 1)

func find(e: openArray[float], a, b: int, d: float, found: var seq[(int, int)]) =
  ## The climbs in `a ..< b`, in order.
  if b - a < 2: return
  var lowest = e[a]
  var highest = e[a]
  for i in a ..< b:
    lowest = min(lowest, e[i])
    highest = max(highest, e[i])
  if highest - lowest <= minGain: return
  let best = biggestClimb(e, a, b, d)
  if best.lo < 0: return
  find(e, a, best.lo, d, found)
  contiguous(e, best.lo, best.hi + 1, d, found)
  find(e, best.hi + 1, b, d, found)

func makeClimb(e: openArray[float], first, last: int, d: float): Climb =
  let gain = e[last] - e[first]
  let length = float(last - first) * d
  Climb(first: first, last: last, gain: gain, length: length,
        gradient: if length > 0: 100.0 * gain / length else: 0.0, category: categoryFor(gain))

func findClimbs*(elev: openArray[float], step: float): seq[Climb] =
  ## The climbs in altitudes `step` metres apart (no NaN), in order along the route.
  var spans: seq[(int, int)]
  find(elev, 0, elev.len, step, spans)
  for (first, last) in spans: result.add makeClimb(elev, first, last, step)

func findClimbs*(p: Profile): seq[Climb] =
  ## The climbs of a profile: in each stretch that has an altitude (a climb does not cross a gap).
  for run in validRuns(p.elev):
    for c in findClimbs(p.elev.toOpenArray(run.a, run.b), p.step):
      var shifted = c
      shifted.first += run.a
      shifted.last += run.a
      result.add shifted
