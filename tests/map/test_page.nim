import std/[json, os, sequtils, strutils, tables, unittest]
import ../support/env
import nimchoo/packages/bundle/unpack
import nimchoo/packages/cache/cache
import nimchoo/packages/map/[frames, page]
import nimchoo/packages/web/libraries
import nimchoo/packages/text/templating/templating
import nimchoo/core/extension
from nimchoo/registry import extensions

let libs = parseLibraries(librariesBundle.data).toTable

proc real(name: string): MapFrame =
  ## A frame of the program, with the style and drawing its provider ships.
  extensions.get(mapFramePoint).filterIt(it.subject == "activities" and it.name == name)[
    0
  ]

proc pageHtml(title: string): string =
  ## The page of the activities, with the routes ticked and the heat not.
  var heat = real("heat")
  heat.shown = false
  var routes = real("routes")
  routes.shown = true
  pageHtml(@[routes, heat], "activities", title)

suite "map page: the text":
  test "it loads Leaflet with the integrity hashes, and the data from the server":
    let h = pageHtml("Map")
    check h.startsWith("<!DOCTYPE html>")
    check h.contains("https://unpkg.com/leaflet@1.9.4/dist/leaflet.js")
    check h.contains("https://unpkg.com/leaflet@1.9.4/dist/leaflet.css")
    check h.contains("integrity=\"" & libs["leaflet-js-hash"] & "\"")
    check h.contains("integrity=\"" & libs["leaflet-css-hash"] & "\"")
    check h.contains("\"name\":\"routes\"") # the frames, in the list the page fetches
    check h.contains("fetch(location.pathname + '?frame='")
    check h.contains("https://tile.openstreetmap.org/{z}/{x}/{y}.png")
    check h.contains("OpenStreetMap") # (the attribution the tile policy asks for)
  test "the hashes are the ones of the files that were checked":
    check libs["leaflet-js-hash"] ==
      "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
    check libs["leaflet-css-hash"] ==
      "sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
  test "the look comes from the css and the style templates, each with its own colours":
    let h = pageHtml("t")
    check h.contains("html, body, #map { height: 100%; margin: 0; }")
      # the css, in the page
    check h.contains("color: #222222;") # (the text, in map.css)
    check h.contains("\"name\":\"routes\"") and
      h.contains("\"style\":{\"color\":\"#e03131\"")
      # (the routes' colour, in their style, under the frame's name)
    check h.contains("\"spread_m\":4") and h.contains("\"smooth_rounds\":2")
    check h.contains("const common = {") and h.contains("const frames = [")
      # the page reads them
    check h.contains("drawers[\"activities-map-routes\"] = (") and
      h.contains("ctx.shared.routesSpreadM") # the routes' drawing, in the page
    check not h.contains("{{!") # (comments are gone)
  test "no placeholder is left":
    let h = pageHtml("t")
    check "{{" notin h and "}}}" notin h # (every tag was filled in)
  test "the title is text, not markup":
    let h = pageHtml("<script>alert(1)</script> & \"x\"")
    check not h.contains("<script>alert")
    check h.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;x&quot;")
  test "every frame of the subject is listed, the ticked ones marked; the page fetches the data of a frame from its own address":
    let h = pageHtml("t")
    check h.contains("\"name\":\"routes\"") and h.contains("\"name\":\"heat\"")
    check h.contains("\"shown\":true") and h.contains("\"shown\":false")
    check h.contains("'?frame='")
    check h.contains("localStorage") # (the browser remembers which are ticked)
  test "the libraries a frame's drawing uses are loaded, with their hashes (the heat: Leaflet.heat)":
    let h = pageHtml("t")
    check h.contains(
      "<script src=\"https://unpkg.com/leaflet.heat@0.2.0/dist/leaflet-heat.js\" integrity=\"" &
        libs["leaflet-heat-js-hash"] & "\""
    )

