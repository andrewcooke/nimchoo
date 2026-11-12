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
## Whether a climb found on a ride is a stored one again, and which stored climbs are near copies of each other, is asked
## of SpatiaLite (`overlap.nim`).  Pure.

import std/[algorithm, math, options, strformat, strutils]
import ../geo/geo

{.push raises: [].}

const
  gateRadius* = 25.0
    ## metres each side of the route, for the gates and for "the same place"
  lengthTolerance = 0.05
    ## the ground covered may differ from the sector's length by this

type
  Path* = object
    ## A route as parallel lists: positions, and for a ride the times and altitudes too.
    lon*, lat*: seq[float]
    t*: seq[float] ## Unix seconds (empty for a sector)
    elev*: seq[float] ## metres, NaN if unknown (may be empty)

  Effort* = object ## One pass of a ride over a sector.
    startT*, finishT*: float ## Unix seconds, at the gates
    startDist*: float ## metres along the ride given, at the start gate

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

func parseLineString*(text: Option[string]): Option[Path] =
  ## (`AsText` of a route SpatiaLite cannot read is NULL: that is damaged data too.)
  if text.isSome:
    parseLineString(text.get)
  else:
    none(Path)

func lineStringText*(p: Path): string =
  ## "LINESTRING Z(lon lat alt, ...)" for a route that has altitudes (the writer of a stored route; `parseLineString`
  ## reads it).  A route with none has them as 0.
  var points: seq[string]
  for i in 0 ..< p.len:
    let alt =
      if p.elev.len == p.len:
        p.elev[i]
      else:
        0.0
    points.add fmt"{p.lon[i]:.7f} {p.lat[i]:.7f} {alt:.1f}"
  "LINESTRING Z(" & points.join(", ") & ")"

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

func gateLines*(
    sector: Path
): Option[tuple[start, finish: array[2, tuple[lon, lat: float]]]] =
  ## The two gates of a sector as the ends of two lines, in longitude and latitude, for drawing them: the same gates `overPaths`
  ## uses (`gates`).  None if the sector has no length.
  if sector.len < 2:
    return
  let pr = projection(sector.lon[0], sector.lat[0])
  let g = gates(sector.xy(pr))
  if g.isNone:
    return
  some(
    (
      start: [pr.unproject(g.get.start.a), pr.unproject(g.get.start.b)],
      finish: [pr.unproject(g.get.finish.a), pr.unproject(g.get.finish.b)],
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
  ##
  ## Nim and not SpatiaLite (measured 2026-11-11, HISTORY.md "Overlap of climbs in SQL"): the same times came out, but the
  ## crossings of one sector took 4.5 to 7 s, because a segment is built for every second of every ride near it, and it could
  ## not read the arrays of TODO item 7.  Do not move it without measuring again.
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
  # the pairs that cover about the right ground, the one closest to the sector's length first; those that overlap one
  # taken are dropped.  Closest and not shortest: where the road folds back through a gate, the ride crosses it a second
  # time going the other way, and the pair from that crossing is shorter than the sector (HISTORY.md "Gates have no
  # direction").
  var pairs: seq[tuple[s, f: Crossing]]
  for s in starts:
    for f in finishes:
      let covered = f.dist - s.dist
      if f.pos > s.pos and covered >= (1 - lengthTolerance) * length and
          covered <= (1 + lengthTolerance) * length:
        pairs.add (s, f)
  pairs.sort(
    proc(a, b: tuple[s, f: Crossing]): int =
      cmp(abs(a.f.dist - a.s.dist - length), abs(b.f.dist - b.s.dist - length))
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
      startT: ride.t.at(p.s.pos), finishT: ride.t.at(p.f.pos), startDist: p.s.dist
    )
