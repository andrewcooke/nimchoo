## Naming a climb (see TODO.md, task 13 and 15): from its route (positions in order, the last being the top) it finds
## the country of the top, makes sure the names of that country are in the table (lookup.nim), looks at the features
## near the route and picks a name by the rules of climbpick.nim; a landmark (landmark/) holding the top comes first.  A name, or none; or a DownloadError if the names
## were needed and could not be had.

import std/options
import ../errors
import ../geo
import ../landmark/landmarks
import ./[climbpick, countries, lookup]

{.push raises: [].}

func middleOf(route: openArray[XY]): XY =
  ## The point half way along the route.
  let half = route.length / 2.0
  var travelled = 0.0
  for i in 0 ..< route.high:
    let step = dist(route[i], route[i + 1])
    if step > 0 and travelled + step >= half:
      let u = (half - travelled) / step
      return XY(
        x: route[i].x + u * (route[i + 1].x - route[i].x),
        y: route[i].y + u * (route[i + 1].y - route[i].y),
      )
    travelled += step
  route[^1]

proc candidatesNear*(
    n: Names, lons, lats: openArray[float]
): seq[Candidate] {.raises: [StoreError].} =
  ## The features near the climb, with their distances from its top and from its middle.
  if lons.len == 0:
    return
  let pr = projection(lons[0], lats[0])
  var route: seq[XY]
  for i in 0 ..< lons.len:
    route.add pr.project(lons[i], lats[i])
  let top = route[^1]
  let middle = middleOf(route)
  for f in n.featuresNear(lons, lats):
    let p = pr.project(f.lon, f.lat)
    result.add Candidate(
      name: f.name,
      code: f.code,
      isPlace: f.isPlace,
      fromTopM: dist(p, top),
      fromMiddleM: dist(p, middle),
    )

proc nameClimb*(
    n: Names, lons, lats: openArray[float]
): Option[Pick] {.raises: [StoreError, DownloadError].} =
  ## The name for a climb: none if there is nothing near to name it by, or `--offline`.  A DownloadError if the
  ## names are needed and cannot be had.
  if lons.len == 0:
    return none(Pick)
  # a landmark of the author's own comes before everything (even offline: it is not a download)
  let own = landmarkAt(n.st, lons[^1], lats[^1])
  if own.isSome:
    return some(
      Pick(
        name: own.get.landmark.name,
        kind: pkLandmark,
        tier: 0,
        distanceM: own.get.distanceM,
      )
    )
  if n.prepare(lons, lats).status != rdReady:
    return none(Pick)
  pickClimbName(n.candidatesNear(lons, lats))
