import std/[options, strutils, unittest]
import nimchoo/cache

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

suite "cache: names":
  test "the command, then the options in the order of their names":
    check fileStem("heatmap", [("style", "lines"), ("check", "ab12cd")]) ==
      some "heatmap--check-ab12cd--style-lines"
    check fileStem("heatmap", [("check", "ab12cd"), ("style", "lines")]) ==
      fileStem("heatmap", [("style", "lines"), ("check", "ab12cd")])
  test "no options":
    check fileStem("heatmap", []) == some "heatmap"
  test "values may have letters, digits and . _ , -":
    check fileStem("x", [("tolerance", "5.5"), ("a", "A_b,c-d")]) ==
      some "x--a-A_b,c-d--tolerance-5.5"
  test "anything else is refused":
    for bad in ["", "a b", "a/b", "../x", "a%20", "a--b", "é", "a\nb", "a:b", "a*"]:
      check fileStem("heatmap", [("check", bad)]).isNone
    check fileStem("Heat", []).isNone
    check fileStem("", []).isNone
    check fileStem("heat map", []).isNone
    check fileStem("heatmap", [("Sel", "x")]).isNone
    check fileStem("heatmap", [("a-b", "x")]).isNone
    check fileStem("heatmap", [("", "x")]).isNone
  test "an option given twice is refused":
    check fileStem("heatmap", [("check", "a"), ("check", "b")]).isNone
  test "a name that is too long is refused":
    check fileStem("heatmap", [("check", "x".repeat(300))]).isNone

suite "cache: names back to options":
  test "the inverse of fileStem":
    let stem = fileStem(
      "heatmap", [("style", "lines"), ("check", "ab12cd"), ("tolerance", "5")]
    ).get
    check parseStem(stem) ==
      some(("heatmap", @[("check", "ab12cd"), ("style", "lines"), ("tolerance", "5")]))
    check parseStem("heatmap") == some(("heatmap", newSeq[(string, string)]()))
  test "not a stem":
    for bad in [
      "", "Heatmap", "heatmap--key", "heatmap--check-", "heatmap--Sel-a",
      "heatmap--check-a b", "heatmap----x-y", "a b",
    ]:
      check parseStem(bad).isNone

suite "cache: files":
  test "the path, with an extension that is allowed":
    check cacheFile("/c/nch", "heatmap--check-a", "geojson") ==
      some "/c/nch/heatmap--check-a.geojson"
    check cacheFile("/c/nch", "heatmap--check-a", "html").isSome
    check cacheFile("/c/nch", "heatmap--check-a", "exe").isNone
    check cacheFile("/c/nch", "heatmap--check-a", "").isNone
  test "what the server may serve: the names this module makes":
    for ok in [
      "heatmap.html", "heatmap--check-ab12cd--style-lines.geojson",
      "x--tolerance-5.5.geojson",
    ]:
      check isCacheFileName(ok)
  test "and nothing else":
    for bad in [
      "", ".geojson", "heatmap", "heatmap.exe", "heatmap.geojson.exe",
      "../heatmap.geojson", "a/heatmap.geojson", "/etc/passwd.html",
      "heatmap--.geojson", "heatmap--key.geojson", "heatmap--check-.geojson",
      "Heatmap.html", "heat map.html", "heatmap--Sel-a.geojson", "heatmap%2e%2e.html",
      "..", ".", "a\\b.html", "heatmap--check-a b.geojson",
    ]:
      check not isCacheFileName(bad)
    check not isCacheFileName("x".repeat(500) & ".html")
  test "every name made is accepted":
    let stem = fileStem("heatmap", [("check", "ab12cd"), ("style", "lines")]).get
    for ext in ["html", "geojson"]:
      check isCacheFileName(stem & "." & ext)

suite "cache: the user and system parts":
  test "two parts of the cache directory":
    check userDir("/c/nch") == "/c/nch/user"
    check systemDir("/c/nch") == "/c/nch/system"
  test "files made by commands are named in the user part":
    check cacheFile(userDir("/c/nch"), "heatmap--check-a", "geojson") ==
      some "/c/nch/user/heatmap--check-a.geojson"

suite "cache: names made from a request":
  test "the same request gives the same name: the command, a hyphen, and three proquint groups":
    let a = requestStem("map", "bits=AsBO&check=ab12cd")
    check a.isSome and a == requestStem("map", "bits=AsBO&check=ab12cd")
    check a != requestStem("map", "bits=AsBO&check=ab12ce")
    check a != requestStem("plot", "bits=AsBO&check=ab12cd")
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

suite "cache: the key of the inputs":
  test "the same inputs give the same key; any change of the code or of an input changes it":
    let k = inputsKey("v1", [("importer", "aa"), ("climbs", "bb")])
    check k == inputsKey("v1", [("importer", "aa"), ("climbs", "bb")])
    check k.len == 16
    check k != inputsKey("v2", [("importer", "aa"), ("climbs", "bb")])
    check k != inputsKey("v1", [("importer", "aa"), ("climbs", "bc")])
    check k != inputsKey("v1", [("importer", "aa")]) # (an input dropped)
    check k != inputsKey("v1", [("importer", "aa"), ("climbs", "bb"), ("speed", "cc")])
  test "the owner is part of the key: the same value from another owner is another input":
    check inputsKey("v", [("a", "x")]) != inputsKey("v", [("b", "x")])
