import std/[strutils, unittest]
import nimchoo/names/outlines as names

proc line(iso, name: string, id: int): string =
  ## A line of countryInfo.txt: 19 columns.
  var cols = newSeq[string](19)
  cols[0] = iso
  cols[4] = name
  cols[16] = $id
  cols.join("\t")

const sample = """{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"geoNameId":"3895114"},"geometry":{"type":"Polygon",
   "coordinates":[[[-76.0,-56.0],[-69.5,-56.0],[-69.5,-17.0],[-76.0,-17.0],[-76.0,-56.0]]]}},
 {"type":"Feature","properties":{"geoNameId":"2510769"},"geometry":{"type":"MultiPolygon",
   "coordinates":[[[[-9.5,37.0],[-6.2,37.0],[-6.2,42.1],[-9.5,42.1],[-9.5,37.0]]],
                  [[[-17.3,32.6],[-16.6,32.6],[-16.6,33.1],[-17.3,33.1],[-17.3,32.6]]]]}},
 {"type":"Feature","properties":{"geoNameId":"1"},"geometry":{"type":"Point","coordinates":[0,0]}},
 {"type":"Feature","properties":{},"geometry":{"type":"Polygon","coordinates":[]}}]}"""

suite "names: the files about countries":
  test "the list of countries: code, name and id; comments and short lines are skipped":
    let text = "# comment\n#ISO\tISO3\n" & line("CL", "Chile", 3895114) & "\n" & line("PT", "Portugal", 2510769) &
               "\nshort\tline\n\n"
    let cs = names.parseCountryInfo(text)
    check cs.len == 2
    check cs[0] == names.CountryInfo(iso: "CL", name: "Chile", geonameId: 3895114)
    check cs[1].iso == "PT" and cs[1].geonameId == 2510769
    check names.parseCountryInfo("").len == 0

  test "an outline is a polygon or several, as well-known text":
    let os = names.parseOutlines(sample)
    check os.len == 2                                # (a point, and a feature with no id, are left out)
    check os[0].geonameId == 3895114
    check os[0].wkt == "MULTIPOLYGON(((-76.00000 -56.00000, -69.50000 -56.00000, -69.50000 -17.00000, " &
                       "-76.00000 -17.00000, -76.00000 -56.00000)))"
    check os[1].geonameId == 2510769
    check os[1].wkt.startsWith("MULTIPOLYGON(((-9.50000 37.00000")
    check os[1].wkt.count(")), ((") == 1             # two polygons
    check os[1].wkt.endsWith("-17.30000 32.60000)))")

  test "something that is not an outline file is refused":
    expect ValueError: discard names.parseOutlines("this is not json")
    expect ValueError: discard names.parseOutlines("{\"type\": \"FeatureCollection\"}")
    expect ValueError: discard names.parseOutlines("[]")

suite "names: a point in an outline":
  test "the polygons are read back from the well-known text":
    let shape = names.parseShape("MULTIPOLYGON(((0.0 0.0, 10.0 0.0, 10.0 10.0, 0.0 10.0, 0.0 0.0), " &
                                 "(4.0 4.0, 6.0 4.0, 6.0 6.0, 4.0 6.0, 4.0 4.0)), " &
                                 "((20.0 0.0, 30.0 0.0, 30.0 5.0, 20.0 0.0)))")
    check shape.len == 2
    check shape[0].len == 2 and shape[0][0].len == 5 and shape[0][1].len == 5     # an outer ring and a hole
    check shape[1].len == 1 and shape[1][0].len == 4
    check names.parseShape("").len == 0 and names.parseShape("nonsense").len == 0
  test "inside, outside, in a hole, in the second polygon":
    let shape = names.parseShape("MULTIPOLYGON(((0 0, 10 0, 10 10, 0 10, 0 0), (4 4, 6 4, 6 6, 4 6, 4 4)), " &
                                 "((20 0, 30 0, 30 5, 20 0)))")
    check shape.contains(1.0, 1.0)
    check shape.contains(9.0, 9.0)
    check not shape.contains(5.0, 5.0)              # the hole
    check not shape.contains(11.0, 5.0)
    check not shape.contains(-1.0, 5.0)
    check shape.contains(28.0, 2.0)                 # the triangle
    check not shape.contains(21.0, 4.0)             # (outside the triangle, inside its box)
  test "an outline a strict library calls invalid still answers: a bow tie, a ring of two points, a touching hole":
    let bowTie = names.parseShape("MULTIPOLYGON(((0 0, 10 10, 10 0, 0 10, 0 0)))")
    check bowTie.contains(5.0, 1.0) or bowTie.contains(1.0, 5.0)     # it does not crash, and counts crossings
    let degenerate = names.parseShape("MULTIPOLYGON(((0 0, 10 0, 10 10, 0 10, 0 0)), ((50 50, 51 51)))")
    check degenerate.contains(5.0, 5.0) and not degenerate.contains(50.5, 50.5)
    let touching = names.parseShape("MULTIPOLYGON(((0 0, 10 0, 10 10, 0 10, 0 0), (0 4, 4 4, 4 6, 0 6, 0 4)))")
    check touching.contains(8.0, 5.0) and not touching.contains(2.0, 5.0)
