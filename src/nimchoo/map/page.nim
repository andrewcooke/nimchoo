## The web page that shows the map: Leaflet (from a CDN, with the integrity hashes of the exact files, so a changed
## file is refused by the browser) drawing the routes and climbs of a GeoJSON file that the server gives it.  The page is
## made of three templates, each built in and kept in the cache's `system/templates/` (see bundle/unpack.nim), where
## the author can change them: `map.html` (the page and its script), `map.css` (the look of the page) and
## `map-style.json` (how routes and climbs are drawn: colours, widths, offsets).  The CSS and the style are filled in
## first, with the palette's colours (`{{blue}}`...), then put into the page, which also gets the title, the name of the
## data and the libraries (serve/libraries.nim).
##
## The routes and the climbs are told apart by their `kind` property in the file; the climbs are drawn thick and coloured by
## category, and the routes as thin, mostly transparent lines, so where many rides share a road
## the lines add up and glow.  A click on a line says which activity it is.

import std/[json, options, strutils]
import ../bundle/unpack
import ../cache
import ../serve/libraries
import ../templating
import ../ui/palette

{.push raises: [].}

const pageTemplate* = staticRead("page.html")
const templateBundle* = Bundle(name: "templates/map.html", data: pageTemplate)
const cssBundle* = Bundle(name: "templates/map.css", data: staticRead("page.css"))
const styleBundle* =
  Bundle(name: "templates/map-style.json", data: staticRead("page-style.json"))

const requiredStyle = [
  ("routes", "color"),
  ("routes", "weight"),
  ("routes", "opacity"),
  ("routes", "spread_m"),
  ("climbs", "color"),
  ("climbs", "weight"),
  ("climbs", "opacity"),
  ("climbs", "gap_px"),
  ("climbs", "lane_px"),
]

func paletteValues*(): seq[(string, Value)] =
  ## The palette's colours as template values: {{white}} {{grey}} {{red}} {{green}} {{yellow}} {{blue}}.
  for c in Color:
    result.add ($c, text(hex(c)))

proc checkedStyle*(styleText: string): string {.raises: [TemplateError].} =
  ## The style text if it is JSON with what the page reads; else a TemplateError that says what is wrong.
  var j: JsonNode
  try:
    j = parseJson(styleText)
  except CatchableError:
    raiseTemplate("map-style.json is not valid JSON: " & getCurrentExceptionMsg())
  for (group, key) in requiredStyle:
    if j{group, key}.isNil:
      raiseTemplate("map-style.json has no " & group & "." & key)
  if j{"smooth_rounds"}.isNil:
    raiseTemplate("map-style.json has no smooth_rounds")
  styleText

proc renderPage*(
    source: string,
    libs: seq[(string, Value)],
    dataName, title: string,
    css = "",
    style = "{}",
): Option[string] {.raises: [TemplateError].} =
  ## The page from a template text, the libraries, and the css and the style text (already filled in); none if
  ## `dataName` is not a GeoJSON file of the cache directory (which is what makes it safe to put in the page).  Pure.
  if not isCacheFileName(dataName) or not dataName.endsWith(".geojson"):
    return none(string)
  some(
    render(
      source,
      context(
        libs &
          @[
            ("title", text(title)),
            ("data", text(dataName)),
            ("css", text(css)),
            ("style", text(style.replace("</", "<\\/"))), # (in a script: the page ends at the first "</script")
          ]
      ),
    )
  )

proc pageHtml*(dataName, title: string): Option[string] {.raises: [TemplateError].} =
  ## The page for the GeoJSON file `dataName`, from the templates and the libraries in use (the author's if they have
  ## put their own in the cache's `system/` part).
  let palette = paletteValues()
  var css, style: string
  try:
    css = render(resolve(cssBundle).data, context(libraryValues() & palette))
  except TemplateError as e:
    raiseTemplate("map.css: " & e.msg)
  try:
    style = checkedStyle(render(resolve(styleBundle).data, context(palette)))
  except TemplateError as e:
    raiseTemplate(
      if e.msg.startsWith("map-style.json") or e.msg.startsWith("line ") == false:
        e.msg
      else:
        "map-style.json: " & e.msg
    )
  renderPage(resolve(templateBundle).data, libraryValues(), dataName, title, css, style)
