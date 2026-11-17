## The routes of activities and how often each place was visited (the heat), as GeoJSON features for the map's frames
## (`mapframes.nim`).  Every feature says what it is in a property `kind` ("route", "heat") and carries only facts, never
## colours or widths: the frame's drawing decides how things look.  Pure: the geometry arrives as GeoJSON text from the
## database (or as numbers), the rest is put round it here.

import std/[json, math, options, strutils, times]
import ../../core/ids
import ../fit/time
import ../geo/cells

{.push raises: [].}

type Route* = object
  id*: ActivityId
  startT*: UnixTime
  sport*: string ## "" if unknown
  distanceM*: Option[float]
  geometry*: string ## GeoJSON text of the route (a LineString or MultiLineString)

type HeatCell* = object
  ## A cell of the grid at a level (`bits`, see geo/cells.nim), with how often it was visited.
  cell*: Cell ## of the level
  bits*: int
  visits*: int ## the visits of the activities (`route_cell` rows) to the cells it holds
  rides*: int ## how many different activities visited it

proc isoUtc*(t: UnixTime): string =
  ## "2018-08-27T12:00:00Z"
  const fmt = initTimeFormat("yyyy-MM-dd'T'HH:mm:ss'Z'")
  t.toTime.utc.format(fmt)

proc routeFeature*(r: Route): string =
  ## One feature, on one line.  Properties: kind ("route"), id, start (UTC, ISO 8601), sport,
  ## distance_m (the last two only if known).
  var props =
    "\"kind\":\"route\",\"id\":" & $r.id & ",\"start\":" & escapeJson(isoUtc(r.startT))
  if r.sport.len > 0:
    props.add ",\"sport\":" & escapeJson(r.sport)
  if r.distanceM.isSome:
    props.add ",\"distance_m\":" & formatFloat(r.distanceM.get, ffDecimal, 1)
  "{\"type\":\"Feature\",\"properties\":{" & props & "},\"geometry\":" & r.geometry & "}"

proc heatFeature*(h: HeatCell): string =
  ## One feature, on one line: the cell as a square (a Polygon).  Properties: kind ("heat"), level (the `bits` of its cells: 0 is
  ## the finest, each more is twice as wide), visits, rides.
  let b = bounds(h.cell, h.bits)
  proc pt(lon, lat: float): string =
    "[" & formatFloat(lon, ffDecimal, 6) & "," & formatFloat(lat, ffDecimal, 6) & "]"

  let ring = [
    pt(b.west, b.south),
    pt(b.east, b.south),
    pt(b.east, b.north),
    pt(b.west, b.north),
    pt(b.west, b.south),
  ].join(",")
  "{\"type\":\"Feature\",\"properties\":{\"kind\":\"heat\",\"level\":" & $h.bits &
    ",\"visits\":" & $h.visits & ",\"rides\":" & $h.rides &
    "},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[" & ring & "]]}}"
