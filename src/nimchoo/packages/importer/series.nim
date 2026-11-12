## The positions of an activity as arrays, for storage: one blob for each of the times, the longitudes, the latitudes and the
## altitudes, so that a ride is one row and not a row for each second.
##
## A position is stored as the file wrote it: a FIT semicircle (a signed 32-bit integer, about 1 cm), which turns into the
## floating-point degrees of `Coord` and back without loss.  The time of each position is its offset in seconds from the
## first (a second without a position has no entry, so the cleaning's gaps need nothing more).  An altitude is stored as the
## file's unit, 0.2 m from -500 m, in 16 bits; 0xFFFF is the encoded form of "no altitude" (an `Option` outside), and an
## altitude beyond what 16 bits hold (-500 to 12,607 m) is not a height on Earth and is stored as none.  The device's speed
## is not stored here (a package of its own, TODO.md).  About 14 bytes a position, against about 40 as a row.
## All arrays are little-endian.  Pure.

import std/[math, options]
import ../../core/errors
import ../fit/time
import ./coord

{.push raises: [].}

type Positions* = object
  t0*: UnixTime ## the time of the first position (the offsets are from it)
  count*: int
  t*, lon*, lat*, alt*: string ## binary: `count` entries of 4, 4, 4 and 2 bytes

const
  noAlt = 0xFFFF
  altOffsetM = 500.0
  altPerM = 5.0

func put32*(s: var string, at: int, v: int32) =
  let u = cast[uint32](v)
  for k in 0 .. 3:
    s[at + k] = char((u shr (8 * k)) and 0xFF)

func get32*(s: string, at: int): int32 =
  var u = 0'u32
  for k in 0 .. 3:
    u = u or (uint32(ord(s[at + k])) shl (8 * k))
  cast[int32](u)

func put16*(s: var string, at: int, v: uint16) =
  s[at] = char(v and 0xFF)
  s[at + 1] = char(v shr 8)

func get16*(s: string, at: int): uint16 =
  uint16(ord(s[at])) or (uint16(ord(s[at + 1])) shl 8)

func semicircles(degrees: float): int32 =
  ## The file's integer for a position that came from one.
  let n = round(degrees / semicircleDegrees)
  doAssert n >= -2147483648.0 and n <= 2147483647.0,
    "a position outside the Earth reached the arrays"
  int32(n)

func encodePositions*(coords: seq[Coord]): Positions =
  ## `coords` in time order, one per second at most.
  result.count = coords.len
  if coords.len == 0:
    return
  result.t0 = coords[0].t
  result.t = newString(4 * coords.len)
  result.lon = newString(4 * coords.len)
  result.lat = newString(4 * coords.len)
  result.alt = newString(2 * coords.len)
  for i, c in coords:
    doAssert c.t >= result.t0 and int64(c.t) - int64(result.t0) <= int64(high(int32)),
      "positions are in time order, within 68 years"
    put32(result.t, 4 * i, int32(int64(c.t) - int64(result.t0)))
    put32(result.lon, 4 * i, semicircles(c.lon))
    put32(result.lat, 4 * i, semicircles(c.lat))
    var code = noAlt
    if c.alt.isSome:
      let units = round((c.alt.get + altOffsetM) * altPerM)
      if units >= 0.0 and units < float(noAlt):
        code = int(units)
    put16(result.alt, 2 * i, uint16(code))

func decodePositions*(p: Positions): seq[Coord] {.raises: [StoreError].} =
  ## The positions back, as `Coord`s without a speed.  A StoreError if the arrays are not the lengths the count says.
  if p.t.len != 4 * p.count or p.lon.len != 4 * p.count or p.lat.len != 4 * p.count or
      p.alt.len != 2 * p.count:
    raiseStore("the position arrays of an activity are not the length their count says")
  result = newSeq[Coord](p.count)
  for i in 0 ..< p.count:
    let code = int(get16(p.alt, 2 * i))
    result[i] = Coord(
      t: UnixTime(int64(p.t0) + int64(get32(p.t, 4 * i))),
      lon: float(get32(p.lon, 4 * i)) * semicircleDegrees,
      lat: float(get32(p.lat, 4 * i)) * semicircleDegrees,
      alt:
        if code == noAlt:
          none(float)
        else:
          some(float(code) / altPerM - altOffsetM),
    )
