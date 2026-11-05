## Naming a climb (see TODO.md, task 13 and 15): from its route (positions in order, the last being the top) it finds
## the country of the top, makes sure the names of that country are in the table (lookup.nim), looks at the features
## near the route and picks a name by the rules of climbpick.nim.  What the caller gets is a result: a name, nothing to
## name it with, or "later" (the network or the disk stopped the names being had: nothing is decided, ask again
## another time).

import std/options
import ../errors
import ../geo
import ./[climbpick, countries, lookup]

{.push raises: [].}

type
  NameStatus* = enum nsNamed, nsNothing, nsLater

  NameResult* = object
    status*: NameStatus
    pick*: Pick                ## when named

func middleOf(route: openArray[XY]): XY =
  ## The point half way along the route.
  let half = route.length / 2.0
  var travelled = 0.0
  for i in 0 ..< route.high:
    let step = dist(route[i], route[i + 1])
    if step > 0 and travelled + step >= half:
      let u = (half - travelled) / step
      return XY(x: route[i].x + u * (route[i + 1].x - route[i].x), y: route[i].y + u * (route[i + 1].y - route[i].y))
    travelled += step
  route[^1]

proc candidatesNear*(n: Names, iso: string, lons, lats: openArray[float]): seq[Candidate]
    {.raises: [StoreError].} =
  ## The features of the country near the climb, with their distances from its top and from its middle.
  if lons.len == 0: return
  let pr = projection(lons[0], lats[0])
  var route: seq[XY]
  for i in 0 ..< lons.len: route.add pr.project(lons[i], lats[i])
  let top = route[^1]
  let middle = middleOf(route)
  for f in n.featuresNear(iso, lons, lats):
    let p = pr.project(f.lon, f.lat)
    result.add Candidate(name: f.name, code: f.code, isPlace: f.isPlace, fromTopM: dist(p, top),
                         fromMiddleM: dist(p, middle))

proc nameClimb*(n: Names, lons, lats: openArray[float]): NameResult {.raises: [StoreError].} =
  ## The name for a climb, if the names can be had now.
  if lons.len == 0: return NameResult(status: nsNothing)
  let ready = n.prepare(lons[^1], lats[^1])
  case ready.status
  of rdLater: return NameResult(status: nsLater)
  of rdNothing: return NameResult(status: nsNothing)
  of rdReady: discard
  let p = pickClimbName(n.candidatesNear(ready.iso, lons, lats))
  if p.isSome: NameResult(status: nsNamed, pick: p.get) else: NameResult(status: nsNothing)
