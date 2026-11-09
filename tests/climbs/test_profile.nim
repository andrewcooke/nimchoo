import std/[math, options, unittest]
import nimchoo/climbs/profile
import nimchoo/geo
import nimchoo/fit/time
import nimchoo/importer/extract

const metre = 360.0 / (2.0 * PI * earthRadius)
  # degrees of longitude per metre at the equator

func at(t: int, east: float, alt = none(float)): Coord =
  ## A recorded point `east` metres from the origin, on the equator.
  Coord(t: UnixTime(t), lon: east * metre, lat: 0.0, alt: alt)

proc ride(
    speed: float, seconds: int, alt: proc(east: float): Option[float]
): seq[Coord] =
  for s in 0 .. seconds:
    let east = speed * float(s)
    result.add at(1000 + s, east, alt(east))

suite "climbs: the profile of a stretch of ride":
  test "samples every 5 m along the ground, with position, time and altitude":
    var coords = ride(
      5.0,
      200,
      proc(e: float): Option[float] =
        some(e / 20.0),
    )
    coords.add at(1201, 1002.0, some(1002.0 / 20.0)) # 1002 m, up 50 m
    let p = buildProfile(coords)
    check p.len == 201
    check p.step == 5.0
    check abs(p.elev[100] - 25.0) < 1e-9 and abs(p.elev[180] - 45.0) < 1e-9
      # as recorded: nothing smoothed
    check abs(p.elev[200] - 50.0) < 1e-9
    check abs(p.lon[100] - 500.0 * metre) < 1e-9 and p.lat[100] == 0.0
    check abs(p.t[100] - (1000.0 + 100.0)) < 1e-6 # 500 m at 5 m/s
    check abs(p.t[200] - 1200.0) < 1e-6

  test "points that have not moved are left out; so is a stop in the middle":
    var coords = ride(
      5.0,
      100,
      proc(e: float): Option[float] =
        some(0.0),
    )
    coords.insert(at(1050, 250.0, some(0.0)), 51) # the same place twice
    coords.insert(at(1050, 250.0, some(0.0)), 51)
    let p = buildProfile(coords)
    check p.len == 101 # 500 m: the stop adds nothing

  test "where there is no altitude there is none made up, and a gap inside is bridged":
    let coords = ride(
      5.0,
      200,
      proc(e: float): Option[float] =
        if e < 200.0:
          none(float) # no altitude for the first 200 m
        elif e >= 400.0 and e < 600.0:
          none(float) # ... or between 400 m and 600 m
        else:
          some(e / 10.0),
    )
    let p = buildProfile(coords)
    check p.elev[10].isNaN and p.elev[38].isNaN # before the first altitude
    check not p.elev[60].isNaN and not p.elev[100].isNaN # inside the gap: joined up
    check abs(p.elev[100] - 50.0) < 1.0 # (the same line, joined)

  test "the altitude is used as recorded: a spike stays":
    var coords = ride(
      5.0,
      200,
      proc(e: float): Option[float] =
        some(100.0),
    )
    coords[100].alt = some(150.0) # one point 50 m out
    let p = buildProfile(coords)
    check abs(p.elev[100] - 150.0) < 1e-9 and abs(p.elev[50] - 100.0) < 1e-9

  test "too little to make a profile":
    check buildProfile(newSeq[Coord]()).len == 0
    check buildProfile(@[at(0, 0.0, some(1.0))]).len == 0
    check buildProfile(@[at(0, 0.0, some(1.0)), at(1, 3.0, some(2.0))]).len == 0
      # under one step

  test "the stretches without a gap":
    let n = NaN
    check validRuns(@[1.0, 2.0, 3.0]) == @[0 ..< 3]
    check validRuns(@[n, 1.0, 2.0, n, 5.0, n, 7.0, 8.0, 9.0]) ==
      @[1 ..< 3, 6 ..< 9] # (a single sample is not a stretch)
    check validRuns(newSeq[float]()).len == 0
    check validRuns(@[n, n]).len == 0
