## Matching a ride to a stored climb (a "sector"), and telling whether a newly found climb is a
## stored one again: a port of choochoo's way (py/ch2/data/sector.py, pipeline/calculate/climb.py).
##
## A sector has a route.  Across the route at its start and at its finish is a gate: a line 25 m
## each side of the route, at right angles to it.  A ride goes over the sector when it crosses
## the start gate and then the finish gate, and the ground it covers between them is within 5 %
## of the sector's length (so a shortcut, a detour or a ride the other way does not count).  The
## times are where the ride crosses the gates, interpolated between its recorded points.  A ride
## may go over a sector more than once (laps): each pass is an effort, and of crossings that
## overlap the shortest is taken.
##
## A climb found on a ride is the same as a stored one if more than half of each lies within 25 m
## of the other (choochoo: less than half of each outside the other's hull).  Pure.

import std/[algorithm, math, options, strutils]
import ../geo

{.push raises: [].}

const
  gateRadius* = 25.0
    ## metres each side of the route, for the gates and for "the same place"
  lengthTolerance = 0.05
    ## the ground covered may differ from the sector's length by this
  repeatLimit = 0.5 ## a repeat if less than this fraction of each is outside the other
  nearCopyLimit = 0.2
    ## a near copy (the duplicates report) if less than this fraction of each is outside the other
  sampleStep = 5.0 ## metres between the points taken along a route to compare it

type
  Path* = object
    ## A route as parallel lists: positions, and for a ride the times and altitudes too.
    lon*, lat*: seq[float]
    t*: seq[float] ## Unix seconds (empty for a sector)
    elev*: seq[float] ## metres, NaN if unknown (may be empty)

  Effort* = object ## One pass of a ride over a sector.
    startT*, finishT*: float ## Unix seconds, at the gates
    startDist*, finishDist*: float ## metres along the ride given
    startElev*, finishElev*: float ## NaN if unknown

func elapsed*(e: Effort): float =
  ## Seconds from the start of the effort to its finish.
  e.finishT - e.startT

func len*(p: Path): int =
  ## The number of points.
  p.lon.len

func parseLineString*(text: string): Option[Path] =
  ## The positions of "LINESTRING Z(lon lat alt, ...)" (SpatiaLite's `AsText`), the one reader of a stored route.  None
  ## if the text is not a route: no brackets, fewer than two points, a point without two finite numbers.  (A route
  ## that cannot be read is damaged data: callers say so and leave the work undone; none of them treats it as an empty
  ## route, which would be stored as "nothing here".)
  let a = text.find('(')
  let b = text.rfind(')')
  if a < 0 or b <= a:
    return
  var p: Path
  try:
    for part in text[a + 1 ..< b].split(','):
      let f = part.splitWhitespace
      if f.len < 2:
        return
      let lon = parseFloat(f[0])
      let lat = parseFloat(f[1])
      if classify(lon) in {fcNan, fcInf, fcNegInf} or
          classify(lat) in {fcNan, fcInf, fcNegInf}:
        return
      p.lon.add lon
      p.lat.add lat
  except ValueError:
    return
  if p.len >= 2:
    some(p)
  else:
    none(Path)

func xy(p: Path, pr: Projection): seq[XY] =
  for i in 0 ..< p.len:
    result.add pr.project(p.lon[i], p.lat[i])

func bounds(pts: openArray[XY]): tuple[x0, y0, x1, y1: float] =
  result = (Inf, Inf, -Inf, -Inf)
  for p in pts:
    result.x0 = min(result.x0, p.x)
    result.y0 = min(result.y0, p.y)
    result.x1 = max(result.x1, p.x)
    result.y1 = max(result.y1, p.y)

func apart(a, b: tuple[x0, y0, x1, y1: float], margin: float): bool =
  ## Whether the boxes are more than `margin` apart.
  a.x1 + margin < b.x0 or b.x1 + margin < a.x0 or a.y1 + margin < b.y0 or
    b.y1 + margin < a.y0

type Gate = tuple[a, b: XY]

func gateAt(centre, direction: XY): Gate =
  ## The line across the route at `centre`, `gateRadius` each side, at right angles to `direction`.
  let n = hypot(direction.x, direction.y)
  let nx = -direction.y / n
  let ny = direction.x / n
  (
    XY(x: centre.x - gateRadius * nx, y: centre.y - gateRadius * ny),
    XY(x: centre.x + gateRadius * nx, y: centre.y + gateRadius * ny),
  )

func gates(route: openArray[XY]): Option[tuple[start, finish: Gate]] =
  ## The gates of a route: across it at its first and last points, at right angles to the first
  ## and last metre.  None if the route has no length.
  var k = 1
  while k < route.len and dist(route[0], route[k]) < 1.0:
    inc k
  var j = route.len - 2
  while j >= 0 and dist(route[j], route[^1]) < 1.0:
    dec j
  if k >= route.len or j < 0:
    return none((Gate, Gate))
  some(
    (
      gateAt(route[0], XY(x: route[k].x - route[0].x, y: route[k].y - route[0].y)),
      gateAt(route[^1], XY(x: route[^1].x - route[j].x, y: route[^1].y - route[j].y)),
    )
  )

