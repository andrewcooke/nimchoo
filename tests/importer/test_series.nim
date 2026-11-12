import std/[options, unittest]
import nimchoo/core/errors
import nimchoo/packages/fit/time
import nimchoo/packages/importer/coord
import nimchoo/packages/importer/series

proc rides(n: int): seq[Coord] =
  ## n positions from a simple generator: semicircles anywhere on the Earth, gaps in time, some altitudes.
  var x = 12345'u32
  func next(x: var uint32): uint32 =
    x = x * 1664525'u32 + 1013904223'u32
    x
  var t = 1_000_000'i64
  for i in 0 ..< n:
    t += 1 + int64(next(x) shr 29) # one to eight seconds on
    let lon = int32(cast[int32](next(x)))
    let lat = int32(cast[int32](next(x)))
    let alt =
      if next(x) mod 4 == 0:
        none(float)
      else:
        some(float(int(next(x) mod 60000)) / 5.0 - 500.0)
    result.add Coord(
      t: UnixTime(t),
      lon: float(lon) * semicircleDegrees,
      lat: float(lat) * semicircleDegrees,
      alt: alt,
    )

suite "import: the position arrays":
  test "what is stored comes back exactly: times, positions to the semicircle, altitudes":
    let c = rides(5000)
    check decodePositions(encodePositions(c)) == c

  test "the arrays are 14 bytes a position":
    let p = encodePositions(rides(1000))
    check p.count == 1000
    check p.t.len + p.lon.len + p.lat.len + p.alt.len == 14 * 1000

  test "no positions, and one":
    check decodePositions(encodePositions(newSeq[Coord]())).len == 0
    let one = @[
      Coord(
        t: UnixTime(500),
        lon: float(123456789) * semicircleDegrees,
        lat: float(-398765432) * semicircleDegrees,
        alt: some(2000.0),
      )
    ]
    check decodePositions(encodePositions(one)) == one

  test "no altitude stays none; one beyond what 16 bits hold is stored as none":
    let c = @[
      Coord(t: UnixTime(10), lon: 1.0, lat: 2.0),
      Coord(t: UnixTime(11), lon: 1.0, lat: 2.0, alt: some(-600.0)),
      Coord(t: UnixTime(12), lon: 1.0, lat: 2.0, alt: some(20000.0)),
      Coord(t: UnixTime(13), lon: 1.0, lat: 2.0, alt: some(-500.0)),
    ]
    let d = decodePositions(encodePositions(c))
    check d[0].alt.isNone and d[1].alt.isNone and d[2].alt.isNone
    check d[3].alt == some(-500.0)

  test "the device's speed is not kept":
    let c = @[Coord(t: UnixTime(10), lon: 1.0, lat: 2.0, speed: some(5.0))]
    check decodePositions(encodePositions(c))[0].speed.isNone

  test "arrays of the wrong length are a store error, not garbage":
    var p = encodePositions(rides(10))
    p.lon.setLen(p.lon.len - 1)
    expect StoreError:
      discard decodePositions(p)
