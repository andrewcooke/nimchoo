import std/[strutils, tables, unittest]
import nimchoo/packages/web/libraries
import nimchoo/packages/text/templating/templating

suite "libraries: the file of CDN libraries":
  test "name = value lines; comments, blank lines and lines that are not that are left out":
    check parseLibraries(
      "# a comment\n\nx = 1\n  y=2  \nnot a line\n= 3\nz =\nw = a = b\n"
    ) == @[("x", "1"), ("y", "2"), ("w", "a = b")]
  test "the built-in file has what the pages use":
    let libs = parseLibraries(librariesBundle.data).toTable
    for name in [
      "leaflet-js", "leaflet-js-hash", "leaflet-css", "leaflet-css-hash", "tiles",
      "d3-js", "d3-js-hash", "plot-js", "plot-js-hash",
    ]:
      check libs.hasKey(name)
    for name in ["leaflet-js", "leaflet-css", "d3-js", "plot-js"]:
      check libs[name].startsWith("https://unpkg.com/")
        # (the only place the server's policy allows scripts and styles from)
      check libs[name & "-hash"].startsWith("sha256-") and
        libs[name & "-hash"].len == 7 + 44
    check libs["tiles"] == "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
  test "the policy is made from the file: the hosts it lists, and no others":
    let builtIn = contentPolicy(parseLibraries(librariesBundle.data))
    check "script-src 'self' 'unsafe-inline' https://unpkg.com;" in builtIn
    check "style-src 'self' 'unsafe-inline' https://unpkg.com;" in builtIn
    check "img-src 'self' data: https://unpkg.com https://tile.openstreetmap.org;" in
      builtIn
    check "connect-src 'self'" in builtIn and "default-src 'none'" in builtIn
    # (another CDN and another tile server, as the file's author may write them)
    let other = contentPolicy(
      parseLibraries(
        "leaflet-js = https://cdn.jsdelivr.net/npm/leaflet/dist/leaflet.js\nleaflet-css = https://cdn.jsdelivr.net/x.css\ntiles = http://tiles.example.org:8080/{z}/{x}/{y}.png\nleaflet-js-hash = sha256-abc\n"
      )
    )
    check "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net;" in other
    check "img-src 'self' data: https://cdn.jsdelivr.net http://tiles.example.org:8080;" in
      other
    check "unpkg" notin other and "openstreetmap" notin other and "*" notin other
  test "they are values for a template":
    let ctx = context(libraryValues("a-b = 1\nc = <&>\n"))
    check render("{{a-b}} {{c}} {{{c}}}", ctx) == "1 &lt;&amp;&gt; <&>"
