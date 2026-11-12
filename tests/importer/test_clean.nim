import std/[algorithm, options, sequtils, unittest]
import nimchoo/packages/fit/time
import nimchoo/packages/geo/geo
import nimchoo/packages/importer/clean
import nimchoo/packages/importer/extract
import ../support/paths

const t0 = 1_000_000

proc at(t: int, x, y: float): Coord =
  let (lon, lat) = pr.unproject(XY(x: x, y: y))
  Coord(t: UnixTime(t), lon: lon, lat: lat)

proc ride(n: int, mps = 8.0): seq[Coord] =
  ## n seconds due east at `mps`, a little wavy so that no two positions are alike.
  for i in 0 ..< n:
    result.add at(t0 + i, float(i) * mps, 2.0 * float(i mod 3))

proc times(ds: seq[Dropped]): seq[int] =
  ds.mapIt(int(it.t) - t0).sorted

proc without(c: seq[Coord], idx: openArray[int]): seq[Coord] =
  for i, p in c:
    if i notin idx:
      result.add p

suite "import: cleaning the positions":
  test "a clean ride is left as it is":
    let c = ride(120)
    let r = cleanCoords(c)
    check r.kept == c and r.dropped.len == 0 and r.splits.len == 0

  test "stale positions (the last fix written again while moving) are dropped, the first of a run kept":
    var c = ride(120)
    for i in [10, 40, 41, 80]: # a single one, a run of two, another
      c[i].lon = c[i - 1].lon
      c[i].lat = c[i - 1].lat
    let r = cleanCoords(c)
    check r.dropped.times == @[10, 40, 41, 80]
    check r.dropped.allIt(it.fault == fStale)
    check r.kept == c.without([10, 40, 41, 80]) and r.splits.len == 0

  test "an identical position while standing still is kept":
    var c = ride(60)
    for i in 0 ..< c.len: # slows to a stop at 160 m, waits 20 s, and goes on
      let x =
        if i < 20:
          float(i) * 8.0
        elif i <= 40:
          160.0
        else:
          160.0 + float(i - 40) * 8.0
      c[i] = at(t0 + i, x, 0.0)
    c[19] = at(t0 + 19, 159.0, 0.0)
    c[41] = at(t0 + 41, 161.0, 0.0)
    let r = cleanCoords(c)
    check r.dropped.len == 0 and r.kept.len == c.len

  test "a spike (out and back) is dropped":
    var c = ride(120)
    c[50] = at(t0 + 50, 400.0, 300.0)
    let r = cleanCoords(c)
    check r.dropped.times == @[50] and r.dropped[0].fault == fSpike
    check r.kept == c.without([50])

  test "a burst of 15 wrong positions in a row is dropped":
    var c = ride(120)
    for i in 40 ..< 55:
      c[i] = at(t0 + i, float(i) * 8.0 + 300.0, 280.0)
    let r = cleanCoords(c)
    check r.dropped.times == toSeq(40 ..< 55)
    check r.kept.len == 105 and r.splits.len == 0

  test "a poor first fix: the positions before a jump in the first seconds are dropped":
    var c = ride(120)
    for i in 0 ..< 6:
      c[i] = at(t0 + i, float(i) * 8.0 - 450.0, 100.0)
    let r = cleanCoords(c)
    check r.dropped.times == toSeq(0 ..< 6)
    check r.dropped.allIt(it.fault == fFirstFix)
    check r.kept == c[6 ..^ 1] and r.splits.len == 0

  test "a jump that does not return splits the stretch, and drops nothing":
    var c = ride(200)
    for i in 100 ..< 200:
      c[i].lat += 0.005 # about 550 m north, and stays there
    let r = cleanCoords(c)
    check r.splits == @[UnixTime(t0 + 100)]
    check r.dropped.len == 0 and r.kept.len == 200

  test "a jump of 60 m that does not return is a correction: no split (a few positions may go while it settles)":
    var c = ride(200)
    for i in 100 ..< 200:
      c[i].lat += 60.0 / 111_195.0
    let r = cleanCoords(c)
    check r.splits.len == 0 and r.dropped.len <= 5 and r.kept.len >= 195

  test "a long gap with a speed of zero at the end is not a fault":
    var c = ride(100)
    c.delete(40 ..< 90) # 50 s without positions: 400 m
    c[40].speed = some(0.0) # the rider has just stopped
    let r = cleanCoords(c)
    check r.dropped.len == 0 and r.splits.len == 0

  test "a sideways jump of 25 m, a wobble, is left alone":
    var c = ride(120)
    c[60] = at(t0 + 60, 60.0 * 8.0, 27.0)
    c[61] = at(t0 + 61, 61.0 * 8.0, 27.0)
    check cleanCoords(c).dropped.len == 0

  test "the device's speed tightens the test: 60 m off while the device says 2 m/s is a fault":
    var c = ride(120, 2.0)
    for i in 0 ..< c.len:
      c[i].speed = some(2.0)
    c[50].lon += 60.0 / 111_195.0 * 3.0 # 180 m east in one second
    check cleanCoords(c).dropped.times == @[50]

  test "the removals do not change over a wide range of the constants":
    var c = ride(300)
    c[50] = at(t0 + 50, 400.0, 400.0)
    for i in 100 ..< 112:
      c[i] = at(t0 + i, float(i) * 8.0 - 300.0, 350.0)
    for i in [150, 200, 201]:
      c[i].lon = c[i - 1].lon
      c[i].lat = c[i - 1].lat
    for i in 0 ..< 4:
      c[i] = at(t0 + i, float(i) * 8.0 - 500.0, 0.0)
    let base = cleanCoords(c)
    check base.dropped.len == 4 + 1 + 12 + 3
    for leeway in [15.0, 20.0, 45.0, 60.0, 100.0]:
      for fastest in [20.0, 30.0, 40.0]:
        for moving in [1.0, 5.0]:
          var tune = tuning()
          tune.leewayM = leeway
          tune.fastestMps = fastest
          tune.movingStepM = moving
          let r = cleanCoords(c, tune)
          check r.dropped.times == base.dropped.times and r.splits == base.splits

  test "few positions are returned as they are":
    check cleanCoords(newSeq[Coord]()).kept.len == 0
    check cleanCoords(ride(2)).kept.len == 2
