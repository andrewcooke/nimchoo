## The libraries the web pages load from a CDN (leaflet, d3, plot) and their integrity hashes, as
## `name = value` lines in libraries.txt.  The file is built into the program and kept in the cache's
## `system/` part (see bundle/unpack.nim), where the author can change it to use another version.
## Every name in it can be used in a page template.

import std/[strutils]
import ../bundle/unpack
import ../templating

{.push raises: [].}

const librariesBundle* = Bundle(name: "libraries.txt", data: staticRead("libraries.txt"))

func parseLibraries*(text: string): seq[(string, string)] =
  ## The `name = value` lines (comments start with #, and lines that are not a name and a value
  ## are left out).
  for line in text.splitLines:
    let l = line.strip
    if l.len == 0 or l[0] == '#': continue
    let eq = l.find('=')
    if eq < 1: continue
    let name = l[0 ..< eq].strip
    let value = l[eq + 1 .. ^1].strip
    if name.len > 0 and value.len > 0: result.add (name, value)

func libraryValues*(content: string): seq[(string, Value)] =
  ## ... as the values of a template.
  for (k, v) in parseLibraries(content): result.add (k, text(v))

proc libraryValues*(): seq[(string, Value)] =
  ## The values of the libraries file in use (see above).
  libraryValues(resolve(librariesBundle).data)
