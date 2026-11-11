import std/[json, options, strutils, unittest]
import nimchoo/packages/fit/time
import nimchoo/packages/map/lines
import nimchoo/core/ids

const line = """{"type":"LineString","coordinates":[[1,2],[3,4]]}"""

suite "map: GeoJSON":
  test "a feature has the properties and the geometry":
    let f = parseJson(
      feature(
        Route(
          id: ActivityId(7),
          startT: UnixTime(1535371200),
          sport: "cycling",
          distanceM: some 11978.11,
          geometry: line,
        )
      )
    )
    check f["type"].getStr == "Feature"
    check f["properties"]["kind"].getStr == "route"
    check f["properties"]["id"].getInt == 7
    check f["properties"]["start"].getStr == "2018-08-27T12:00:00Z"
    check f["properties"]["sport"].getStr == "cycling"
    check f["properties"]["distance_m"].getFloat == 11978.1
    check f["geometry"]["coordinates"].len == 2
  test "what is not known is left out":
    let f =
      parseJson(feature(Route(id: ActivityId(1), startT: UnixTime(0), geometry: line)))
    check not f["properties"].hasKey("sport")
    check not f["properties"].hasKey("distance_m")
    check f["properties"]["start"].getStr == "1970-01-01T00:00:00Z"
  test "text is escaped":
    let f = parseJson(
      feature(
        Route(
          id: ActivityId(1), startT: UnixTime(0), sport: "a\"b\\c\n", geometry: line
        )
      )
    )
    check f["properties"]["sport"].getStr == "a\"b\\c\n"
  test "a climb has its name, category and facts, and no look":
    let f = parseJson(
      climbFeature(
        Climb(
          id: 70,
          name: "Farellones₁",
          category: "HC",
          lengthM: 16710.4,
          gainM: 1210.6,
          gradient: 7.24,
          geometry: line,
        )
      )
    )
    check f["properties"]["kind"].getStr == "climb" and
      f["properties"]["id"].getInt == 70
    check f["properties"]["name"].getStr == "Farellones₁" and
      f["properties"]["category"].getStr == "HC"
    check f["properties"]["length_m"].getInt == 16710 and
      f["properties"]["gain_m"].getInt == 1211
    check f["properties"]["gradient"].getFloat == 7.2
    check f["properties"].len == 7 # (kind, id, name, category, length, gain, gradient)
    let none = parseJson(
      climbFeature(
        Climb(id: 1, name: "x", lengthM: 1, gainM: 1, gradient: 1, geometry: line)
      )
    )
    check not none["properties"].hasKey("category")
  test "a collection is valid JSON: the request, the routes and then the climbs, a line each":
    let text = featureCollection(
      @[
        Route(id: ActivityId(1), startT: UnixTime(0), geometry: line),
        Route(id: ActivityId(2), startT: UnixTime(5), geometry: line),
      ],
      @[Climb(id: 9, name: "A", lengthM: 1, gainM: 1, gradient: 1, geometry: line)],
      "selection=AB&state=ab12cd",
      "k1",
    )
    let j = parseJson(text)
    check j["type"].getStr == "FeatureCollection"
    check j["nch"]["request"].getStr == "selection=AB&state=ab12cd"
    check j["nch"]["inputs"].getStr == "k1"
    check j["features"].len == 3
    check j["features"][1]["properties"]["id"].getInt == 2 and
      j["features"][2]["properties"]["kind"].getStr == "climb"
    check text.countLines == 6 # { , 3 features, ]} (and the end)
  test "the start of a file says which request it is for, and from which inputs":
    let text = featureCollection(@[], @[], "selection=AB&state=ab12cd", "k1")
    check text.startsWith(filePrefixFor("selection=AB&state=ab12cd", "k1"))
    check not text.startsWith(filePrefixFor("selection=AB&state=ab12ce", "k1"))
    check not text.startsWith(filePrefixFor("selection=AB&state=ab12cd", "k2"))
    check text.startsWith(requestPrefixFor("selection=AB&state=ab12cd"))
    check not text.startsWith(requestPrefixFor("selection=AB&state=ab12ce"))
    check not requestPrefixFor("selection=AB").startsWith(
      requestPrefixFor("selection=ABC")
    ) # (a longer request is not a start of a shorter)
  test "the key of the climbs follows everything that is shown of them":
    let c = Climb(id: 9, name: "A", lengthM: 1, gainM: 1, gradient: 1, geometry: line)
    check climbsKey(@[c]) == climbsKey(@[c])
    var d = c
    d.name = "B"
    check climbsKey(@[d]) != climbsKey(@[c])
    d = c
    d.category = "4"
    check climbsKey(@[d]) != climbsKey(@[c])
    d = c
    d.geometry = "{}"
    check climbsKey(@[d]) != climbsKey(@[c])
  test "no routes: still valid":
    check parseJson(featureCollection(@[], @[], "", ""))["features"].len == 0
