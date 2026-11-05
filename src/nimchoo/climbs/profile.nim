## The profile of one stretch of a ride (a timer segment) as the climb detector wants it: the
## altitude at even steps of distance along the ground, cleaned of spikes and smoothed.
##
## The ride has a position and time at each second but no distance, so the distance is worked out
## from the positions (over the ground; the altitude is not part of it).  Samples are put every
## `stepM` metres by interpolating between the recorded points.  The altitude comes only from the
## points that have one; where there is none it is not made up (NaN), and a climb never crosses
## such a gap.  Pure.

import std/[algorithm, math, options]
import ../importer/extract
import ../geo

{.push raises: [].}

const
  stepM* = 10.0                  ## metres between samples
  despikeWidth = 5               ## samples in the median that removes spikes
  smoothWidth = 5                ## samples in the moving average that smooths what is left

type Profile* = object
  step*: float                   ## metres between samples (`stepM`)
  elev*: seq[float]              ## altitude in metres; NaN where there is none
  lon*, lat*: seq[float]         ## position
  t*: seq[float]                 ## Unix seconds

func isNaN(x: float): bool = x != x

func len*(p: Profile): int = p.elev.len

func validRuns*(elev: openArray[float]): seq[Slice[int]] =
  ## The stretches without NaN (as index ranges), each at least two samples long.
  var start = -1
  for i in 0 .. elev.len:
    let ok = i < elev.len and not elev[i].isNaN
    if ok and start < 0: start = i
    if not ok and start >= 0:
      if i - start >= 2: result.add start ..< i
      start = -1

func filtered(elev: seq[float], width: int, median: bool): seq[float] =
  ## A median or a mean of `width` samples round each sample (fewer at the ends of a run without NaN).
  result = elev
  let half = width div 2
  for run in validRuns(elev):
    for i in run:
      let lo = max(run.a, i - half)
      let hi = min(run.b, i + half)
      if median:
        var window = newSeq[float](hi - lo + 1)
        for k in lo .. hi: window[k - lo] = elev[k]
        window.sort
        result[i] = window[window.len div 2]
      else:
        var sum = 0.0
        for k in lo .. hi: sum += elev[k]
        result[i] = sum / float(hi - lo + 1)

func smoothed*(elev: seq[float]): seq[float] =
  ## Without spikes (a median) and smoothed (a moving average).
  filtered(filtered(elev, despikeWidth, median = true), smoothWidth, median = false)

func buildProfile*(coords: openArray[Coord]): Profile =
  ## The profile of the points, which are in time order and belong to one timer segment.
  result.step = stepM
  # distance along the ground to each point; a point that has not moved is left out
  var cum: seq[float]
  var kept: seq[int]
  for i, c in coords:
    if kept.len == 0:
      cum.add 0.0
      kept.add i
    else:
      let prev = coords[kept[^1]]
      let d = haversine(prev.lon, prev.lat, c.lon, c.lat)
      if d > 0:
        cum.add cum[^1] + d
        kept.add i
  if kept.len < 2: return
  let total = cum[^1]
  let n = int(floor(total / stepM)) + 1
  if n < 2: return
  # the points that have an altitude, by distance
  var altD, altV: seq[float]
  for k, i in kept:
    if coords[i].alt.isSome:
      altD.add cum[k]
      altV.add coords[i].alt.get
  result.elev = newSeq[float](n)
  result.lon = newSeq[float](n)
  result.lat = newSeq[float](n)
  result.t = newSeq[float](n)
  var j = 0                      # the recorded point at or before the sample
  var ja = 0                     # ... and the same among those with an altitude
  for s in 0 ..< n:
    let d = float(s) * stepM
    while j + 2 < kept.len and cum[j + 1] <= d: inc j
    let a = coords[kept[j]]
    let b = coords[kept[j + 1]]
    let u = max(0.0, min(1.0, (d - cum[j]) / (cum[j + 1] - cum[j])))
    result.lon[s] = a.lon + u * (b.lon - a.lon)
    result.lat[s] = a.lat + u * (b.lat - a.lat)
    result.t[s] = float(int64(a.t)) + u * float(int64(b.t) - int64(a.t))
    if altD.len >= 2 and d >= altD[0] and d <= altD[^1]:
      while ja + 2 < altD.len and altD[ja + 1] <= d: inc ja
      let v = max(0.0, min(1.0, (d - altD[ja]) / (altD[ja + 1] - altD[ja])))
      result.elev[s] = altV[ja] + v * (altV[ja + 1] - altV[ja])
    else:
      result.elev[s] = NaN
  result.elev = smoothed(result.elev)
