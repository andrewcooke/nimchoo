## Cleaning the positions of an activity before they are stored (dev/CLEANING.md).  Pure: the series in, the series out
## with what was dropped and where a stretch must be split.
##
## What it aims at is what matters downstream: errors of tens of metres and more (cells are about 100 m, names look 700 m
## and more away, a climb's gates are 25 m each side).  A wobble of 10 to 20 m is left alone on purpose.  The constants of
## `Tuning` are chosen by that consequence, and the tests show that the removals do not change over a wide range of them.
##
## 1. **Stale positions**: the device had no new fix and wrote the last one again.  A run of identical positions with a long
##    step on each side (the ride is moving) is one position, the first; no threshold but "long" (`movingStepM`).
##    An identical position while standing still (no long step either side) is kept.
## 2. **Spikes and bursts**: a position the ride cannot have reached from the last good one in the time (`leewayM` plus the
##    fastest a bicycle goes, or, when the device measured its speed, twice that speed and a little more), while a later
##    position within `burstS` seconds is again reachable: those between are dropped.
## 3. **A jump that does not return**: no later position is reachable from the last good one.  Within `firstFixS` of
##    the start of the recording, the positions before the jump were a poor first fix: they are dropped.  Later, the
##    stretch is split there (nothing measures distance, a climb or an effort across it: there is no telling which side is
##    wrong).
##
## A dropped position leaves that second without one; the other channels of the second are untouched.  Nothing here looks
## at other rides: a ride's cleaned data must not depend on what was imported before it.

import std/[algorithm, math, options]
import ../fit/time
import ../geo/geo
import ./extract

{.push raises: [].}

type
  Fault* = enum
    fStale = "stale position"
    fSpike = "spike or burst"
    fFirstFix = "poor first fix"

  Dropped* = object
    t*: UnixTime
    fault*: Fault

  Cleaned* = object
    kept*: seq[Coord]
    dropped*: seq[Dropped]
    splits*: seq[UnixTime]
      ## the first second of each new stretch, where a jump did not return

  Tuning* = object
    movingStepM*: float
      ## a step this long, either side of a run of identical positions, means the ride was moving
    leewayM*: float ## the error of a position that is not a fault
    fastestMps*: float ## faster than any bicycle goes
    burstS*: int ## how long a run of wrong positions may be
    firstFixS*: int ## how soon after the start a jump is a poor first fix

func tuning*(): Tuning =
  ## The defaults (shown not to matter: tests/importer/test_clean.nim).
  Tuning(movingStepM: 3.0, leewayM: 30.0, fastestMps: 30.0, burstS: 30, firstFixS: 15)

func cleanCoords*(coords: seq[Coord], tune = tuning()): Cleaned =
  ## `coords` in time order, one per second at most (as `extract` gives them).
  if coords.len < 3:
    result.kept = coords
    return
  let pr = projection(coords[0].lon, coords[0].lat) # one projection per ride
  var xy = newSeq[XY](coords.len)
  for i, c in coords:
    xy[i] = pr.project(c.lon, c.lat)
  func gap(a, b: int): float =
    hypot(xy[a].x - xy[b].x, xy[a].y - xy[b].y)

  func same(a, b: int): bool =
    coords[a].lon == coords[b].lon and coords[a].lat == coords[b].lat

  # 1. stale positions
  var live: seq[int]
  var i = 0
  while i < coords.len:
    var e = i
    while e + 1 < coords.len and same(e + 1, i):
      inc e
    live.add i
    if e > i and i >= 1 and e + 1 < coords.len and gap(i - 1, i) >= tune.movingStepM and
        gap(e, e + 1) >= tune.movingStepM:
      for j in i + 1 .. e:
        result.dropped.add Dropped(t: coords[j].t, fault: fStale)
    else:
      for j in i + 1 .. e:
        live.add j
    i = e + 1

  # 2 and 3. spikes, bursts and jumps, walking along with the last good position
  func reachable(a, b: int): bool =
    let dt = float(int64(coords[b].t) - int64(coords[a].t))
    let mps =
      if coords[b].speed.isSome:
        min(tune.fastestMps, 2.0 * coords[b].speed.get + 3.0)
      else:
        tune.fastestMps
    gap(a, b) <= tune.leewayM + dt * mps

  var kept: seq[int] = @[live[0]]
  var good = live[0]
  var k = 1

  func recentMps(): float =
    ## How fast the ride has been going: the median of its last few steps.
    var v: seq[float]
    var j = kept.high
    while j >= 1 and v.len < 5:
      let dt = float(int64(coords[kept[j]].t) - int64(coords[kept[j - 1]].t))
      v.add gap(kept[j - 1], kept[j]) / max(dt, 1.0)
      dec j
    if v.len == 0:
      return 0.0
    v.sort()
    v[v.len div 2]

  func comesBack(a, b: int, mps: float): bool =
    ## Whether `b`, a little later, is where a ride that went on as it had been going could be: much tighter than
    ## `reachable`, which a long wait makes true of anything (30 m/s for 20 s is 600 m).
    let dt = float(int64(coords[b].t) - int64(coords[a].t))
    gap(a, b) <= tune.leewayM + dt * min(tune.fastestMps, 1.5 * mps + 2.0)

  while k < live.len:
    let at = live[k]
    if reachable(good, at):
      kept.add at
      good = at
      inc k
      continue
    var back = -1
      # a later position, soon, where the ride would be had it gone on as it was
    var m = k + 1
    let mps = recentMps()
    while m < live.len and int64(coords[live[m]].t) - int64(coords[at].t) <= tune.burstS:
      if comesBack(good, live[m], mps):
        back = m
        break
      inc m
    let early = int64(coords[at].t) - int64(coords[live[0]].t) <= tune.firstFixS
    if back >= 0 and not (early and back - k > kept.len):
      for j in k ..< back:
        result.dropped.add Dropped(t: coords[live[j]].t, fault: fSpike)
      k = back
    elif early:
      for j in kept:
        result.dropped.add Dropped(t: coords[j].t, fault: fFirstFix)
      kept = @[at]
      good = at
      inc k
    else:
      result.splits.add coords[at].t
      kept.add at
      good = at
      inc k
  for j in kept:
    result.kept.add coords[j]
