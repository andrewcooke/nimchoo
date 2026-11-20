import std/[os, strutils, unittest]
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
  test "a number without a pointless decimal part":
    check plainNumber(5.0) == "5" and plainNumber(1.25) == "1.25" and
      plainNumber(0.5) == "0.5" and plainNumber(100.0) == "100"

suite "units: counts":
  test "a count has commas from 1,000; counted says what it counts, singular for one":
    check count(1113) == "1,113" and count(7) == "7"
    check counted(1, "activity", "activities") == "1 activity"
    check counted(1113, "activity", "activities") == "1,113 activities"
    check counted(0, "file", "files") == "0 files"

  test "no other code writes commas into a count itself: every count is count() or counted()":
    var found: seq[string]
    let top = currentSourcePath().parentDir.parentDir.parentDir / "src"
    for path in walkDirRec(top):
      if path.endsWith(".nim") and not path.endsWith("ui/units.nim") and
          "insertSep" in readFile(path):
        found.add path.relativePath(top)
    check found.len == 0
    if found.len > 0:
      echo "commas written by hand: ", found.join(", ")
