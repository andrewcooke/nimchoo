## Naming an activity (see TODO.md, "Names refactor and activity naming").  From the route alone:
##
##   shape (shape.nim)        name
##   out and back             "<destination> and back"      the destination is where the ride turns round
##   one way                  "to <destination>"            ... where it ends (the furthest point)
##   loop                     "loop via <feature>"          a feature along the route, well away from the start
##   mixed                    "around <feature>"            (the same)
##   local                    "at <start place>"            (just the start place if that is "near ...")
##
## and a START place of its own, for finding rides from somewhere: the nearest populated place within 5 km, "near ..." out
## to 20 km, none beyond.  Both are text, "" when there is nothing to say (and for `--offline`, which has no GeoNames names).
##
## Destination and feature are found the same way: a landmark of the author's own (landmark/) comes first; else, for a
## destination, anything within 700 m of the turning point; else within half the distance out (at least 1.5 km).  Among
## the features found the kinds go in a fixed order (town, section of a town, park or reserve, lake, range / valley / ...,
## farm or bridge) and the first kind that has anything wins; within a kind the closest.  A feature along a route is one
## within 2 km of it and at least a third of the way out from the start.

import std/[math, options, strutils]
import ../../core/errors
import ../geo/geo
import ./landmarks
import ./[countries, lookup, shape]

{.push raises: [].}

const
  closeM* = 700.0 ## a destination this close to the turning point wins whatever its kind
  minReachM* = 1500.0
    ## the least distance a destination is looked for round the turning point
  viaRouteM* = 2000.0 ## a feature along the route is within this of it
  viaGridM = 2500.0 ## the size of the cells that route is cut into to find them
  startNearM* = 5000.0 ## the start place is this near, or "near ..." up to startFarM
  startFarM* = 20_000.0

type ActivityNames* = object
  start*: string ## "" if none
  name*: string ## "" if none
  shape*: ShapeKind
  gpsErrors*: int
    ## searches for a place not made because the positions were too far apart (bad GPS fixes): the start, the turning
    ## point, and each stretch along the route

func destKind*(f: Found): int =
  ## How a feature ranks as a destination: 1 town, 2 section of a town, 3 park or reserve, 4 lake, 5 range / valley / other
  ## area, 6 farm or bridge; 0 not wanted (abandoned places, and everything else).
  if f.isPlace:
    if f.code in ["PPLQ", "PPLW", "PPLH"]:
      return 0
    return if f.code == "PPLX": 2 else: 1
  case f.code
  of "PRK", "RES", "RESA", "RESF", "RESH", "RESN", "RESV", "RESW": 3
  of "LK", "LKS", "RSV": 4
  of "MTS", "VAL", "VALS", "CNYN", "HLLS", "PLAT", "PLN", "VLC", "DSRT", "GRGE": 5
  of "FRM", "FRMS", "BDG": 6
  else: 0

func choose*(found: openArray[(Found, float)]): Option[Found] =
  ## The first kind that has anything wins; the closest within it.  (Pairs of a feature and its distance.)
  var best = 0
  var bestD = 0.0
  for (f, d) in found:
    let k = destKind(f)
    if k == 0:
      continue
    if result.isNone or k < best or (k == best and d < bestD):
      result = some(f)
      best = k
      bestD = d

func startText*(found: openArray[(Found, float)]): string =
  ## The start place from the features near the start (with their distances): the nearest populated place, plain within
  ## 5 km, "near ..." within 20 km, else "".
  var bestD = startFarM + 1.0
  var name = ""
  for (f, d) in found:
    if f.isPlace and f.code notin ["PPLQ", "PPLW", "PPLH"] and d < bestD:
      bestD = d
      name = f.name
  if name.len == 0 or bestD > startFarM:
    ""
  elif bestD <= startNearM:
    name
  else:
    "near " & name

