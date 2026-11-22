## The libraries the web pages load from a CDN (leaflet, d3, plot) and their integrity hashes, as
## `name = value` lines in libraries.cdn.  The file is built into the program and kept in the cache's
## `system/` part (see bundle/unpack.nim), where the author can change it to use another version.
## Every name in it can be used in a page template.

import std/[sequtils, strutils]
import ../bundle/unpack
import ../text/templating/templating

{.push raises: [].}

const librariesBundle* =
  Bundle(name: "libraries.cdn", data: staticRead("libraries.cdn"))

func parseLibraries*(text: string): seq[(string, string)] =
  ## The `name = value` lines (comments start with #, and lines that are not a name and a value
  ## are left out).
  for line in text.splitLines:
    let l = line.strip
    if l.len == 0 or l[0] == '#':
      continue
    let eq = l.find('=')
    if eq < 1:
      continue
    let name = l[0 ..< eq].strip
    let value = l[eq + 1 .. ^1].strip
    if name.len > 0 and value.len > 0:
      result.add (name, value)

proc libraries*(): seq[(string, string)] =
  ## The libraries file in use, as name and value.
  parseLibraries(resolve(librariesBundle).data)

func origin(url: string): string =
  ## "https://unpkg.com" of "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"; "" if it is not an http(s) address.
  for scheme in ["https://", "http://"]:
    if url.startsWith(scheme):
      let hostEnd = url.find('/', scheme.len)
      return
        if hostEnd < 0:
          url
        else:
          url[0 ..< hostEnd]

func contentPolicy*(libs: seq[(string, string)]): string =
  ## The Content-Security-Policy of the pages, made from the libraries file in use: scripts only from the origins of the
  ## `-js` entries, styles from those of the `-css` entries, images from `'self'`, data and the origin of every address (the
  ## tiles, and what the styles load).  So that pointing a library or the tiles at another server works, and nothing else is
  ## allowed.
  var scripts, styles, images: seq[string]
  for (name, value) in libs:
    let o = origin(value)
    if o.len == 0:
      continue
    if name.endsWith("-js") and o notin scripts:
      scripts.add o
    if name.endsWith("-css") and o notin styles:
      styles.add o
    if o notin images:
      images.add o
  func sources(origins: seq[string], more: string): string =
    (@["'self'"] & @[more] & origins).filterIt(it.len > 0).join(" ")

  "default-src 'none'; script-src " & sources(scripts, "'unsafe-inline'") &
    "; style-src " & sources(styles, "'unsafe-inline'") & "; img-src " &
    sources(images, "data:") &
    "; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

func libraryValues*(content: string): seq[(string, Value)] =
  ## ... as the values of a template.
  for (k, v) in parseLibraries(content):
    result.add (k, text(v))

proc libraryValues*(): seq[(string, Value)] =
  ## The values of the libraries file in use (see above).
  libraryValues(resolve(librariesBundle).data)
