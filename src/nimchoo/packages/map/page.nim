## The web page that shows the map: Leaflet (from a CDN, with the integrity hashes of the exact files, so a changed
## file is refused by the browser) drawing the frames of a GeoJSON file each that the server gives it.  The page is made of
## templates, each built in and kept in the cache's `system/templates/` (see bundle/unpack.nim), where the author can change them:
## `map.html` (the page and its script), `map.css` (the look of the page), `map-style.json` (what is common to all: the corner
## cutting) and **one style for each frame, which its provider ships** (`activities-map-routes.json`: colours, widths, offsets ...).
## The CSS and the styles are filled in first, with the palette's colours (`{{blue}}`...), then the styles are joined into one
## (each frame has its groups) and put into the page, which also gets the title, the names of the data files and the libraries
## (serve/libraries.nim).
##
## The things drawn are told apart by their `kind` property in the files (route, climb, heat, gate, effort); the heat is squares
## under the lines, the size that suits the zoom, shaded by how often the place was visited; the climbs are drawn thick and coloured by
## category, and the routes as thin, mostly transparent lines, so where many rides share a road
## the lines add up and glow.  A click on a line says which activity it is.  The page fetches each file, and if one cannot be
## read it says so and draws the rest.

import std/[json, options, strutils]
import ../bundle/unpack
import ./frames
import ../cache/cache
import ../web/libraries
import ../text/templating/templating
import ../ui/palette

{.push raises: [].}

const pageTemplate* = staticRead("page.html")
const templateBundle* = Bundle(name: "templates/map.html", data: pageTemplate)
const cssBundle* = Bundle(name: "templates/map.css", data: staticRead("page.css"))
const styleBundle* =
  Bundle(name: "templates/map-style.json", data: staticRead("page-style.json"))
  ## what is common to all the frames

func paletteValues*(): seq[(string, Value)] =
  ## The palette's colours as template values: {{white}} {{grey}} {{red}} {{green}} {{yellow}} {{blue}}.
  for c in Color:
    result.add ($c, text(hex(c)))

func nameOf(b: Bundle): string =
  ## "activities-map-routes.json": what the user sees in `system/templates/`.
  b.name.rsplit('/', maxsplit = 1)[^1]

proc parsed(
    bundle: Bundle, palette: seq[(string, Value)]
): JsonNode {.raises: [TemplateError].} =
  ## A style template filled in with the palette, as JSON (an object); a TemplateError that says what is wrong otherwise.
  var text: string
  try:
    text = render(resolve(bundle).data, context(palette))
  except TemplateError as e:
    raiseTemplate(bundle.nameOf & ": " & e.msg)
  try:
    result = parseJson(text)
  except JsonParsingError, ValueError, IOError, OSError:
    raiseTemplate(bundle.nameOf & " is not valid JSON: " & getCurrentExceptionMsg())
  if result.kind != JObject:
    raiseTemplate(bundle.nameOf & " is not a JSON object")

proc joinedStyle*(
    palette: seq[(string, Value)], all: seq[MapFrame]
): string {.raises: [TemplateError].} =
  ## The style of the page: `map-style.json` (which must have `smooth_rounds`) and the style of every frame, each with the
  ## groups the page reads (`styleKeys`), joined into one JSON object.  A frame whose style lacks what the page reads is a
  ## TemplateError that says which.
  let joined = parsed(styleBundle, palette)
  if joined{"smooth_rounds"}.isNil:
    raiseTemplate("map-style.json has no smooth_rounds")
  for f in all:
    let j = parsed(f.style, palette)
    for key in f.styleKeys:
      let at = key.split('.')
      if j{at[0], at[1]}.isNil:
        raiseTemplate(f.style.nameOf & " has no " & key)
    for group, value in j:
      joined[group] = value
  $joined

proc renderPage*(
    source: string,
    libs: seq[(string, Value)],
    files: seq[string],
    title: string,
    css = "",
    style = "{}",
): Option[string] {.raises: [TemplateError].} =
  ## The page from a template text, the libraries, the css and the style text (already filled in); none if any of `files`
  ## is not a GeoJSON file of the cache directory (which is what makes them safe to put in the page).  Pure.
  var names = newJArray()
  for f in files:
    if not isCacheFileName(f) or not f.endsWith(".geojson"):
      return none(string)
    names.add %f
  some(
    render(
      source,
      context(
        libs &
          @[
            ("title", text(title)),
            ("files", text($names.pretty.replace("</", "<\\/"))),
            ("css", text(css)),
            ("style", text(style.replace("</", "<\\/"))),
              # (in a script: the page ends at the first "</script")
          ]
      ),
    )
  )

proc pageHtml*(
    files: seq[string], title: string, all: seq[MapFrame]
): Option[string] {.raises: [TemplateError].} =
  ## The page for the GeoJSON files `files` (one for each frame drawn), from the templates and the libraries in use (the
  ## author's if they have put their own in the cache's `system/` part); `all` are the frames whose styles it carries.
  let palette = paletteValues()
  var css: string
  try:
    css = render(resolve(cssBundle).data, context(libraryValues() & palette))
  except TemplateError as e:
    raiseTemplate("map.css: " & e.msg)
  renderPage(
    resolve(templateBundle).data,
    libraryValues(),
    files,
    title,
    css,
    joinedStyle(palette, all),
  )
