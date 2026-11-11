## Made-up routes for tests of the climbs: waypoints in metres east and north of the origin on the equator.

import nimchoo/packages/climbs/match
import nimchoo/packages/geo/geo

let pr* = projection(0.0, 0.0)

proc pathOf*(
    waypoints: openArray[(float, float)],
    spacing: float,
    speed = 0.0,
    t0 = 0.0,
    slope = 0.0,
): Path =
  ## A route through the waypoints (metres east and north of the origin, on the equator), a point
  ## every `spacing` metres; with a `speed` it has times, with a `slope` altitudes (that much per
  ## metre east).
  var pts: seq[XY]
  for (x, y) in waypoints:
    pts.add XY(x: x, y: y)
  let sampled = pts.along(spacing)
  var travelled = 0.0
  for i, p in sampled:
    if i > 0:
      travelled += dist(sampled[i - 1], p)
    let (lon, lat) = pr.unproject(p)
    result.lon.add lon
    result.lat.add lat
    if speed > 0:
      result.t.add t0 + travelled / speed
    if slope != 0:
      result.elev.add slope * p.x
