## The routes of activities as GeoJSON: a FeatureCollection with one feature
## for each activity.  Pure: the geometry arrives as GeoJSON text from the
## database, the rest is put round it here.

import std/[json, options, strutils, times]
import ../fit/time
import ../ids

{.push raises: [].}

type Route* = object
  id*: ActivityId
  startT*: UnixTime
  sport*: string                ## "" if unknown
  distanceM*: Option[float]
  geometry*: string             ## GeoJSON text of the route (a LineString or MultiLineString)

proc isoUtc*(t: UnixTime): string =
  ## "2018-08-27T12:00:00Z"
  const fmt = initTimeFormat("yyyy-MM-dd'T'HH:mm:ss'Z'")
  t.toTime.utc.format(fmt)

proc feature*(r: Route): string =
  ## One feature, on one line.  Properties: id, start (UTC, ISO 8601), sport,
  ## distance_m (the last two only if known).
  var props = "\"id\":" & $r.id & ",\"start\":" & escapeJson(isoUtc(r.startT))
  if r.sport.len > 0: props.add ",\"sport\":" & escapeJson(r.sport)
  if r.distanceM.isSome: props.add ",\"distance_m\":" & formatFloat(r.distanceM.get, ffDecimal, 1)
  "{\"type\":\"Feature\",\"properties\":{" & props & "},\"geometry\":" & r.geometry & "}"

proc featureCollection*(routes: seq[Route]): string =
  ## The whole file: valid JSON, a feature to a line.
  var fs: seq[string]
  for r in routes: fs.add feature(r)
  "{\"type\":\"FeatureCollection\",\"features\":[\n" & fs.join(",\n") & "\n]}\n"
