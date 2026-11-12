## The routes of activities, the climbs on them, how often each place was visited, and the gates and efforts of the climbs, as
## GeoJSON: a FeatureCollection with a feature for each activity, climb, cell of the heat, gate and effort.  Every feature says
## what it is in a property `kind` ("route", "climb", "heat", "gate" or "effort") and carries only facts, never colours or
## widths: the page decides how things look.  Pure: the geometry arrives as GeoJSON text from the database (or as numbers), the
## rest is put round it here.

import std/[json, math, options, strutils, times]
import ../../core/ids
import ../util/hashing/hashing
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

type GateLine* = object ## One gate of a climb, drawn as a short line across the road.
  climbId*: int64
  name*: string
  start*: bool ## the start gate; else the finish gate
  ends*: array[2, tuple[lon, lat: float]]

type EffortLine* = object
  ## The part of a ride that is an effort on a climb: its positions between the stored start and finish times.
  activityId*: ActivityId
  climbId*: int64
  name*: string
  startT*, finishT*: float ## Unix seconds, interpolated at the gates
  elapsedS*, startM*: float
  points*: seq[tuple[lon, lat: float]]

type Climb* = object
  id*: int64
  name*: string ## as shown: "Farellones₃"
  category*: string ## "" if none
  lengthM*, gainM*, gradient*: float
  geometry*: string ## GeoJSON text of the climb's line (with heights)

proc isoUtc*(t: UnixTime): string =
  ## "2018-08-27T12:00:00Z"
  const fmt = initTimeFormat("yyyy-MM-dd'T'HH:mm:ss'Z'")
  t.toTime.utc.format(fmt)

proc feature*(r: Route): string =
  ## One feature, on one line.  Properties: kind ("route"), id, start (UTC, ISO 8601), sport,
  ## distance_m (the last two only if known).
  var props =
    "\"kind\":\"route\",\"id\":" & $r.id & ",\"start\":" & escapeJson(isoUtc(r.startT))
  if r.sport.len > 0:
    props.add ",\"sport\":" & escapeJson(r.sport)
  if r.distanceM.isSome:
    props.add ",\"distance_m\":" & formatFloat(r.distanceM.get, ffDecimal, 1)
  "{\"type\":\"Feature\",\"properties\":{" & props & "},\"geometry\":" & r.geometry & "}"

proc climbFeature*(c: Climb): string =
  ## One feature, on one line.  Properties: kind ("climb"), id, name, category (if it has one), length_m, gain_m, gradient
  ## (percent).
  var props = "\"kind\":\"climb\",\"id\":" & $c.id & ",\"name\":" & escapeJson(c.name)
  if c.category.len > 0:
    props.add ",\"category\":" & escapeJson(c.category)
  props.add ",\"length_m\":" & $int(c.lengthM + 0.5) & ",\"gain_m\":" &
    $int(c.gainM + 0.5) & ",\"gradient\":" & formatFloat(c.gradient, ffDecimal, 1)
  "{\"type\":\"Feature\",\"properties\":{" & props & "},\"geometry\":" & c.geometry & "}"

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

proc gateFeature*(g: GateLine): string =
  ## One feature, on one line: a gate as a LineString.  Properties: kind ("gate"), id (of the climb), name, end ("start" or "finish").
  proc pt(p: tuple[lon, lat: float]): string =
    "[" & formatFloat(p.lon, ffDecimal, 6) & "," & formatFloat(p.lat, ffDecimal, 6) & "]"

  "{\"type\":\"Feature\",\"properties\":{\"kind\":\"gate\",\"id\":" & $g.climbId &
    ",\"name\":" & escapeJson(g.name) & ",\"end\":" &
    escapeJson(if g.start: "start" else: "finish") &
    "},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[" & pt(g.ends[0]) & "," &
    pt(g.ends[1]) & "]}}"

proc effortFeature*(e: EffortLine): string =
  ## One feature, on one line: the part of the ride as a LineString.  Properties: kind ("effort"), activity, id (of the climb),
  ## name, start and finish (UTC, ISO 8601), elapsed_s, start_m (how far along the ride the start gate was crossed).
  var coords: seq[string]
  for p in e.points:
    coords.add "[" & formatFloat(p.lon, ffDecimal, 6) & "," &
      formatFloat(p.lat, ffDecimal, 6) & "]"
  "{\"type\":\"Feature\",\"properties\":{\"kind\":\"effort\",\"activity\":" &
    $e.activityId & ",\"id\":" & $e.climbId & ",\"name\":" & escapeJson(e.name) &
    ",\"start\":" & escapeJson(isoUtc(UnixTime(int64(round(e.startT))))) & ",\"finish\":" &
    escapeJson(isoUtc(UnixTime(int64(round(e.finishT))))) & ",\"elapsed_s\":" &
    formatFloat(e.elapsedS, ffDecimal, 1) & ",\"start_m\":" & $int(round(e.startM)) &
    "},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[" & coords.join(",") &
    "]}}"

func climbsKey*(climbs: seq[Climb]): string =
  ## The key of the climbs as they are read (what goes into the file, so nothing that is shown can be left out).
  var text = ""
  for c in climbs:
    text.add climbFeature(c) & "\n"
  sha256Hex(text)[0 ..< 16]

proc gatesKey*(gates: seq[GateLine]): string =
  ## The key of the gates as they are drawn.
  var text = ""
  for g in gates:
    text.add gateFeature(g) & "\n"
  sha256Hex(text)[0 ..< 16]

proc effortsKey*(efforts: seq[EffortLine]): string =
  ## The key of the efforts as they are drawn (so, of the times and of the positions between them).
  var text = ""
  for e in efforts:
    text.add effortFeature(e) & "\n"
  sha256Hex(text)[0 ..< 16]

proc featureCollection*(
    routes: seq[Route],
    climbs: seq[Climb],
    heat: seq[HeatCell] = @[],
    efforts: seq[EffortLine] = @[],
    gates: seq[GateLine] = @[],
): string =
  ## The whole file: valid JSON, a feature to a line, the heat, the routes, the efforts, the climbs and then the gates (so
  ## that each is drawn on top of the one before).
  var fs: seq[string]
  for h in heat:
    fs.add heatFeature(h)
  for r in routes:
    fs.add feature(r)
  for e in efforts:
    fs.add effortFeature(e)
  for c in climbs:
    fs.add climbFeature(c)
  for g in gates:
    fs.add gateFeature(g)
  "{\"type\":\"FeatureCollection\",\"features\":[\n" & fs.join(",\n") & "\n]}\n"
