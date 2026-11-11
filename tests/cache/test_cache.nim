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
    for ok in ["map-lusab-babad-fuzoh.html", "ff-lusab-babad-fuzoh.csv"]:
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
  test "every name made is accepted":
    let stem = requestStem("ff", "state=ab12cd&to=2018-09-05").get
    for ext in ["html", "geojson"]:
      check isCacheFileName(stem & "." & ext)

suite "cache: the user and system parts":
  test "two parts of the cache directory":
    check userDir("/c/nch") == "/c/nch/user"
    check systemDir("/c/nch") == "/c/nch/system"
  test "files made by commands are named in the user part":
    check cacheFile(userDir("/c/nch"), "heatmap-lusab-babad", "geojson") ==
      some "/c/nch/user/heatmap-lusab-babad.geojson"

suite "cache: names made from a request":
  test "the same request gives the same name: the command, a hyphen, and three proquint groups":
    let a = requestStem("map", "selection=AsBO&state=ab12cd")
    check a.isSome and a == requestStem("map", "selection=AsBO&state=ab12cd")
    check a != requestStem("map", "selection=AsBO&state=ab12ce")
    check a != requestStem("plot", "selection=AsBO&state=ab12cd")
    let name = a.get
    check name.startsWith("map-") and name.len == 4 + 17 and not name.contains("--")
  test "they are accepted as file names, with an extension that is allowed":
    let name = requestStem("map", "x").get
    check cacheFile("/c/nch", name, "geojson").isSome
    for ext in ["geojson", "html", "csv"]:
      check isCacheFileName(name & "." & ext)
    check not isCacheFileName(name & ".exe") and
      not isCacheFileName("map-notaproquint.geojson")
    check not isCacheFileName("map-lusab-babad-.geojson") and
      not isCacheFileName("map-.geojson")
    check not isCacheFileName("../map-lusab-babad.geojson") and
      not isCacheFileName("Map-lusab-babad.geojson")
    check isCacheFileName("map-lusab-babad.geojson") and
      not isCacheFileName("map-lusab-babad-xx.geojson")
  test "not a name for anything that is not a command":
    check requestStem("Map", "x").isNone and requestStem("", "x").isNone and
      requestStem("a-b", "x").isNone

suite "cache: the state of the inputs":
  test "the same inputs give the same state; any change of an input changes it":
    let k = stateKey([("importer", "aa"), ("climbs", "bb")])
    check k == stateKey([("importer", "aa"), ("climbs", "bb")])
    check k.len == 16
    check k != stateKey([("importer", "aa"), ("climbs", "bc")])
    check k != stateKey([("importer", "aa")]) # (an input dropped)
    check k != stateKey([("importer", "aa"), ("climbs", "bb"), ("speed", "cc")])
  test "the owner is part of the state: the same value from another owner is another input":
    check stateKey([("a", "x")]) != stateKey([("b", "x")])
