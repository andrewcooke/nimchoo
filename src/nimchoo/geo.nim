## Flat geometry for rides, in metres.  Positions come as longitude and latitude in degrees; for
## the distances and crossings here they are projected onto a flat plane round a reference point
## (good to a fraction of a percent over the tens of kilometres of a ride, and the same projection
## is used for everything that is compared).  Pure.

import std/[math, options, tables]

{.push raises: [].}

const earthRadius* = 6_371_008.8 ## metres

type
  XY* = object
    x*, y*: float ## metres east and north of the reference point

  Projection* = object
    lon0, lat0: float
    kx, ky: float ## metres per degree of longitude and latitude

func projection*(lon0, lat0: float): Projection =
  let perDegree = earthRadius * PI / 180.0
  Projection(lon0: lon0, lat0: lat0, kx: perDegree * cos(degToRad(lat0)), ky: perDegree)

func project*(p: Projection, lon, lat: float): XY =
  XY(x: (lon - p.lon0) * p.kx, y: (lat - p.lat0) * p.ky)

func unproject*(p: Projection, xy: XY): tuple[lon, lat: float] =
  (p.lon0 + xy.x / p.kx, p.lat0 + xy.y / p.ky)

func haversine*(lon1, lat1, lon2, lat2: float): float =
  ## The distance in metres over the ground between two positions.
  let p1 = degToRad(lat1)
  let p2 = degToRad(lat2)
  let dp = p2 - p1
  let dl = degToRad(lon2 - lon1)
  let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
  2 * earthRadius * arcsin(min(1.0, sqrt(a)))

func dist*(a, b: XY): float =
  hypot(b.x - a.x, b.y - a.y)

func pointSegmentDistance*(p, a, b: XY): float =
  ## The distance from `p` to the segment `ab`.
  let dx = b.x - a.x
  let dy = b.y - a.y
  let len2 = dx * dx + dy * dy
  if len2 == 0:
    return dist(p, a)
  let u = max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
  dist(p, XY(x: a.x + u * dx, y: a.y + u * dy))

func pointLineDistance*(p: XY, line: openArray[XY]): float =
  ## The distance from `p` to the nearest point of the polyline (to the point if it has only one).
  if line.len == 0:
    return Inf
  if line.len == 1:
    return dist(p, line[0])
  result = Inf
  for i in 0 ..< line.high:
    result = min(result, pointSegmentDistance(p, line[i], line[i + 1]))

type RouteGrid* = object
  ## A polyline cut into a grid, to ask how far points are from it without measuring to every segment: each segment is
  ## kept in every cell its bounding box touches.
  cellM: float
  line: seq[XY]
  cells: Table[(int, int), seq[int]]
    ## the segments (by the index of their first point) in each cell

func cellOf(g: RouteGrid, v: float): int =
  int(floor(v / g.cellM))

func newRouteGrid*(line: openArray[XY], cellM: float): RouteGrid =
  ## The grid of the polyline, in cells `cellM` metres square (the radius to be asked about should be about the size of a
  ## cell or less: a bigger radius still gives the right answers, but looks in more cells).
  result =
    RouteGrid(cellM: cellM, line: @line, cells: initTable[(int, int), seq[int]]())
  if line.len == 0:
    return
  for i in 0 ..< max(1, line.high):
    let a = line[i]
    let b = line[min(i + 1, line.high)]
    for cx in result.cellOf(min(a.x, b.x)) .. result.cellOf(max(a.x, b.x)):
      for cy in result.cellOf(min(a.y, b.y)) .. result.cellOf(max(a.y, b.y)):
        result.cells.mgetOrPut((cx, cy), @[]).add i

func distanceWithin*(g: RouteGrid, p: XY, radiusM: float): Option[float] =
  ## The distance from `p` to the nearest point of the polyline, if that is at most `radiusM` (the same as
  ## `pointLineDistance`, which it replaces when only the near points matter); none if it is farther.
  if g.line.len == 0:
    return
  var best = Inf
  for cx in g.cellOf(p.x - radiusM) .. g.cellOf(p.x + radiusM):
    for cy in g.cellOf(p.y - radiusM) .. g.cellOf(p.y + radiusM):
      g.cells.withValue((cx, cy), segments):
        for i in segments:
          best = min(
            best, pointSegmentDistance(p, g.line[i], g.line[min(i + 1, g.line.high)])
          )
  if best <= radiusM:
    some(best)
  else:
    none(float)

func length*(line: openArray[XY]): float =
  for i in 0 ..< line.high:
    result += dist(line[i], line[i + 1])

func intersect*(a1, a2, b1, b2: XY): Option[tuple[ta, tb: float]] =
  ## Where the segments `a1 a2` and `b1 b2` cross: the fraction of the way along each
  ## (0 at the first point, 1 at the second).  None if they are parallel or do not meet.
  let rx = a2.x - a1.x
  let ry = a2.y - a1.y
  let sx = b2.x - b1.x
  let sy = b2.y - b1.y
  let denom = rx * sy - ry * sx
  if denom == 0:
    return none((float, float))
  let qx = b1.x - a1.x
  let qy = b1.y - a1.y
  let ta = (qx * sy - qy * sx) / denom
  let tb = (qx * ry - qy * rx) / denom
  if ta < 0 or ta > 1 or tb < 0 or tb > 1:
    return none((float, float))
  some((ta, tb))

func along*(line: openArray[XY], step: float): seq[XY] =
  ## Points every `step` metres along the polyline, from its start, and its last point.
  if line.len == 0:
    return
  result.add line[0]
  var carried = 0.0 # how far the last point added is back along the current segment
  for i in 0 ..< line.high:
    let segment = dist(line[i], line[i + 1])
    if segment == 0:
      continue
    var at = step - carried # distance along this segment of the next point
    while at <= segment:
      let u = at / segment
      result.add XY(
        x: line[i].x + u * (line[i + 1].x - line[i].x),
        y: line[i].y + u * (line[i + 1].y - line[i].y),
      )
      at += step
    carried = segment - (at - step)
  if dist(result[^1], line[^1]) > 0:
    result.add line[^1]