suite "map page: the template and the libraries are files":
  teardown:
    useTestCache()
  test "the built-in template is the one in the cache until the author changes it":
    let top = getTempDir() / "nch-test-map-page"
    removeDir top
    putEnv("NCH_CACHE", top)
    check pageHtml("t").startsWith("<!DOCTYPE html>")
    check readFile(systemDir(top) / "templates" / "map.html") == pageTemplate
    check readFile(systemDir(top) / "libraries.cdn") == librariesBundle.data
    writeFile(
      systemDir(top) / "templates" / "map.html",
      "<h1>{{title}}</h1> <a href=\"{{leaflet-js}}\">{{{frames}}}</a>\n",
    )
    check pageHtml("My <map>").startsWith(
      "<h1>My &lt;map&gt; of activities</h1> <a href=\"" & libs["leaflet-js"] &
        "\">[{\"name\":\"routes\",\"summary\":\""
    )
  test "other versions of the libraries: change the file":
    let top = getTempDir() / "nch-test-map-libs"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml("t")
    writeFile(
      systemDir(top) / "libraries.cdn",
      librariesBundle.data.replace("leaflet@1.9.4", "leaflet@9.9.9"),
    )
    let h = pageHtml("t")
    check h.contains("leaflet@9.9.9/dist/leaflet.js") and not h.contains(
      "leaflet@1.9.4"
    )
  test "a template with a mistake is an error that says where":
    let top = getTempDir() / "nch-test-map-bad"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml("t")
    writeFile(
      systemDir(top) / "templates" / "map.html", "line one\n{{nothing-like-this}}\n"
    )
    expect TemplateError:
      discard pageHtml("t")
    try:
      discard pageHtml("t")
    except TemplateError as e:
      check e.msg == "line 2: there is no value called 'nothing-like-this'"
  test "the pure form takes the template, the libraries, the frames, the css, the style and the drawings as they are":
    let page = renderPage(
      "{{title}}|{{{frames}}}|{{x}}|{{{css}}}|{{{style}}}|{{{drawers}}}",
      @[("x", text("1"))],
      @[
        PageFrame(name: "b", summary: "B", shown: true, style: %*{"k": 1}, drawer: "d"),
        PageFrame(name: "c", summary: "C", style: %*{}),
      ],
      "T",
      "a{}",
      "{\"k\":1}",
      @[("d", "(features, ctx) => ({})\n")],
    )
    check page ==
      "T|[{\"name\":\"b\",\"summary\":\"B\",\"shown\":true,\"style\":{\"k\":1},\"drawer\":\"d\"}," &
      "{\"name\":\"c\",\"summary\":\"C\",\"shown\":false,\"style\":{},\"drawer\":\"\"}]|1|a{}|{\"k\":1}|" &
      "  drawers[\"d\"] = (\n(features, ctx) => ({})\n  );\n"
  test "a closing script tag in a style or a summary cannot end the script of the page":
    let page = renderPage(
      "<script>const s = {{{style}}}; const f = {{{frames}}};</script>",
      @[],
      @[PageFrame(name: "b", summary: "</script>", style: %*{"k": "</script><i>"})],
      "T",
      "",
      "{\"k\":\"</script><b>\"}",
    )
    check page.count("</script") == 1
    check page.contains("<\\/script><b>") and page.contains("<\\/script><i>")

suite "map page: the css and the style are files too":
  teardown:
    useTestCache()
  test "the author's css and style are used as they are, and never overwritten":
    let top = getTempDir() / "nch-test-map-look"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml("t")
    check readFile(systemDir(top) / "templates" / "map.css") == cssBundle.data
    check readFile(systemDir(top) / "templates" / "map-style.json") == styleBundle.data
    check readFile(systemDir(top) / "templates" / "activities-map-routes.json").contains(
      "spread_m"
    ) # (a style for each frame, shipped by its provider)
    writeFile(systemDir(top) / "templates" / "map.css", "body { color: #123456; }\n")
    writeFile(
      systemDir(top) / "templates" / "activities-map-routes.json",
      readFile(systemDir(top) / "templates" / "activities-map-routes.json").replace(
        "\"spread_m\": 4", "\"spread_m\": 9"
      ),
    )
    let h = pageHtml("t")
    check h.contains("body { color: #123456; }") and h.contains("\"spread_m\":9") and
      not h.contains("height: 100%")
    check readFile(systemDir(top) / "templates" / "map.css") ==
      "body { color: #123456; }\n" # (still the author's)
  test "a style that is not JSON, or lacks something the page reads, is an error that says which file":
    let top = getTempDir() / "nch-test-map-badstyle"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml("t")
    let routes = systemDir(top) / "templates" / "activities-map-routes.json"
    let original = readFile(routes)
    writeFile(routes, "{ \"routes\": ")
    try:
      discard pageHtml("t")
      check false
    except TemplateError as e:
      check e.msg.startsWith("activities-map-routes.json is not valid JSON")
    writeFile(routes, "[1]")
    try:
      discard pageHtml("t")
      check false
    except TemplateError as e:
      check e.msg == "activities-map-routes.json is not a JSON object"
    writeFile(routes, "{ \"weight\": 3 }")
    try:
      discard pageHtml("t")
      check false
    except TemplateError as e:
      check e.msg == "activities-map-routes.json has no color"
    writeFile(routes, original)
    let common = systemDir(top) / "templates" / "map-style.json"
    writeFile(common, "{}")
    try:
      discard pageHtml("t")
      check false
    except TemplateError as e:
      check e.msg == "map-style.json has no smooth_rounds"
    writeFile(common, styleBundle.data)
    check pageHtml("t").len > 0
  test "a mistake in the css template says which file":
    let top = getTempDir() / "nch-test-map-badcss"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml("t")
    writeFile(systemDir(top) / "templates" / "map.css", "a {}\n{{nothing-like-this}}\n")
    try:
      discard pageHtml("t")
    except TemplateError as e:
      check e.msg == "map.css: line 2: there is no value called 'nothing-like-this'"

suite "map page: the drawings of the frames are files too":
  teardown:
    useTestCache()
  test "the author's drawing is used as it is, and a closing script tag in it is an error that says which file":
    let top = getTempDir() / "nch-test-map-drawing"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml("t")
    let js = systemDir(top) / "templates" / "activities-map-routes.js"
    check readFile(js).contains("routesSpreadM") # (unpacked, as the provider ships it)
    writeFile(js, "// mine\n(features, ctx) => ({ caption: 'my routes' })\n")
    check pageHtml("t").contains("caption: 'my routes'")
    writeFile(js, "(features, ctx) => '</SCRIPT>'\n")
    try:
      discard pageHtml("t")
      check false
    except TemplateError as e:
      check e.msg == "activities-map-routes.js has a closing script tag in it"
  test "a drawing used by two frames is in the page once":
    let routes = real("routes")
    var again = routes
    again.name = "again"
    let h = pageHtml(@[routes, again], "activities", "t")
    check h.count("drawers[\"activities-map-routes\"] = (") == 1
    check h.contains("\"name\":\"again\"")
