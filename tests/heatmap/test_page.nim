import std/[options, os, strutils, tables, unittest]
import ../support/env
import nimchoo/bundle/unpack
import nimchoo/cache
import nimchoo/heatmap/page
import nimchoo/serve/libraries
import nimchoo/templating

let libs = parseLibraries(librariesBundle.data).toTable

const data = "heatmap--check-ab12cd--style-lines--tolerance-5.geojson"

suite "heatmap page: the text":
  test "it loads Leaflet with the integrity hashes, and the data from the server":
    let h = pageHtml(data, "Heat map ab12cd").get
    check h.startsWith("<!DOCTYPE html>")
    check h.contains("https://unpkg.com/leaflet@1.9.4/dist/leaflet.js")
    check h.contains("https://unpkg.com/leaflet@1.9.4/dist/leaflet.css")
    check h.contains("integrity=\"" & libs["leaflet-js-hash"] & "\"")
    check h.contains("integrity=\"" & libs["leaflet-css-hash"] & "\"")
    check h.contains("fetch('/files/" & data & "')")
    check h.contains("https://tile.openstreetmap.org/{z}/{x}/{y}.png")
    check h.contains("OpenStreetMap")                  # (the attribution the tile policy asks for)
  test "the hashes are the ones of the files that were checked":
    check libs["leaflet-js-hash"] == "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
    check libs["leaflet-css-hash"] == "sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
  test "the lines are thin and mostly transparent, so that overlaps glow":
    let h = pageHtml(data, "t").get
    check h.contains("opacity: 0.25") and h.contains("weight: 2")
  test "no placeholder is left":
    let h = pageHtml(data, "t").get
    check "{{" notin h and "}}}" notin h                  # (every tag was filled in)
  test "the title is text, not markup":
    let h = pageHtml(data, "<script>alert(1)</script> & \"x\"").get
    check not h.contains("<script>alert")
    check h.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;x&quot;")
  test "only the name of a cache file, and a geojson one":
    for bad in ["", "../x.geojson", "a/b.geojson", "heatmap.html",
                "heatmap--check-a.geojson'); alert(1); ('", "heatmap--check-a b.geojson",
                "heatmap--check-a.geojson.exe"]:
      check pageHtml(bad, "t").isNone
    check pageHtml("heatmap.geojson", "t").isSome
    check pageHtml("x.geojson", "t").isSome               # (a name the cache could hold)

suite "heatmap page: the template and the libraries are files":
  teardown: useTestCache()
  test "the built-in template is the one in the cache until the author changes it":
    let top = getTempDir() / "nch-test-heatmap-page"
    removeDir top
    putEnv("NCH_CACHE", top)
    check pageHtml(data, "t").get.startsWith("<!DOCTYPE html>")
    check readFile(systemDir(top) / "templates" / "heatmap.html") == pageTemplate
    check readFile(systemDir(top) / "libraries.txt") == librariesBundle.data
    writeFile(systemDir(top) / "templates" / "heatmap.html", "<h1>{{title}}</h1> <a href=\"{{leaflet-js}}\">{{data}}</a>\n")
    check pageHtml(data, "My <map>").get == "<h1>My &lt;map&gt;</h1> <a href=\"" & libs["leaflet-js"] & "\">" & data & "</a>\n"
  test "other versions of the libraries: change the file":
    let top = getTempDir() / "nch-test-heatmap-libs"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml(data, "t")
    writeFile(systemDir(top) / "libraries.txt", librariesBundle.data.replace("leaflet@1.9.4", "leaflet@9.9.9"))
    let h = pageHtml(data, "t").get
    check h.contains("leaflet@9.9.9/dist/leaflet.js") and not h.contains("leaflet@1.9.4")
  test "a template with a mistake is an error that says where":
    let top = getTempDir() / "nch-test-heatmap-bad"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml(data, "t")
    writeFile(systemDir(top) / "templates" / "heatmap.html", "line one\n{{nothing-like-this}}\n")
    expect TemplateError: discard pageHtml(data, "t")
    try: discard pageHtml(data, "t")
    except TemplateError as e: check e.msg == "line 2: there is no value called 'nothing-like-this'"
  test "the pure form takes the template and the libraries as they are":
    let page = renderPage("{{title}}|{{data}}|{{x}}", @[("x", text("1"))], data, "T")
    check page == some("T|" & data & "|1")
    check renderPage("{{title}}", @[], "../x.geojson", "T").isNone

