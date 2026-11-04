## The route of an activity as well-known binary (WKB, the OGC standard form), for SpatiaLite: a
## MULTILINESTRING with one part for each timer segment, in time order.  Pure: the importer hands
## the bytes to the database (`GeomFromWKB`).
##
## (Binary, not text: SpatiaLite takes 20 ms to read the routes of 166 activities in this form and
## 1.9 s to read them as text.)

import std/options
import ./extract
import ../fit/time

{.push raises: [].}

const
  littleEndianFlag = 1'u8
  lineString = 2'u32
  multiLineString = 5'u32

func put32(buf: var string, pos: var int, v: uint32) =
  for i in 0 ..< 4: buf[pos + i] = char((v shr (8 * i)) and 0xff)
  pos += 4

func put64(buf: var string, pos: var int, x: float) =
  let v = cast[uint64](x)
  for i in 0 ..< 8: buf[pos + i] = char((v shr (8 * i)) and 0xff)
  pos += 8

func routeWkb*(a: ActivityData): Option[string] =
  ## The WKB of the route (as bytes in a string), or none if no segment has two points (a line
  ## needs two).  Each coordinate is in the segment whose interval holds its time (extract.nim
  ## makes sure there is exactly one).  Points are longitude, latitude.
  var parts: seq[(int, int)]       # (index of the first coordinate, how many) of each segment
  var k = 0                        # coords are in time order, segments too
  for g in a.segments:
    var first = -1
    var n = 0
    while k < a.coords.len and a.coords[k].t <= g.endT:
      if a.coords[k].t >= g.startT:
        if first < 0: first = k
        inc n
      inc k
    if n >= 2: parts.add (first, n)
  if parts.len == 0: return none(string)
  var size = 1 + 4 + 4
  for (_, n) in parts: size += 1 + 4 + 4 + 16 * n
  var buf = newString(size)
  var pos = 0
  buf[pos] = char(littleEndianFlag)
  inc pos
  put32(buf, pos, multiLineString)
  put32(buf, pos, uint32(parts.len))
  for (first, n) in parts:
    buf[pos] = char(littleEndianFlag)
    inc pos
    put32(buf, pos, lineString)
    put32(buf, pos, uint32(n))
    for i in first ..< first + n:
      put64(buf, pos, a.coords[i].lon)
      put64(buf, pos, a.coords[i].lat)
  some(buf)
