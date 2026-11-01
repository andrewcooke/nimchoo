## The route of an activity as well-known text (WKT), for SpatiaLite: a
## MULTILINESTRING with one part for each timer segment, in time order.  Pure:
## the importer hands the text to the database.

import std/[options, strutils]
import ./extract

{.push raises: [].}

func point(c: Coord): string =
  ## "lon lat", to 7 decimals (about a centimetre).
  formatFloat(c.lon, ffDecimal, 7) & " " & formatFloat(c.lat, ffDecimal, 7)

func routeWkt*(a: ActivityData): Option[string] =
  ## The WKT of the route, or none if no segment has two points (a line needs two).
  ## Each coordinate is in the segment whose interval holds its time (extract.nim
  ## makes sure there is exactly one).
  var parts: seq[string]
  var k = 0                      # coords are in time order, segments too
  for g in a.segments:
    var pts: seq[string]
    while k < a.coords.len and a.coords[k].t <= g.endT:
      if a.coords[k].t >= g.startT: pts.add point(a.coords[k])
      inc k
    if pts.len >= 2: parts.add "(" & pts.join(", ") & ")"
  if parts.len == 0: none(string)
  else: some("MULTILINESTRING(" & parts.join(", ") & ")")
