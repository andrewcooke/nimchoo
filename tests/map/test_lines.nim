import std/[json, options, strutils, unittest]
import nimchoo/packages/fit/time
import nimchoo/packages/map/lines
import nimchoo/packages/geo/cells
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
  test "a collection is valid JSON: the routes and then the climbs, a line each":
    let text = featureCollection(
      @[
        Route(id: ActivityId(1), startT: UnixTime(0), geometry: line),
        Route(id: ActivityId(2), startT: UnixTime(5), geometry: line),
      ],
      @[Climb(id: 9, name: "A", lengthM: 1, gainM: 1, gradient: 1, geometry: line)],
    )
    let j = parseJson(text)
    check j["type"].getStr == "FeatureCollection"
    check j["features"].len == 3
    check j["features"][1]["properties"]["id"].getInt == 2 and
      j["features"][2]["properties"]["kind"].getStr == "climb"
    check text.countLines == 6 # { , 3 features, ]} (and the end)
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
    check parseJson(featureCollection(@[], @[]))["features"].len == 0

suite "map lines: the heat":
  test "a cell is a square polygon that closes, with its counts":
    let c = cellOf(-70.65, -33.45).get
    let j = parseJson(heatFeature(HeatCell(cell: c, bits: 0, visits: 7, rides: 3)))
    check j["type"].getStr == "Feature"
    let p = j["properties"]
    check p["kind"].getStr == "heat" and p["level"].getInt == 0 and
      p["visits"].getInt == 7 and p["rides"].getInt == 3
    check p.len == 4
    let ring = j["geometry"]["coordinates"][0]
    check j["geometry"]["type"].getStr == "Polygon" and ring.len == 5 and
      ring[0] == ring[4]
    let b = bounds(c)
    check abs(ring[0][0].getFloat - b.west) < 1e-6 and
      abs(ring[2][1].getFloat - b.north) < 1e-6
  test "a coarser level is a bigger square":
    let c = coarsen(cellOf(-70.65, -33.45).get, 3)
    let ring = parseJson(heatFeature(HeatCell(cell: c, bits: 3, visits: 1, rides: 1)))[
      "geometry"
    ]["coordinates"][0]
    check abs((ring[1][0].getFloat - ring[0][0].getFloat) - 8.0 / 1024.0) < 1e-5
  test "the heat is in the file, under the routes and the climbs, a line each":
    let text = featureCollection(
      @[Route(id: ActivityId(1), startT: UnixTime(0), geometry: line)],
      @[],
      @[HeatCell(cell: cell(5, 6), bits: 0, visits: 1, rides: 1)],
    )
    let j = parseJson(text)
    check j["features"].len == 2
    check j["features"][0]["properties"]["kind"].getStr == "heat"
    check j["features"][1]["properties"]["kind"].getStr == "route"

suite "map lines: gates and efforts":
  test "a gate is a short line, with the climb and which end":
    let j = parseJson(
      gateFeature(
        GateLine(
          climbId: 7, name: "Cerro", start: true, ends: [(-70.1, -33.2), (-70.2, -33.3)]
        )
      )
    )
    check j["properties"]["kind"].getStr == "gate" and j["properties"]["id"].getInt == 7
    check j["properties"]["end"].getStr == "start" and
      j["properties"]["name"].getStr == "Cerro"
    check j["geometry"]["coordinates"].len == 2
    check parseJson(gateFeature(GateLine(climbId: 7, name: "Cerro", start: false)))[
      "properties"
    ]["end"].getStr == "finish"
  test "an effort is the positions between its times, with the times as text and the start as a whole number (valid JSON)":
    let j = parseJson(
      effortFeature(
        EffortLine(
          activityId: ActivityId(4),
          climbId: 7,
          name: "Cerro",
          startT: 1535371200.4,
          finishT: 1535371260.6,
          elapsedS: 60.2,
          startM: 1253.4,
          points: @[(-70.1, -33.2), (-70.2, -33.3), (-70.3, -33.4)],
        )
      )
    )
    let p = j["properties"]
    check p["kind"].getStr == "effort" and p["activity"].getInt == 4 and
      p["id"].getInt == 7
    check p["start"].getStr == "2018-08-27T12:00:00Z" and
      p["finish"].getStr == "2018-08-27T12:01:01Z"
    check p["elapsed_s"].getFloat == 60.2 and p["start_m"].getInt == 1253
    check j["geometry"]["coordinates"].len == 3
  test "the file puts the heat first, then the routes, the efforts, the climbs and the gates":
    let text = featureCollection(
      @[Route(id: ActivityId(1), startT: UnixTime(0), geometry: line)],
      @[Climb(id: 9, name: "A", lengthM: 1, gainM: 1, gradient: 1, geometry: line)],
      @[HeatCell(cell: cell(5, 6), bits: 0, visits: 1, rides: 1)],
      @[
        EffortLine(
          activityId: ActivityId(1), climbId: 9, name: "A", points: @[(1.0, 2.0)]
        )
      ],
      @[GateLine(climbId: 9, name: "A", start: true)],
    )
    var kinds: seq[string]
    for f in parseJson(text)["features"]:
      kinds.add f["properties"]["kind"].getStr
    check kinds == @["heat", "route", "effort", "climb", "gate"]
  test "the keys follow what is drawn":
    let g = @[GateLine(climbId: 9, name: "A", start: true)]
    let e = @[
      EffortLine(
        activityId: ActivityId(1), climbId: 9, name: "A", points: @[(1.0, 2.0)]
      )
    ]
    check gatesKey(g) == gatesKey(g) and
      gatesKey(g) != gatesKey(@[GateLine(climbId: 9, name: "B", start: true)])
    var e2 = e
    e2[0].points.add (3.0, 4.0)
    check effortsKey(e) != effortsKey(e2)
