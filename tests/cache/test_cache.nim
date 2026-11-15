import std/[options, strutils, unittest]
import nimchoo/packages/cache/cache

suite "cache: the directory":
  test "NCH_CACHE wins":
    check cachePath(some "/x", some "/c", some "/h") == some "/x"
  test "an empty NCH_CACHE is ignored":
    check cachePath(some "", some "/c", some "/h") == some "/c/nch"
  test "XDG_CACHE_HOME if absolute, else the home directory":
    check cachePath(none string, some "/c", some "/h") == some "/c/nch"
    check cachePath(none string, some "rel", some "/h") == some "/h/.cache/nch"
    check cachePath(none string, none string, some "/h") == some "/h/.cache/nch"
  test "nothing known":
    check cachePath(none string, none string, none string).isNone
    check cachePath(none string, none string, some "").isNone

suite "cache: files":
  test "the path, with an extension that is allowed":
    check cacheFile("/c/nch", "heatmap-lusab-babad", "geojson") ==
      some "/c/nch/heatmap-lusab-babad.geojson"
    check cacheFile("/c/nch", "heatmap-lusab-babad", "html").isSome
    check cacheFile("/c/nch", "heatmap-lusab-babad", "exe").isNone
    check cacheFile("/c/nch", "heatmap-lusab-babad", "").isNone
  test "what the server may serve: the names this module makes":
    for ok in [
      "map-routes-climbs.html", "ff-default-hourly.csv",
      "ff-default-fitness-scale-1.5.csv",
    ]:
      check isCacheFileName(ok)
  test "and nothing else":
    for bad in [
      "", ".geojson", "heatmap", "heatmap.exe", "heatmap.geojson.exe",
      "../heatmap.geojson", "a/heatmap.geojson", "/etc/passwd.html", "heatmap.html",
      "heatmap--check-ab12cd--style-lines.geojson", "heatmap--.geojson", "Heatmap.html",
      "heat map.html", "heatmap%2e%2e.html", "..", ".", "a\\b.html",
    ]:
      check not isCacheFileName(bad)
    check not isCacheFileName("x".repeat(500) & ".html")

suite "cache: the user and system parts":
  test "two parts of the cache directory":
    check userDir("/c/nch") == "/c/nch/user"
    check systemDir("/c/nch") == "/c/nch/system"
  test "files made by commands are named in the user part":
    check cacheFile(userDir("/c/nch"), "heatmap-lusab-babad", "geojson") ==
      some "/c/nch/user/heatmap-lusab-babad.geojson"

suite "cache: names made from the options":
  test "a name is the command, a hyphen and the options spelt out":
    for stem in ["map-routes", "map-routes-climbs", "ff-default-to-2018-09-05-utc"]:
      check isFileStem(stem)
      check cacheFile("/c/nch", stem, "geojson").isSome
      for ext in ["geojson", "html", "csv"]:
        check isCacheFileName(stem & "." & ext)
    check not isCacheFileName("map-routes.exe")
  test "not a name for anything else":
    for bad in [
      "map", "map-", "-routes", "Map-routes", "a b-routes", "map-routes-",
      "map--routes", "map-a/b", "map-ro utes", "ff-x%2e", "",
    ]:
      check not isFileStem(bad)
    check not isCacheFileName("../map-routes.geojson") and
      not isCacheFileName("map-routes-.geojson")
