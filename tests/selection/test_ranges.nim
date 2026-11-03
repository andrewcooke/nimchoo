import std/[options, unittest]
import nimchoo/selection/ranges

suite "ranges: distances":
  test "kilometres by default, metres with m":
    check parseDistance("5") == some(5000.0)
    check parseDistance("2.5") == some(2500.0)
    check parseDistance("5km") == some(5000.0)
    check parseDistance("5KM") == some(5000.0)
    check parseDistance("500m") == some(500.0)
    check parseDistance("0") == some(0.0)
  test "not a distance":
    for bad in ["", "km", "m", "abc", "-5", "5x", "5 miles", "1e3", ".5", "5.5.5", "5kmm"]:
      check parseDistance(bad).isNone

suite "ranges: intervals":
  test "the notation that is printed":
    check parseInterval("45s") == some(45.0)
    check parseInterval("22m") == some(1320.0)
    check parseInterval("22m05s") == some(1325.0)
    check parseInterval("4h41m") == some(16860.0)
    check parseInterval("1h") == some(3600.0)
    check parseInterval("2d03h07m") == some(2.0 * 86400 + 3 * 3600 + 7 * 60)
    check parseInterval("0s") == some(0.0)
    check parseInterval("34h") == some(122400.0)         # (more than a day of hours is fine)
    check parseInterval("1H30M") == some(5400.0)
  test "not an interval":
    for bad in ["", "90", "1h30", "h", "1x", "30m1h", "1h1h", "1.5h", "-1h", "1h 30m", "99999999999s"]:
      check parseInterval(bad).isNone

suite "ranges: a-b, a-, -b":
  test "both ends, inclusive":
    check parseRange("10-50", parseDistance) == some(NumRange(lo: some 10000.0, hi: some 50000.0))
    check parseRange("5-5", parseDistance) == some(NumRange(lo: some 5000.0, hi: some 5000.0))
  test "either end open":
    check parseRange("40-", parseDistance) == some(NumRange(lo: some 40000.0))
    check parseRange("-5", parseDistance) == some(NumRange(hi: some 5000.0))
    check parseRange("1h-", parseInterval) == some(NumRange(lo: some 3600.0))
    check parseRange("-45m", parseInterval) == some(NumRange(hi: some 2700.0))
    check parseRange("1h30m-4h", parseInterval) == some(NumRange(lo: some 5400.0, hi: some 14400.0))
    check parseRange("500m-2km", parseDistance) == some(NumRange(lo: some 500.0, hi: some 2000.0))
  test "no range":
    for bad in ["", "-", "5", "1-2-3", "--5", "5--", "a-b", "10-x", "x-10"]:
      check parseRange(bad, parseDistance).isNone
    check parseRange("90-", parseInterval).isNone            # (a time needs its unit)
  test "backwards":
    check parseRange("50-10", parseDistance).isNone
    check isBackwards("50-10", parseDistance)
    check isBackwards("2h-1h", parseInterval)
    check not isBackwards("10-50", parseDistance)
    check not isBackwards("-5", parseDistance)
    check not isBackwards("x-1", parseDistance)
  test "open is open":
    check NumRange().isOpen
    check not NumRange(lo: some 1.0).isOpen
