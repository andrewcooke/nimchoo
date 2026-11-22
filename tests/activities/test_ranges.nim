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

suite "ranges: a unit is given once":
  test "a side with no unit takes the single unit of the other":
    for same in ["42~2km", "42km~2", "42km~2000m"]:
      check parseAround(sharedUnit(same), metresEnd) ==
        some(Around(centre: some 42000.0, tol: Tol(amount: 2000.0)))
    check parseAround(sharedUnit("42~2000m"), metresEnd).get.centre == some 42.0
    for same in ["10-50km", "10km-50", "10km-50km"]:
      check parseRange(sharedUnit(same), metresEnd) ==
        some(NumRange(lo: some 10000.0, hi: some 50000.0))
    check parseRange(sharedUnit("40km-"), metresEnd) == some(NumRange(lo: some 40000.0))
    check parseRange(sharedUnit("-5km"), metresEnd) == some(NumRange(hi: some 5000.0))
    check parseRange(sharedUnit("30-90m"), secondsEnd) ==
      some(NumRange(lo: some 1800.0, hi: some 5400.0))
    check parseAround(sharedUnit("2~15m"), secondsEnd).get.centre == some 120.0
  test "a compound unit, a percentage or a word is not shared":
    check sharedUnit("2h30m-3") == "2h30m-3"
    check sharedUnit("latest~10%") == "latest~10%"
    check sharedUnit("5-10%") == "5-10%"
    check parseRange(sharedUnit("2h30m-3"), secondsEnd).isNone
  test "with no unit anywhere the default is added to the first number":
    check addDefaultUnit("40-", "km") == some("40km-")
    check addDefaultUnit("-5", "km") == some("-5km")
    check addDefaultUnit("10-50", "km") == some("10km-50")
    check addDefaultUnit("42~2", "km") == some("42km~2")
    check addDefaultUnit("latest~5", "km") == some("latest~5km")
    check addDefaultUnit("90-", "h") == some("90h-")
    check parseRange(sharedUnit(addDefaultUnit("10-50", "km").get), metresEnd) ==
      some(NumRange(lo: some 10000.0, hi: some 50000.0))
  test "no default when a unit is there, or there is no number":
    for done in [
      "40km-", "10-50km", "42~2km", "latest~10%", "latest", "-", "~", "5", "x-y",
      "1-2-3",
    ]:
      check addDefaultUnit(done, "km").isNone

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
