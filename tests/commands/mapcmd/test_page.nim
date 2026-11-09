import std/[options, os, strutils, tables, unittest]
import ../../support/env
import nimchoo/packages/bundle/unpack
import nimchoo/packages/cache/cache
import nimchoo/packages/commands/mapcmd/page
import nimchoo/packages/web/libraries
import nimchoo/packages/text/templating/templating

let libs = parseLibraries(librariesBundle.data).toTable

const data = "map-lusab-babad-fuzoh.geojson"

suite "map page: the text":
  test "it loads Leaflet with the integrity hashes, and the data from the server":
    let h = pageHtml(data, "Map").get
    check h.startsWith("<!DOCTYPE html>")
    check h.contains("https://unpkg.com/leaflet@1.9.4/dist/leaflet.js")
    check h.contains("https://unpkg.com/leaflet@1.9.4/dist/leaflet.css")
    check h.contains("integrity=\"" & libs["leaflet-js-hash"] & "\"")
    check h.contains("integrity=\"" & libs["leaflet-css-hash"] & "\"")
    check h.contains("fetch('/files/" & data & "')")
    check h.contains("https://tile.openstreetmap.org/{z}/{x}/{y}.png")
    check h.contains("OpenStreetMap") # (the attribution the tile policy asks for)
  test "the hashes are the ones of the files that were checked":
    check libs["leaflet-js-hash"] ==
      "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
    check libs["leaflet-css-hash"] ==
      "sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
  test "the look comes from the css and the style templates, with the palette's colours filled in":
    let h = pageHtml(data, "t").get
    check h.contains("html, body, #map { height: 100%; margin: 0; }")
      # the css, in the page
    check h.contains("color: #222222;") # {{white}} of the palette
    check h.contains("\"routes\": { \"color\": \"#e03131\"")
      # {{{red}}} of the palette, in the style
    check h.contains("\"spread_m\": 4") and h.contains("\"smooth_rounds\": 2")
    check h.contains("const style = {") # the page reads it
    check not h.contains("{{!") # (comments are gone)
  test "no placeholder is left":
    let h = pageHtml(data, "t").get
    check "{{" notin h and "}}}" notin h # (every tag was filled in)
  test "the title is text, not markup":
    let h = pageHtml(data, "<script>alert(1)</script> & \"x\"").get
    check not h.contains("<script>alert")
    check h.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;x&quot;")
  test "only the name of a cache file, and a geojson one":
    for bad in [
      "", "../x.geojson", "a/b.geojson", "map.html",
      "heatmap--check-a.geojson'); alert(1); ('", "heatmap--check-a b.geojson",
      "heatmap--check-a.geojson.exe",
    ]:
      check pageHtml(bad, "t").isNone
    check pageHtml("heatmap.geojson", "t").isSome
    check pageHtml("x.geojson", "t").isSome # (a name the cache could hold)

suite "map page: the template and the libraries are files":
  teardown:
    useTestCache()
  test "the built-in template is the one in the cache until the author changes it":
    let top = getTempDir() / "nch-test-map-page"
    removeDir top
    putEnv("NCH_CACHE", top)
    check pageHtml(data, "t").get.startsWith("<!DOCTYPE html>")
    check readFile(systemDir(top) / "templates" / "map.html") == pageTemplate
    check readFile(systemDir(top) / "libraries.txt") == librariesBundle.data
    writeFile(
      systemDir(top) / "templates" / "map.html",
      "<h1>{{title}}</h1> <a href=\"{{leaflet-js}}\">{{data}}</a>\n",
    )
    check pageHtml(data, "My <map>").get ==
      "<h1>My &lt;map&gt;</h1> <a href=\"" & libs["leaflet-js"] & "\">" & data & "</a>\n"
  test "other versions of the libraries: change the file":
    let top = getTempDir() / "nch-test-map-libs"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml(data, "t")
    writeFile(
      systemDir(top) / "libraries.txt",
      librariesBundle.data.replace("leaflet@1.9.4", "leaflet@9.9.9"),
    )
    let h = pageHtml(data, "t").get
    check h.contains("leaflet@9.9.9/dist/leaflet.js") and not h.contains(
      "leaflet@1.9.4"
    )
  test "a template with a mistake is an error that says where":
    let top = getTempDir() / "nch-test-map-bad"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml(data, "t")
    writeFile(
      systemDir(top) / "templates" / "map.html", "line one\n{{nothing-like-this}}\n"
    )
    expect TemplateError:
      discard pageHtml(data, "t")
    try:
      discard pageHtml(data, "t")
    except TemplateError as e:
      check e.msg == "line 2: there is no value called 'nothing-like-this'"
  test "the pure form takes the template, the libraries, the css and the style as they are":
    let page = renderPage(
      "{{title}}|{{data}}|{{x}}|{{{css}}}|{{{style}}}",
      @[("x", text("1"))],
      data,
      "T",
      "a{}",
      "{\"k\":1}",
    )
    check page == some("T|" & data & "|1|a{}|{\"k\":1}")
    check renderPage("{{title}}", @[], "../x.geojson", "T").isNone
  test "a closing script tag in the style cannot end the script of the page":
    let page = renderPage(
      "<script>const s = {{{style}}};</script>",
      @[],
      data,
      "T",
      "",
      "{\"k\":\"</script><b>\"}",
    ).get
    check page.count("</script") == 1
    check page.contains("<\\/script><b>")

suite "map page: the css and the style are files too":
  teardown:
    useTestCache()
  test "the author's css and style are used as they are, and never overwritten":
    let top = getTempDir() / "nch-test-map-look"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml(data, "t")
    check readFile(systemDir(top) / "templates" / "map.css") == cssBundle.data
    check readFile(systemDir(top) / "templates" / "map-style.json") == styleBundle.data
    writeFile(systemDir(top) / "templates" / "map.css", "body { color: {{blue}}; }\n")
    writeFile(
      systemDir(top) / "templates" / "map-style.json",
      styleBundle.data.replace("\"spread_m\": 4", "\"spread_m\": 9"),
    )
    let h = pageHtml(data, "t").get
    check h.contains("body { color: #4dabf7; }") and h.contains("\"spread_m\": 9") and
      not h.contains("height: 100%")
    check readFile(systemDir(top) / "templates" / "map.css") ==
      "body { color: {{blue}}; }\n" # (still the author's)
  test "a style that is not JSON, or lacks something the page reads, is an error that says so":
    let top = getTempDir() / "nch-test-map-badstyle"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml(data, "t")
    writeFile(systemDir(top) / "templates" / "map-style.json", "{ \"routes\": ")
    try:
      discard pageHtml(data, "t")
    except TemplateError as e:
      check e.msg.startsWith("map-style.json is not valid JSON")
    writeFile(
      systemDir(top) / "templates" / "map-style.json",
      "{ \"routes\": {}, \"climbs\": {}, \"smooth_rounds\": 2 }",
    )
    try:
      discard pageHtml(data, "t")
    except TemplateError as e:
      check e.msg == "map-style.json has no routes.color"
    writeFile(systemDir(top) / "templates" / "map-style.json", styleBundle.data)
    check pageHtml(data, "t").isSome
  test "a mistake in the css template says which file":
    let top = getTempDir() / "nch-test-map-badcss"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml(data, "t")
    writeFile(systemDir(top) / "templates" / "map.css", "a {}\n{{nothing-like-this}}\n")
    try:
      discard pageHtml(data, "t")
    except TemplateError as e:
      check e.msg == "map.css: line 2: there is no value called 'nothing-like-this'"
