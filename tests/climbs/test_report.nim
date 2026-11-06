import std/[strutils, unicode, unittest]
import nimchoo/climbs/[report, work]
import nimchoo/db/store
import nimchoo/ui/units
import nimchoo/ui/style
import ../support/[climbdata, userdata]

suite "climbs report: the words":
  test "a time, to the second":
    check duration(552.4) == "9:12"
    check duration(59.6) == "1:00"
    check duration(0) == "0:00"
    check duration(3723) == "1:02:03"
    check duration(7751.0) == "2:09:11"
  test "kilometres to a tenth, the unit attached":
    check km(14520) == "14.5km"
    check km(1949) == "1.9km"
    check km(50) == "0.1km"

suite "climbs report: the display while they are worked out":
  test "two lines like the import's: plain, then the counts in green joined by grey dots":
    let lines = climbingLines(120, 1986, Worked(activities: 120, sectors: 12, efforts: 40))
    check lines.len == 2
    check lines[0].text == "climbing 120 / 1,986 activities"
    check lines[0][0].look.bold and lines[0][0].look.colour == white and lines[0][1].look.colour == white
    check lines[1].text == "climbs 12 · efforts 40"
    check lines[1][0].look.colour == green and lines[1][2].look.colour == green
    check lines[1][1].text == " · " and lines[1][1].look.colour == grey
  test "the line after the display, as the import has one":
    check doneLine(Worked(activities: 1650, sectors: 138, efforts: 2661)) ==
      "done: 1,650 activities: 138 new climbs, 2,661 efforts"
    check doneLine(Worked(activities: 1, sectors: 1, efforts: 1)) ==
      "done: 1 activity: 1 new climb, 1 effort"

suite "climbs report: the lines":
  test "the sectors, with headings: only the climbs, how often ridden, and the mark of a name given by hand":
    let lines = sectorLines(@[
      SectorRow(id: 20, lengthM: 14900, gainM: 1109, gradient: 7.4, category: "HC", efforts: 1, name: "unnamed", manual: true),
      SectorRow(id: 3, lengthM: 4900, gainM: 245, gradient: 5.0, category: "3", efforts: 0, name: "unnamed")])
    check lines[0].startsWith("climb") and "length" in lines[0] and "efforts" in lines[0] and "best" notin lines[0]
    check lines[1].contains("HC   14.9km  +1109m      7.4%") and lines[2].contains("3     4.9km   +245m      5.0%")
    check lines[1].endsWith("manual") and lines[2].endsWith("0")
    let named = sectorLines(@[SectorRow(id: 20, lengthM: 14900, gainM: 1109, gradient: 7.4, category: "HC",
                                        name: "near Farellones (1/2)", efforts: 1)])
    check named[1].startsWith("near Farellones (1/2)")
  test "the name leads a line, lined up by characters, and a long one is cut":
    check cut("short") == "short"
    check cut("x".repeat(40)) == "x".repeat(27) & "..."
    check cut("é".repeat(31)).runeLen == 30
    check cut("near San Carlos de Apoquindo (1/3)") == "near San Carlos de Ap... (1/3)"
    check cut("near San Carlos de Apoquindo (1/3)").runeLen == 30

suite "climbs report: from the tables":
  test "the sectors: how often each was ridden, by anyone":
    let s = fresh("sectors")
    defer: s.close()
    addUser(s.path, "bob")
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "bob", "two", 2_000_000, 6.0, eastbound(6.0))
    discard ensureClimbs(s)
    let rows = allSectors(s)
    check rows.len == 1 and rows[0].efforts == 2