type Crossing = tuple[pos, dist: float]
  ## Where a ride crosses a gate: the position in the ride (the index of the point before it, plus
  ## the fraction of the way to the next), and the distance along the ride.

func crossings(ride: openArray[XY], cum: openArray[float], g: Gate): seq[Crossing] =
  for i in 0 ..< ride.high:
    let hit = intersect(ride[i], ride[i + 1], g.a, g.b)
    if hit.isSome and hit.get.ta < 1.0:
      let u = hit.get.ta
      result.add (float(i) + u, cum[i] + u * (cum[i + 1] - cum[i]))

func at(values: openArray[float], pos: float): float =
  ## A list of values (one to a point of the ride) at a position between the points.
  if values.len == 0:
    return NaN
  let i = min(int(floor(pos)), values.high - 1)
  if i < 0:
    return NaN
  let u = pos - float(i)
  values[i] + u * (values[i + 1] - values[i])

func overPaths*(sector, ride: Path): seq[Effort] =
  ## The passes of `ride` (one stretch of a ride, so that the time is continuous) over `sector`, in
  ## order.  Empty if it does not go over it.
  if sector.len < 2 or ride.len < 2:
    return
  let pr = projection(sector.lon[0], sector.lat[0])
  let route = sector.xy(pr)
  let rideXY = ride.xy(pr)
  let length = route.length
  if length <= 0:
    return
  if bounds(route).apart(bounds(rideXY), gateRadius):
    return
  let g = gates(route)
  if g.isNone:
    return
  var cum = newSeq[float](rideXY.len)
  for i in 1 ..< rideXY.len:
    cum[i] = cum[i - 1] + dist(rideXY[i - 1], rideXY[i])
  let starts = crossings(rideXY, cum, g.get.start)
  let finishes = crossings(rideXY, cum, g.get.finish)
  # the pairs that cover about the right ground, shortest first; those that overlap one taken are dropped
  var pairs: seq[tuple[s, f: Crossing]]
  for s in starts:
    for f in finishes:
      let covered = f.dist - s.dist
      if f.pos > s.pos and covered >= (1 - lengthTolerance) * length and
          covered <= (1 + lengthTolerance) * length:
        pairs.add (s, f)
  pairs.sort(
    proc(a, b: tuple[s, f: Crossing]): int =
      cmp(a.f.dist - a.s.dist, b.f.dist - b.s.dist)
  )
  var taken: seq[tuple[s, f: Crossing]]
  for p in pairs:
    var overlaps = false
    for q in taken:
      if p.s.pos < q.f.pos and q.s.pos < p.f.pos:
        overlaps = true
        break
    if not overlaps:
      taken.add p
  taken.sort(
    proc(a, b: tuple[s, f: Crossing]): int =
      cmp(a.s.pos, b.s.pos)
  )
  for p in taken:
    result.add Effort(
      startT: ride.t.at(p.s.pos),
      finishT: ride.t.at(p.f.pos),
      startDist: p.s.dist,
      finishDist: p.f.dist,
      startElev: ride.elev.at(p.s.pos),
      finishElev: ride.elev.at(p.f.pos),
    )

func inHull(p: XY, route: openArray[XY]): bool =
  ## Whether the point is within `gateRadius` of the route, not counting the ground beyond its
  ## ends (choochoo's hull is the route widened by 25 m with flat ends).
  for i in 0 ..< route.high:
    let a = route[i]
    let b = route[i + 1]
    let dx = b.x - a.x
    let dy = b.y - a.y
    let len2 = dx * dx + dy * dy
    if len2 == 0:
      continue
    var u = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
    if (i == 0 and u < 0) or (i == route.high - 1 and u > 1):
      continue
    u = max(0.0, min(1.0, u))
    if dist(p, XY(x: a.x + u * dx, y: a.y + u * dy)) <= gateRadius:
      return true

func insideShare(line: openArray[XY], other: openArray[XY]): float =
  ## The share of the length of `line` that is inside the hull of `other`.
  let pts = line.along(sampleStep)
  var inside, total = 0.0
  for i in 0 ..< pts.high:
    let piece = dist(pts[i], pts[i + 1])
    let middle = XY(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
    total += piece
    if inHull(middle, other):
      inside += piece
  if total > 0:
    inside / total
  else:
    0.0

func overlapsBothWays(older, newer: Path, limit: float): bool =
  ## Whether less than `limit` of each path is outside the other (within the gate radius).
  if older.len < 2 or newer.len < 2:
    return false
  let pr = projection(older.lon[0], older.lat[0])
  let a = older.xy(pr)
  let b = newer.xy(pr)
  if bounds(a).apart(bounds(b), gateRadius):
    return false
  let outsideA = 1.0 - insideShare(a, b)
  let outsideB = 1.0 - insideShare(b, a)
  outsideA < limit and outsideB < limit

func isRepeat*(older, newer: Path): bool =
  ## Whether `newer` (a climb just found) is `older` (a stored one) again: less than half of each is outside the other.
  overlapsBothWays(older, newer, repeatLimit)

func isNearCopy*(a, b: Path): bool =
  ## Whether two climbs are nearly the same one, for the duplicates report: less than a fifth of each is outside the
  ## other (so a short climb inside a long one is not, and a chain of climbs that each overlap the next is not).
  overlapsBothWays(a, b, nearCopyLimit)
