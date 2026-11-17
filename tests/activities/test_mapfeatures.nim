## The routes and the heat as GeoJSON features (activities/mapfeatures.nim).

import std/[json, options, unittest]
import nimchoo/packages/activities/mapfeatures
import nimchoo/packages/fit/time
import nimchoo/packages/geo/cells
import nimchoo/core/ids

const line = """{"type":"LineString","coordinates":[[1,2],[3,4]]}"""

suite "activities features: the routes":
  test "a feature has the properties and the geometry":
    let f = parseJson(
      routeFeature(
        Route(
          id: ActivityId(7),
          startT: UnixTime(1535371200),
          sport: "cycling",
          name: "Farellones and back",
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
    check f["properties"]["name"].getStr == "Farellones and back"
    check f["properties"]["distance_m"].getFloat == 11978.1
    check f["geometry"]["coordinates"].len == 2
  test "what is not known is left out":
    let f = parseJson(
      routeFeature(Route(id: ActivityId(1), startT: UnixTime(0), geometry: line))
    )
    check not f["properties"].hasKey("sport") and not f["properties"].hasKey("name")
    check not f["properties"].hasKey("distance_m")
    check f["properties"]["start"].getStr == "1970-01-01T00:00:00Z"
  test "text is escaped":
    let f = parseJson(
      routeFeature(
        Route(
          id: ActivityId(1), startT: UnixTime(0), sport: "a\"b\\c\n", geometry: line
        )
      )
    )
    check f["properties"]["sport"].getStr == "a\"b\\c\n"

suite "activities features: the heat":
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