func nameFor*(shape: ShapeKind, start, destination, via: string): string =
  ## The name in the form of the shape; "" when what it needs is missing.
  case shape
  of skLocal:
    if start.len == 0:
      ""
    elif start.startsWith("near "):
      start
    else:
      "at " & start
  of skOutAndBack:
    (if destination.len > 0: destination & " and back" else: "")
  of skOneWay:
    (if destination.len > 0: "to " & destination else: "")
  of skLoop:
    (if via.len > 0: "loop via " & via else: "")
  of skMixed:
    (if via.len > 0: "around " & via else: "")

proc around(
    n: Names, lon, lat, radiusM: float, gpsErrors: var int
): seq[(Found, float)] {.raises: [StoreError, DownloadError].} =
  ## The features within the radius of a position, with their distances (the names are made available first).  A search
  ## too wide to make (the radius is set by the distance to a position that is a bad fix) is counted in `gpsErrors`.
  case n.prepare([lon], [lat], radiusM).status
  of rdTooWide:
    inc gpsErrors
    return
  of rdNothing:
    return
  of rdReady:
    discard
  for f in n.featuresNear([lon], [lat], radiusM):
    let d = haversine(lon, lat, f.lon, f.lat)
    if d <= radiusM:
      result.add (f, d)

proc nameActivity*(
    n: Names, parts: openArray[Part]
): ActivityNames {.raises: [StoreError, DownloadError].} =
  ## The start place and the name of an activity with this route (its stretches of riding, in order).  The names
  ## along the route are looked for one stretch at a time, so that a stretch with a bad fix is left out (and counted)
  ## and the others are still used.
  var lons, lats: seq[float]
  for part in parts:
    lons.add part.lons
    lats.add part.lats
  if lons.len == 0:
    return
  result.start = startText(n.around(lons[0], lats[0], startFarM, result.gpsErrors))
  let sh = shapeOf(lons, lats)
  result.shape = sh.kind
  if sh.kind == skLocal:
    result.name = nameFor(sh.kind, result.start, "", "")
    return
  let pr = projection(lons[0], lats[0])
  let origin = XY(x: 0.0, y: 0.0)
  case sh.kind
  of skOutAndBack, skOneWay:
    let turn = pr.unproject(sh.points[sh.turn])
    let own = landmarkAt(n.st, turn.lon, turn.lat)
    var destination = ""
    if own.isSome:
      destination = own.get.landmark.name
    else:
      let radius = max(sh.farM / 2.0, minReachM)
      let found = n.around(turn.lon, turn.lat, radius, result.gpsErrors)
      var close: seq[(Found, float)]
      for (f, d) in found:
        if d <= closeM:
          close.add (f, d)
      var pick = choose(close)
      if pick.isNone:
        pick = choose(found)
      if pick.isSome:
        destination = pick.get.name
    result.name = nameFor(sh.kind, result.start, destination, "")
  of skLoop, skMixed:
    # a landmark along the route, well away from the start, else a feature there
    var via = ""
    var bestD = viaRouteM + 1.0
    for l in n.st.listLandmarks():
      let xy = pr.project(l.lon, l.lat)
      let d = pointLineDistance(xy, sh.points)
      if dist(xy, origin) >= sh.farM / 3.0 and d <= l.radiusM and d < bestD:
        via = l.name
        bestD = d
    if via.len == 0:
      var cands: seq[(Found, float)]
      let grid = newRouteGrid(sh.points, viaGridM)
        # (so that a feature is measured only to the route near it)
      for part in parts:
        case n.prepare(part.lons, part.lats, viaRouteM).status
        of rdTooWide:
          inc result.gpsErrors
        of rdNothing:
          discard
        of rdReady:
          for f in n.featuresNear(part.lons, part.lats, viaRouteM):
            let xy = pr.project(f.lon, f.lat)
            if dist(xy, origin) < sh.farM / 3.0:
              continue
            let d = grid.distanceWithin(xy, viaRouteM)
            if d.isSome:
              cands.add (f, d.get)
      let pick = choose(cands)
      if pick.isSome:
        via = pick.get.name
    result.name = nameFor(sh.kind, result.start, "", via)
  of skLocal:
    discard
