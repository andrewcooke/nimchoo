import std/[options, unittest]
import nimchoo/selection/ranges

suite "ranges: distances":
  test "always kilometres, a decimal number, no unit":
    check parseDistance("5") == some(5000.0)
    check parseDistance("2.5") == some(2500.0)
    check parseDistance("0.5") == some(500.0)
    check parseDistance("0") == some(0.0)
  test "not a distance":
    for bad in ["", "km", "m", "abc", "-5", "5x", "5 miles", "1e3", ".5", "5.5.5", "5kmm",
                "500m", "5m", "1h", "5km", "5KM", "5 km"]:               # (m is minutes: not a distance)
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
    check parseRange("0.5-2", parseDistance) == some(NumRange(lo: some 500.0, hi: some 2000.0))
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

suite "ranges: around":
  test "tolerances: an amount, or a percentage":
    check parseTol("2", parseDistance) == some(Tol(amount: 2000.0))
    check parseTol("0.5", parseDistance) == some(Tol(amount: 500.0))
    check parseTol("500m", parseDistance).isNone
    check parseTol("15m", parseInterval) == some(Tol(amount: 900.0))
    check parseTol("10%", parseDistance) == some(Tol(amount: 10.0, percent: true))
    check parseTol("2.5%", parseInterval) == some(Tol(amount: 2.5, percent: true))
    check parseTol("0%", parseDistance) == some(Tol(amount: 0.0, percent: true))
    for bad in ["", "%", "x%", "-5%", "1e2%", ".5%", "5%%", "1.2.3%", "x"]:
      check parseTol(bad, parseDistance).isNone
    check parseTol("90", parseInterval).isNone               # (a time needs its unit)
  test "centre ~ tolerance, the centre a value or latest":
    check parseAround("42~2", parseDistance) ==
      some(Around(centre: some 42000.0, tol: Tol(amount: 2000.0)))
    check parseAround("2h~15m", parseInterval) ==
      some(Around(centre: some 7200.0, tol: Tol(amount: 900.0)))
    check parseAround("latest~10%", parseDistance) ==
      some(Around(centre: none float, tol: Tol(amount: 10.0, percent: true)))
    check parseAround("LATEST~5", parseDistance).get.centre.isNone
    check parseAround("0.5~0.05", parseDistance).get.centre == some 500.0
    check parseAround("500m~50m", parseDistance).isNone
  test "not around":
    for bad in ["", "42", "~", "42~", "~2", "42~2~3", "x~2", "latest~", "latest", "42-2"]:
      check parseAround(bad, parseDistance).isNone
  test "the range around a centre: an amount or a percentage of it, not below zero":
    check around(42000.0, Tol(amount: 2000.0)) == NumRange(lo: some 40000.0, hi: some 44000.0)
    check around(40000.0, Tol(amount: 10.0, percent: true)) == NumRange(lo: some 36000.0, hi: some 44000.0)
    check around(1000.0, Tol(amount: 5000.0)).lo == some 0.0
    check around(7200.0, Tol(amount: 0.0)) == NumRange(lo: some 7200.0, hi: some 7200.0)
