## The climbs, their gates and the efforts as GeoJSON features (climbs/mapfeatures.nim).

import std/[json, unittest]
import nimchoo/packages/climbs/mapfeatures
import nimchoo/core/ids

const line = """{"type":"LineString","coordinates":[[1,2],[3,4]]}"""

suite "climbs features":
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
    check p["elapsed"].getStr == "1m00s" and p["started"].getStr == "1.3km"
    check j["geometry"]["coordinates"].len == 3
