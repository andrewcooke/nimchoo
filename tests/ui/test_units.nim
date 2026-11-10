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
  test "sizes in bytes, kB and MB; the unit follows with no space":
    check humanBytes(1_400_000) == "1.4MB" and humanBytes(85_000) == "85kB" and
      humanBytes(12) == "12B"
  test "not recorded is a dash":
    check notRecorded == "-"
