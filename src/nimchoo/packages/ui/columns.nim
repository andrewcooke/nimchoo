## Lining up the cells of a table in columns: the one function every listing uses.

import std/[strutils, unicode]

{.push raises: [].}

func columns*(rows: seq[seq[string]], right: set[0 .. 31]): seq[string] =
  ## The rows with their cells lined up (two spaces between), those in `right` to the right.
  var widths: seq[int]
  for row in rows:
    for c, cell in row:
      if c >= widths.len:
        widths.add 0
      widths[c] = max(widths[c], cell.runeLen)
  for row in rows:
    var line = ""
    for c, cell in row:
      if c > 0:
        line.add "  "
      let pad = repeat(' ', widths[c] - cell.runeLen)
      line.add (if c <= 31 and c in right: pad & cell
      else: cell & pad)
    result.add line.strip(leading = false)
