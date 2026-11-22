## The climbs, their gates and the efforts on them, as GeoJSON features for the map's frames (`mapframes.nim`).  Every feature
## says what it is in a property `kind` ("climb", "gate", "effort") and carries only facts, never colours or widths: the frame's
## drawing decides how things look.  Pure.

import std/[json, math, options, strutils]
import ../../core/ids
import ../activities/mapfeatures
import ../fit/time
import ../ui/[interval, units]

{.push raises: [].}

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
  category*: Option[string] ## none if it has none
  lengthM*, gainM*, gradient*: float
  geometry*: string ## GeoJSON text of the climb's line (with heights)

proc climbFeature*(c: Climb): string =
  ## One feature, on one line.  Properties: kind ("climb"), id, name, category (if it has one), length_m, gain_m, gradient
  ## (percent).
  var props = "\"kind\":\"climb\",\"id\":" & $c.id & ",\"name\":" & escapeJson(c.name)
  if c.category.isSome:
    props.add ",\"category\":" & escapeJson(c.category.get)
  props.add ",\"length_m\":" & $int(c.lengthM + 0.5) & ",\"gain_m\":" &
    $int(c.gainM + 0.5) & ",\"gradient\":" & formatFloat(c.gradient, ffDecimal, 1)
  "{\"type\":\"Feature\",\"properties\":{" & props & "},\"geometry\":" & c.geometry & "}"

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
  ## name, start and finish (UTC, ISO 8601), elapsed (as every interval is written, `22m05s`) and started (how far along the
  ## ride the start gate was crossed, as every distance is written, `3.2km`): the drawing shows them as they are.
  var coords: seq[string]
  for p in e.points:
    coords.add "[" & formatFloat(p.lon, ffDecimal, 6) & "," &
      formatFloat(p.lat, ffDecimal, 6) & "]"
  "{\"type\":\"Feature\",\"properties\":{\"kind\":\"effort\",\"activity\":" &
    $e.activityId & ",\"id\":" & $e.climbId & ",\"name\":" & escapeJson(e.name) &
    ",\"start\":" & escapeJson(isoUtc(UnixTime(int64(round(e.startT))))) & ",\"finish\":" &
    escapeJson(isoUtc(UnixTime(int64(round(e.finishT))))) & ",\"elapsed\":" &
    escapeJson(interval(e.elapsedS)) & ",\"started\":" & escapeJson(km(e.startM)) &
    "},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[" & coords.join(",") &
    "]}}"
