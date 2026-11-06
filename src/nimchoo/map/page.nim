## The web page that shows a heat map: Leaflet (from a CDN, with the integrity hashes of the exact
## files, so a changed file is refused by the browser) drawing the routes of a GeoJSON file that the
## server gives it.  The page is a template (page.html, built in and kept in the cache's
## `system/templates/`, see bundle/unpack.nim) filled in with the title, the name of the data and the
## libraries (serve/libraries.nim).
##
## The routes and the climbs are told apart by their `kind` property in the file; the climbs are drawn thick and coloured by
## category, and the routes as thin, mostly transparent lines, so where many rides share a road
## the lines add up and glow.  A click on a line says which activity it is.

import std/[options, strutils]
import ../bundle/unpack
import ../cache
import ../serve/libraries
import ../templating

{.push raises: [].}

const pageTemplate* = staticRead("page.html")
const templateBundle* = Bundle(name: "templates/map.html", data: pageTemplate)

proc renderPage*(source: string, libs: seq[(string, Value)], dataName, title: string): Option[string]
    {.raises: [TemplateError].} =
  ## The page from a template text and the libraries; none if `dataName` is not a GeoJSON file of the
  ## cache directory (which is what makes it safe to put in the page).  Pure.
  if not isCacheFileName(dataName) or not dataName.endsWith(".geojson"):
    return none(string)
  some(render(source, context(libs & @[("title", text(title)), ("data", text(dataName))])))

proc pageHtml*(dataName, title: string): Option[string] {.raises: [TemplateError].} =
  ## The page for the GeoJSON file `dataName`, from the template and the libraries in use (the
  ## author's if they have put their own in the cache's `system/` part).
  renderPage(resolve(templateBundle).data, libraryValues(), dataName, title)
