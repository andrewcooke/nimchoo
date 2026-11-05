import std/[math, options, unittest]
import nimchoo/climbs/[detect, match, profile]
import nimchoo/geo
import nimchoo/fit/time
import nimchoo/importer/extract

const metre = 360.0 / (2.0 * PI * earthRadius)

proc rideAt(speed: float, t0: int): seq[Coord] =
  ## A ride east along the equator at a steady speed, a point a second: 1 km flat, 3 km up at 4 %
  ## (120 m), 2 km flat.
  let seconds = int(6000.0 / speed)
  for s in 0 .. seconds:
    let x = speed * float(s)
    let alt =
      if x < 1000.0: 100.0
      elif x < 4000.0: 100.0 + (x - 1000.0) * 0.04
      else: 220.0
    result.add Coord(t: UnixTime(t0 + s), lon: x * metre, lat: 0.0, alt: some(alt))

func asPath(coords: openArray[Coord]): Path =
  for c in coords:
    result.lon.add c.lon
    result.lat.add c.lat
    result.t.add float(int64(c.t))
    result.elev.add (if c.alt.isSome: c.alt.get else: NaN)

func climbPath(p: Profile, c: Climb): Path =
  for i in c.first .. c.last:
    result.lon.add p.lon[i]
    result.lat.add p.lat[i]

suite "climbs: from a ride to a stored climb and back":
  test "found in one ride, a sector, matched in another ride at another speed":
    let first = rideAt(5.0, 1_000_000)
    let p = buildProfile(first)
    let cs = findClimbs(p)
    check cs.len == 1
    check abs(cs[0].gain - 119.0) < 3.0 and abs(cs[0].gradient - 4.0) < 0.2
    check cs[0].category == "4"
    let sector = climbPath(p, cs[0])
    check sector.len > 250                                        # about 3 km every 10 m
    # the same ride finds the climb at the right times
    let es = overPaths(sector, asPath(first))
    check es.len == 1
    check abs(es[0].elapsed - cs[0].length / 5.0) < 3.0           # the climb's length at 5 m/s
    # a slower ride later
    let second = rideAt(4.0, 2_000_000)
    let es2 = overPaths(sector, asPath(second))
    check es2.len == 1
    check abs(es2[0].elapsed - cs[0].length / 4.0) < 3.0
    check es2[0].startT > 2_000_000.0
    check abs(es2[0].finishElev - es2[0].startElev - 119.0) < 4.0
    # and the climb found again in the second ride is the stored one
    let again = findClimbs(buildProfile(second))
    check again.len == 1
    check isRepeat(sector, climbPath(buildProfile(second), again[0]))

  test "a flat ride finds nothing, and matches nothing":
    var flat: seq[Coord]
    for s in 0 .. 1000:
      flat.add Coord(t: UnixTime(s), lon: 5.0 * float(s) * metre, lat: 0.0, alt: some(50.0))
    check findClimbs(buildProfile(flat)).len == 0
