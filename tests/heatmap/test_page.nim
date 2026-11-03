import std/[options, strutils, unittest]
import nimchoo/heatmap/page

const data = "heatmap--sel-ab12cd--style-lines--tolerance-5.geojson"

suite "heatmap page: the text":
  test "it loads Leaflet with the integrity hashes, and the data from the server":
    let h = pageHtml(data, "Heat map ab12cd").get
    check h.startsWith("<!DOCTYPE html>")
    check h.contains("https://unpkg.com/leaflet@1.9.4/dist/leaflet.js")
    check h.contains("https://unpkg.com/leaflet@1.9.4/dist/leaflet.css")
    check h.contains("integrity=\"" & leafletJsHash & "\"")
    check h.contains("integrity=\"" & leafletCssHash & "\"")
    check h.contains("fetch('/files/" & data & "')")
    check h.contains("https://tile.openstreetmap.org/{z}/{x}/{y}.png")
    check h.contains("OpenStreetMap")                  # (the attribution the tile policy asks for)
  test "the hashes are the ones of the files that were checked":
    check leafletJsHash == "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
    check leafletCssHash == "sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
  test "the lines are thin and mostly transparent, so that overlaps glow":
    let h = pageHtml(data, "t").get
    check h.contains("opacity: 0.25") and h.contains("weight: 2")
  test "no placeholder is left":
    let h = pageHtml(data, "t").get
    for key in ["@TITLE@", "@CDN@", "@CSSHASH@", "@JSHASH@", "@TILES@", "@DATA@"]:
      check not h.contains(key)
  test "the title is text, not markup":
    let h = pageHtml(data, "<script>alert(1)</script> & \"x\"").get
    check not h.contains("<script>alert")
    check h.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;x&quot;")
  test "only the name of a cache file, and a geojson one":
    for bad in ["", "../x.geojson", "a/b.geojson", "heatmap.html",
                "heatmap--sel-a.geojson'); alert(1); ('", "heatmap--sel-a b.geojson",
                "heatmap--sel-a.geojson.exe"]:
      check pageHtml(bad, "t").isNone
    check pageHtml("heatmap.geojson", "t").isSome
    check pageHtml("x.geojson", "t").isSome               # (a name the cache could hold)
