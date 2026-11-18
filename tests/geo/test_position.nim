import std/[options, unittest]
import nimchoo/packages/geo/position

suite "geo: a position as the user writes it":
  test "latitude first, then longitude, into named fields":
    let p = parsePosition("38.72,-9.14").get
    check p.lat == 38.72 and p.lon == -9.14
    check parsePosition(" -33.344 , -70.364 ").get == (lon: -70.364, lat: -33.344)
  test "out of range, or not a pair, is none":
    for bad in ["", "1", "1,2,3", "91,0", "0,181", "a,b", "38.72;-9.14"]:
      check parsePosition(bad).isNone
