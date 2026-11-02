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
    check fileStem("heatmap", [("style", "lines"), ("sel", "ab12cd")]) ==
      some "heatmap--sel-ab12cd--style-lines"
    check fileStem("heatmap", [("sel", "ab12cd"), ("style", "lines")]) ==
      fileStem("heatmap", [("style", "lines"), ("sel", "ab12cd")])
  test "no options":
    check fileStem("heatmap", []) == some "heatmap"
  test "values may have letters, digits and . _ , -":
    check fileStem("x", [("tolerance", "5.5"), ("a", "A_b,c-d")]) ==
      some "x--a-A_b,c-d--tolerance-5.5"
  test "anything else is refused":
    for bad in ["", "a b", "a/b", "../x", "a%20", "a--b", "é", "a\nb", "a:b", "a*"]:
      check fileStem("heatmap", [("sel", bad)]).isNone
    check fileStem("Heat", []).isNone
    check fileStem("", []).isNone
    check fileStem("heat map", []).isNone
    check fileStem("heatmap", [("Sel", "x")]).isNone
    check fileStem("heatmap", [("a-b", "x")]).isNone
    check fileStem("heatmap", [("", "x")]).isNone
  test "an option given twice is refused":
    check fileStem("heatmap", [("sel", "a"), ("sel", "b")]).isNone
  test "a name that is too long is refused":
    check fileStem("heatmap", [("sel", "x".repeat(300))]).isNone

suite "cache: files":
  test "the path, with an extension that is allowed":
    check cacheFile("/c/nch", "heatmap--sel-a", "geojson") == some "/c/nch/heatmap--sel-a.geojson"
    check cacheFile("/c/nch", "heatmap--sel-a", "html").isSome
    check cacheFile("/c/nch", "heatmap--sel-a", "exe").isNone
    check cacheFile("/c/nch", "heatmap--sel-a", "").isNone
  test "what the server may serve: the names this module makes":
    for ok in ["heatmap.html", "heatmap--sel-ab12cd--style-lines.geojson",
               "x--tolerance-5.5.geojson"]:
      check isCacheFileName(ok)
  test "and nothing else":
    for bad in ["", ".geojson", "heatmap", "heatmap.exe", "heatmap.geojson.exe",
                "../heatmap.geojson", "a/heatmap.geojson", "/etc/passwd.html",
                "heatmap--.geojson", "heatmap--sel.geojson", "heatmap--sel-.geojson",
                "Heatmap.html", "heat map.html", "heatmap--Sel-a.geojson",
                "heatmap%2e%2e.html", "..", ".", "a\\b.html",
                "heatmap--sel-a b.geojson"]:
      check not isCacheFileName(bad)
    check not isCacheFileName("x".repeat(500) & ".html")
  test "every name made is accepted":
    let stem = fileStem("heatmap", [("sel", "ab12cd"), ("style", "lines")]).get
    for ext in ["html", "geojson"]:
      check isCacheFileName(stem & "." & ext)
