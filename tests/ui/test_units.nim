import std/unittest
import nimchoo/packages/ui/units

suite "units: a number and its unit":
  test "distances in km, one decimal, commas from 1,000; the unit follows with no space":
    check kmNumber(0.0) == "0.0"
    check kmNumber(102650.0) == "102.7"
    check kmNumber(1234567.0) == "1,234.6"
    check km(0.0) == "0.0km"
    check km(5549.0) == "5.5km"
    check km(99950.0) == "100.0km"
    check km(1234567.0) == "1,234.6km"
  test "not recorded is a dash":
    check notRecorded == "-"
