import std/[strutils, tables, unittest]
import nimchoo/serve/libraries
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
  test "they are values for a template":
    let ctx = context(libraryValues("a-b = 1\nc = <&>\n"))
    check render("{{a-b}} {{c}} {{{c}}}", ctx) == "1 &lt;&amp;&gt; <&>"
