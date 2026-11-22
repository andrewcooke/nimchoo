import std/[options, unittest]
import nimchoo/packages/activities/ranges

suite "ranges: the ends are read by the shared readers":
  test "a distance end has its unit, in metres":
    check metresEnd("5km") == some(5000.0)
    check metresEnd("500m") == some(500.0)
    check metresEnd("0.5km") == some(500.0)
    for bad in ["", "5", "km", "m", "abc", "-5km", "1h", "5KM", "5 km", "0km"]:
      check metresEnd(bad).isNone
  test "a time end is the notation that is printed, in seconds":
    check secondsEnd("45s") == some(45.0)
    check secondsEnd("22m05s") == some(1325.0)
    check secondsEnd("4h41m") == some(16860.0)
    check secondsEnd("2d03h07m") == some(2.0 * 86400 + 3 * 3600 + 7 * 60)
    check secondsEnd("34h") == some(122400.0)
    for bad in ["", "90", "1h30", "h", "1x", "30m1h", "1h1h", "-1h", "1h 30m", "0s"]:
      check secondsEnd(bad).isNone

suite "ranges: units that are left out are filled in (and the program asks)":
  const km = distanceUnitsBelow
  const t = timeUnitsBelow
  test "a range with every unit written needs nothing":
    for done in ["42km~200m", "10km-50km", "40km-", "-5km", "latest~10%", "latest~5km"]:
      check fillUnits(done, "km", km).isNone
    check fillUnits("2h~15m", "h", t).isNone
  test "a spread takes the centre's unit, or the one below it if its number is larger":
    check fillUnits("42km~2", "km", km) == some("42km~2km")
    check fillUnits("42km~42", "km", km) == some("42km~42km")
    check fillUnits("42km~200", "km", km) == some("42km~200m")
    check fillUnits("500m~50", "km", km) == some("500m~50m")
    check fillUnits("500m~900", "km", km) == some("500m~900m") # (nothing below metres)
    check fillUnits("2h~1", "h", t) == some("2h~1h")
    check fillUnits("2h~15", "h", t) == some("2h~15m")
    check fillUnits("2d~5", "h", t) == some("2d~5h")
    check fillUnits("2m~30", "h", t) == some("2m~30s")
    check fillUnits("30s~90", "h", t) == some("30s~90s")
  test "a centre with no unit takes the spread's; with neither the default is on both":
    check fillUnits("42~2km", "km", km) == some("42km~2km")
    check fillUnits("2~15m", "h", t) == some("2m~15m")
    check fillUnits("40~2", "km", km) == some("40km~2km")
    check fillUnits("2~1", "h", t) == some("2h~1h")
  test "latest and previous have a spread alone, with the default":
    check fillUnits("latest~5", "km", km) == some("latest~5km")
    check fillUnits("previous~15", "h", t) == some("previous~15h")
  test "a-b: a side takes the other's unit; neither, the default; open, the default":
    check fillUnits("10-50km", "km", km) == some("10km-50km")
    check fillUnits("10km-50", "km", km) == some("10km-50km")
    check fillUnits("10-50", "km", km) == some("10km-50km")
    check fillUnits("30-90m", "h", t) == some("30m-90m")
    check fillUnits("40-", "km", km) == some("40km-")
    check fillUnits("-5", "km", km) == some("-5km")
    check fillUnits("90-", "h", t) == some("90h-")
  test "what is filled in is a range the readers take":
    check parseRange(fillUnits("10-50", "km", km).get, metresEnd) ==
      some(NumRange(lo: some 10000.0, hi: some 50000.0))
    check parseAround(fillUnits("42km~200", "km", km).get, metresEnd) ==
      some(Around(centre: some 42000.0, tol: Tol(amount: 200.0)))
  test "a compound unit is not borrowed, and nothing else is changed":
    check fillUnits("2h30m~15", "h", t).isNone
    check fillUnits("2h30m-3", "h", t).isNone
    for other in ["5", "", "-", "latest", "1-2-3", "x-y"]:
      check fillUnits(other, "km", km).isNone

