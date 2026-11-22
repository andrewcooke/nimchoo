## The box round a circle or round some positions, in degrees: what a spatial index is asked for.  Pure.
##
## A distance in metres is turned into degrees with one figure (`geo.metresPerDegree`): a degree of latitude is the same
## everywhere, a degree of longitude is shorter towards the poles (the box then reaches further in longitude, up to the whole
## circle).  A box that goes past the date line (longitude 180 / -180) is **two** boxes, one on each side (`split`): a
## search in one box alone would miss the other side.

import std/math
import ./geo

{.push raises: [].}

type Box* = object ## degrees
  minX*, minY*, maxX*, maxY*: float

const
  wholeCircle = 89.0 ## the latitude from which a box takes every longitude
  shortestCos = 0.02
    ## a degree of longitude is never taken as shorter than this share of one at the equator

func widened*(lons, lats: openArray[float], marginM: float): Box =
  ## The box round the positions, widened by the margin in metres.  Its longitudes may pass 180 or -180 (`split` gives the
  ## parts); near a pole they cover more than the whole circle.  No positions: an empty box at the origin.
  if lons.len == 0:
    return Box()
  result = Box(minX: Inf, minY: Inf, maxX: -Inf, maxY: -Inf)
  for i in 0 ..< lons.len:
    result.minX = min(result.minX, lons[i])
    result.minY = min(result.minY, lats[i])
    result.maxX = max(result.maxX, lons[i])
    result.maxY = max(result.maxY, lats[i])
  let dLat = marginM / metresPerDegree
  let worst = max(abs(result.minY), abs(result.maxY)) + dLat
    # the latitude where a degree of longitude is shortest
  let dLon =
    if worst >= wholeCircle:
      360.0
    else:
      dLat / max(cos(degToRad(worst)), shortestCos)
  result.minX -= dLon
  result.maxX += dLon
  result.minY = max(-90.0, result.minY - dLat)
  result.maxY = min(90.0, result.maxY + dLat)

func split*(b: Box): seq[Box] =
  ## The box as boxes with longitudes from -180 to 180: one, or two where it goes past the date line (the part on the other
  ## side); the whole range of longitudes if it is 360 degrees wide or more.
  if b.maxX - b.minX >= 360.0:
    return @[Box(minX: -180.0, maxX: 180.0, minY: b.minY, maxY: b.maxY)]
  var west = b.minX
  var east = b.maxX
  # (a box that starts past one side is the same box moved by a turn)
  if east > 180.0 and west >= 180.0:
    west -= 360.0
    east -= 360.0
  elif west < -180.0 and east <= -180.0:
    west += 360.0
    east += 360.0
  result.add Box(
    minX: max(-180.0, west), maxX: min(180.0, east), minY: b.minY, maxY: b.maxY
  )
  if west < -180.0:
    result.add Box(minX: west + 360.0, maxX: 180.0, minY: b.minY, maxY: b.maxY)
  if east > 180.0:
    result.add Box(minX: -180.0, maxX: east - 360.0, minY: b.minY, maxY: b.maxY)

func circleBoxes*(lon, lat, radiusM: float): seq[Box] =
  ## The boxes that hold the circle of the radius round the point.
  split(widened([lon], [lat], radiusM))
