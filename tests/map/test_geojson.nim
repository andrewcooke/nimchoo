## A file of features (map/geojson.nim).

import std/[json, strutils, unittest]
import nimchoo/packages/map/geojson

const point =
  """{"type":"Feature","properties":{"kind":"x"},"geometry":{"type":"Point","coordinates":[1,2]}}"""

suite "map: a file of features":
  test "valid JSON, a feature to a line, in the order given":
    let text = featureCollection(@[point, point.replace("\"x\"", "\"y\"")])
    let j = parseJson(text)
    check j["type"].getStr == "FeatureCollection"
    check j["features"].len == 2 and j["features"][1]["properties"]["kind"].getStr == "y"
    check text.countLines == 5 # { , 2 features, ]} (and the end)
  test "no features: still valid":
    check parseJson(featureCollection(@[]))["features"].len == 0