suite "ranges: a-b, a-, -b":
  test "both ends, inclusive":
    check parseRange("10km-50km", metresEnd) ==
      some(NumRange(lo: some 10000.0, hi: some 50000.0))
    check parseRange("5km-5km", metresEnd) ==
      some(NumRange(lo: some 5000.0, hi: some 5000.0))
  test "either end open":
    check parseRange("40km-", metresEnd) == some(NumRange(lo: some 40000.0))
    check parseRange("-5km", metresEnd) == some(NumRange(hi: some 5000.0))
    check parseRange("1h-", secondsEnd) == some(NumRange(lo: some 3600.0))
    check parseRange("-45m", secondsEnd) == some(NumRange(hi: some 2700.0))
    check parseRange("1h30m-4h", secondsEnd) ==
      some(NumRange(lo: some 5400.0, hi: some 14400.0))
    check parseRange("0.5km-2km", metresEnd) ==
      some(NumRange(lo: some 500.0, hi: some 2000.0))
  test "no range":
    for bad in [
      "", "-", "5km", "1km-2km-3km", "--5km", "5km--", "a-b", "10km-x", "x-10km",
      "10-50",
    ]:
      check parseRange(bad, metresEnd).isNone
    check parseRange("90-", secondsEnd).isNone # (a time needs its unit)
  test "backwards":
    check parseRange("50km-10km", metresEnd).isNone
    check isBackwards("50km-10km", metresEnd)
    check isBackwards("2h-1h", secondsEnd)
    check not isBackwards("10km-50km", metresEnd)
    check not isBackwards("-5km", metresEnd)
    check not isBackwards("x-1km", metresEnd)
  test "open is open":
    check NumRange().isOpen
    check not NumRange(lo: some 1.0).isOpen

suite "ranges: around":
  test "tolerances: an amount, or a percentage":
    check parseTol("2km", metresEnd) == some(Tol(amount: 2000.0))
    check parseTol("0.5km", metresEnd) == some(Tol(amount: 500.0))
    check parseTol("500m", metresEnd) == some(Tol(amount: 500.0))
    check parseTol("2", metresEnd).isNone # (a unit is needed)
    check parseTol("15m", secondsEnd) == some(Tol(amount: 900.0))
    check parseTol("10%", metresEnd) == some(Tol(amount: 10.0, percent: true))
    check parseTol("2.5%", secondsEnd) == some(Tol(amount: 2.5, percent: true))
    check parseTol("0%", metresEnd) == some(Tol(amount: 0.0, percent: true))
    for bad in ["", "%", "x%", "-5%", "1e2%", ".5%", "5%%", "1.2.3%", "x"]:
      check parseTol(bad, metresEnd).isNone
    check parseTol("90", secondsEnd).isNone # (a time needs its unit)
  test "centre ~ tolerance, the centre a value or latest":
    check parseAround("42km~2km", metresEnd) ==
      some(Around(centre: some 42000.0, tol: Tol(amount: 2000.0)))
    check parseAround("2h~15m", secondsEnd) ==
      some(Around(centre: some 7200.0, tol: Tol(amount: 900.0)))
    check parseAround("latest~10%", metresEnd) ==
      some(
        Around(
          centre: none float, refers: refLatest, tol: Tol(amount: 10.0, percent: true)
        )
      )
    check parseAround("LATEST~5km", metresEnd).get.centre.isNone
    check parseAround("previous~5km", metresEnd).get.refers == refPrevious
    check parseAround("Previous~10%", secondsEnd).get.tol.percent
      # (a percentage needs no unit)
    check parseAround("Previous~10", secondsEnd).isNone # (an amount of time does)
    check parseAround("42km~2km", metresEnd).get.refers == refNone
    check parseAround("0.5km~0.05km", metresEnd).get.centre == some 500.0
    check parseAround("500m~50m", metresEnd).isSome
  test "not around":
    for bad in [
      "", "42", "~", "42~", "~2", "42~2~3", "x~2", "latest~", "latest", "42-2"
    ]:
      check parseAround(bad, metresEnd).isNone
  test "the words for a reference":
    check parseReference("latest") == refLatest
    check parseReference("PREVIOUS") == refPrevious
    for other in ["", "last", "prev", "latest ", "none"]:
      check parseReference(other) == refNone
  test "the range around a centre: an amount or a percentage of it, not below zero":
    check around(42000.0, Tol(amount: 2000.0)) ==
      NumRange(lo: some 40000.0, hi: some 44000.0)
    check around(40000.0, Tol(amount: 10.0, percent: true)) ==
      NumRange(lo: some 36000.0, hi: some 44000.0)
    check around(1000.0, Tol(amount: 5000.0)).lo == some 0.0
    check around(7200.0, Tol(amount: 0.0)) == NumRange(lo: some 7200.0, hi: some 7200.0)
