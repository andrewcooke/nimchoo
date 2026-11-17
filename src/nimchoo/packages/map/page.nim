## The web page that shows the map: Leaflet (from a CDN, with the integrity hashes of the exact files, so a changed
## file is refused by the browser) drawing the frames of a GeoJSON file each that the server gives it.  The page is made of
## templates, each built in and kept in the cache's `system/templates/` (see bundle/unpack.nim), where the author can change them:
## `map.html` (the page and its script, which knows no frame), `map.css` (the look of the page), `map-style.json` (what is common
## to all: the corner cutting) and, **for each frame, a style and perhaps a drawing that its provider ships**
## (`activities-map-routes.json`: colours, widths, offsets ...; `activities-map-routes.js`: how they are drawn; see `frames.nim`).
## The CSS and the styles are filled in first, with the palette's colours (`{{blue}}`...), then put into the page with the drawings
## of the frames drawn, which also gets the title, the list of the frames (each with its file, its style and the name of its
## drawing) and the libraries (serve/libraries.nim).  The page fetches each file, and if one cannot be read or drawn it says so
## and draws the rest.

import std/[json, options, sequtils, strformat, strutils]
import ../bundle/unpack
import ./frames
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

type PageFrame* = object ## A frame as the page gets it.
  name*: string
    ## "routes": the page fetches its data from its own address with `?frame=routes`
  summary*: string ## what it is, beside its box in the list of frames
  shown*: bool ## ticked when the page opens
  style*: JsonNode ## its style, filled in
  drawer*: string
    ## the name of its drawing ("activities-map-routes"); "": the generic one

func stemOf(b: Bundle): string =
  ## "activities-map-routes": a drawing's name, from its file's.
  b.nameOf.rsplit('.', maxsplit = 1)[0]

proc commonStyle*(palette: seq[(string, Value)]): JsonNode {.raises: [TemplateError].} =
  ## `map-style.json`, filled in; it must have `smooth_rounds`.
  result = parsed(styleBundle, palette)
  if result{"smooth_rounds"}.isNil:
    raiseTemplate("map-style.json has no smooth_rounds")

proc frameStyle*(
    f: MapFrame, palette: seq[(string, Value)]
): JsonNode {.raises: [TemplateError].} =
  ## The style of a frame, filled in, with every key its drawing reads (`styleKeys`); a TemplateError that says which file
  ## otherwise.
  result = parsed(f.style, palette)
  for key in f.styleKeys:
    if result{key}.isNil:
      raiseTemplate(fmt"{f.style.nameOf} has no {key}")

proc drawerText*(b: Bundle): string {.raises: [TemplateError].} =
  ## The drawing of a frame, as the page will hold it (from the cache's copy, which the author may have changed).  It goes into
  ## the page's script, so a closing script tag in it would end the script there: that is a TemplateError that names the file.
  result = resolve(b).data
  if "</script" in result.toLowerAscii:
    raiseTemplate(fmt"{b.nameOf} has a closing script tag in it")

proc renderPage*(
    source: string,
    libs: seq[(string, Value)],
    frames: seq[PageFrame],
    title: string,
    css = "",
    common = "{}",
    drawers: seq[(string, string)] = @[],
): string {.raises: [TemplateError].} =
  ## The page from a template text, the libraries, the frames, the css, the common style and the drawings (each a name and the
  ## text of its function; already checked).  Pure.
  var list = newJArray()
  for f in frames:
    list.add %*{
      "name": f.name,
      "summary": f.summary,
      "shown": f.shown,
      "style": f.style,
      "drawer": f.drawer,
    }
  var code = ""
  for (name, js) in drawers:
    code.add "  drawers[" & escapeJson(name) & "] = (\n" & js.strip & "\n  );\n"
  render(
    source,
    context(
      libs &
        @[
          ("title", text(title)),
          ("frames", text(($list).replace("</", "<\\/"))),
          ("css", text(css)),
          ("style", text(common.replace("</", "<\\/"))),
            # (in a script: the page ends at the first "</script")
          ("drawers", text(code)),
        ]
    ),
  )

proc pageHtml*(
    listed: seq[tuple[frame: MapFrame, shown: bool]], subject, title: string
): string {.raises: [TemplateError].} =
  ## The page of a subject: every frame of it (`listed`, those to show ticked), from the templates, the styles and drawings of
  ## the frames and the libraries in use (the author's if they have put their own in the cache's `system/` part).  The page
  ## fetches the data of each frame it shows from its own address.
  let palette = paletteValues()
  var css: string
  try:
    css = render(resolve(cssBundle).data, context(libraryValues() & palette))
  except TemplateError as e:
    raiseTemplate("map.css: " & e.msg)
  var frames: seq[PageFrame]
  var drawers: seq[(string, string)]
  for (f, shown) in listed:
    var drawer = ""
    if f.script.isSome:
      drawer = f.script.get.stemOf
      if drawers.allIt(it[0] != drawer):
        drawers.add (drawer, drawerText(f.script.get))
    frames.add PageFrame(
      name: f.name,
      summary: f.summary,
      shown: shown,
      style: frameStyle(f, palette),
      drawer: drawer,
    )
  renderPage(
    resolve(templateBundle).data,
    libraryValues(),
    frames,
    title & " of " & subject,
    css,
    $commonStyle(palette),
    drawers,
  )
