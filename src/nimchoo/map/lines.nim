## The routes of activities and the climbs on them as GeoJSON: a FeatureCollection with a feature for each activity and
## a feature for each climb.  Every feature says what it is in a property `kind` ("route" or "climb") and carries only
## facts, never colours or widths: the page decides how things look.  The request that made the file is written into
## it (`nch.request`), and the key of the inputs it was made from (`nch.inputs`), to tell the file when it is found again.  Pure: the geometry arrives as GeoJSON text from the
## database, the rest is put round it here.

import std/[json, options, strutils, times]
import ../core/ids
import ../hashing
import ../fit/time

{.push raises: [].}

type Route* = object
  id*: ActivityId
  startT*: UnixTime
  sport*: string ## "" if unknown
  distanceM*: Option[float]
  geometry*: string ## GeoJSON text of the route (a LineString or MultiLineString)

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

const filePrefix* = "{\"type\":\"FeatureCollection\",\"nch\":{\"request\":"
  ## What every file starts with, up to the request: so a file found by its name can be checked to be for that request.

func requestPrefixFor*(request: string): string =
  ## ... up to the inputs: the file is for this request (a file found by a name that is another request's is not ours).
  filePrefix & escapeJson(request) & ",\"inputs\":"

func filePrefixFor*(request, inputs: string): string =
  ## ... through the key of the inputs: the file is for this request and was made from these inputs.
  requestPrefixFor(request) & escapeJson(inputs) & "},"

func climbsKey*(climbs: seq[Climb]): string =
  ## The key of the climbs as they are read (what goes into the file, so nothing that is shown can be left out).
  var text = ""
  for c in climbs:
    text.add climbFeature(c) & "\n"
  sha256Hex(text)[0 ..< 16]

proc featureCollection*(
    routes: seq[Route], climbs: seq[Climb], request, inputs: string
): string =
  ## The whole file: valid JSON, a feature to a line, the routes and then the climbs (so they are drawn on top).
  var fs: seq[string]
  for r in routes:
    fs.add feature(r)
  for c in climbs:
    fs.add climbFeature(c)
  filePrefixFor(request, inputs) & "\"features\":[\n" & fs.join(",\n") & "\n]}\n"
