## Tables with lines between the columns and a rule under the headings, as the program shows them in its usages and in
## `nch packages`:
##
##     subject    │ what is marked
##     ───────────┼───────────────────────────────
##     activities │ a day is marked when ...
##
## The lines are box-drawing characters, which the theme draws in its `lineStyle` wherever they are (`theme.nim`).  A cell
## is a styled line (`line.nim`: a command's name in `cmd`), wrapped by words like text.
## Pure: the width to wrap to is given.

import std/[sequtils, strutils, unicode]
import ./line

{.push raises: [].}

const minLastWidth* = 30
  ## the last column is never narrower than this, however narrow the width

func ruled*(
    header: seq[string],
    rows: seq[seq[Line]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
): seq[Line] =
  ## The table, `indent` spaces in, as styled lines: every column but the last as wide as its widest cell (and
  ## its heading), those in `right` aligned to the right, and a column in `together` followed by the next with two spaces
  ## and no line (narrow columns that belong together: `L  U  B  T`); the last wrapped to what is left of `width` (but
  ## never narrower than `minLastWidth`), a newline in it starting a paragraph of its own.  Every row has as many cells as
  ## the header.
  doAssert header.len > 0 and rows.allIt(it.len == header.len), "a cell for each column"
  var widths = header.mapIt(it.runeLen)
  for r in rows:
    for k in 0 ..< r.high:
      widths[k] = max(widths[k], r[k].width)
  func between(k: int): string =
    ## what follows column `k`
    if k in together: "  " else: " │ "

  var column = indent
  for k in 0 ..< header.high:
    column += widths[k] + between(k).runeLen
  let lastWidth = max(minLastWidth, width - column)
  var lines: seq[tuple[lead, text: Line]]
  var used = 0 # how wide the last column is
  for r in @[header.mapIt(plain(it))] & rows:
    var lead, blank: Line
    for k in 0 ..< r.high:
      let room = " ".repeat(max(0, widths[k] - r[k].width))
      if k in right:
        lead.add span(room)
        lead.add r[k]
      else:
        lead.add r[k]
        lead.add span(room)
      lead.add span(between(k))
      blank.add span(" ".repeat(widths[k]) & between(k))
    for i, piece in r[^1].wrapped(lastWidth):
      lines.add ((if i == 0: lead else: blank), piece)
      used = max(used, piece.width)
  for i, l in lines:
    result.add stripped(@[span(" ".repeat(indent))] & l.lead & l.text)
    if i == 0 and header.len > 1:
      # the rule under the headings: the headings' line drawn over, crossed where a line divides the columns
      var rule = ""
      for r in l.lead.text.runes:
        rule.add(if r == "│".runeAt(0): "┼" else: "─")
      result.add plain(" ".repeat(indent) & rule & "─".repeat(used))
