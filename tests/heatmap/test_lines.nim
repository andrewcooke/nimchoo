import std/[json, options, strutils, unittest]
import nimchoo/fit/time
import nimchoo/heatmap/lines
import nimchoo/ids

const line = """{"type":"LineString","coordinates":[[1,2],[3,4]]}"""

suite "heatmap: GeoJSON":
  test "a feature has the properties and the geometry":
    let f = parseJson(feature(Route(id: ActivityId(7), startT: UnixTime(1535371200), sport: "cycling",
                                    distanceM: some 11978.11, geometry: line)))
    check f["type"].getStr == "Feature"
    check f["properties"]["id"].getInt == 7
    check f["properties"]["start"].getStr == "2018-08-27T12:00:00Z"
    check f["properties"]["sport"].getStr == "cycling"
    check f["properties"]["distance_m"].getFloat == 11978.1
    check f["geometry"]["coordinates"].len == 2
  test "what is not known is left out":
    let f = parseJson(feature(Route(id: ActivityId(1), startT: UnixTime(0), geometry: line)))
    check not f["properties"].hasKey("sport")
    check not f["properties"].hasKey("distance_m")
    check f["properties"]["start"].getStr == "1970-01-01T00:00:00Z"
  test "text is escaped":
    let f = parseJson(feature(Route(id: ActivityId(1), startT: UnixTime(0), sport: "a\"b\\c\n", geometry: line)))
    check f["properties"]["sport"].getStr == "a\"b\\c\n"
  test "a collection is valid JSON with a feature for each route, a line each":
    let text = featureCollection(@[Route(id: ActivityId(1), startT: UnixTime(0), geometry: line),
                                   Route(id: ActivityId(2), startT: UnixTime(5), geometry: line)])
    let j = parseJson(text)
    check j["type"].getStr == "FeatureCollection"
    check j["features"].len == 2
    check j["features"][1]["properties"]["id"].getInt == 2
    check text.countLines == 5                    # { , feature, feature, ]} (and the end)
  test "no routes: still valid":
    check parseJson(featureCollection(@[]))["features"].len == 0
