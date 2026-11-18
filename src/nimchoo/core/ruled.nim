## Tables with lines between the columns and a rule under the headings, as the program shows them in its usages and in
## `nch packages`:
##
##     subject    │ what is marked
##     ───────────┼───────────────────────────────
##     activities │ a day is marked when ...
##
## The lines are box-drawing characters, which the theme draws in its `lineStyle` wherever they are (`theme.nim`).  Pure:
## the width to wrap to is given.

import std/[sequtils, strutils, unicode]
import ./wrap

{.push raises: [].}

const minLastWidth* = 30
  ## the last column is never narrower than this, however narrow the width

func padded(s: string, width: int, right: bool): string =
  ## `s` and spaces to `width` characters (not bytes), on the left if `right`.
  let room = " ".repeat(max(0, width - s.runeLen))
  if right:
    room & s
  else:
    s & room

func ruledLines*(
    header: seq[string],
    rows: seq[seq[string]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
): seq[string] =
  ## The table, `indent` spaces in: every column but the last as wide as its widest cell (and its heading), those in
  ## `right` aligned to the right, and a column in `together` followed by the next with two spaces and no line (narrow
  ## columns that belong together: `L  U  B  T`); the last wrapped to what is left of `width` (but never narrower than
  ## `minLastWidth`), a newline in it starting a paragraph of its own.  Every row has as many cells as the header.
  doAssert header.len > 0 and rows.allIt(it.len == header.len), "a cell for each column"
  var widths = header.mapIt(it.runeLen)
  for r in rows:
    for k in 0 ..< r.high:
      widths[k] = max(widths[k], r[k].runeLen)
  func between(k: int): string =
    ## what follows column `k`
    if k in together: "  " else: " │ "

  var column = indent
  for k in 0 ..< header.high:
    column += widths[k] + between(k).runeLen
  let lastWidth = max(minLastWidth, width - column)
  var lines: seq[tuple[lead: string, text: string]]
  var used = 0 # how wide the last column is
  for r in @[header] & rows:
    var lead = ""
    var blank = ""
    for k in 0 ..< r.high:
      lead.add padded(r[k], widths[k], k in right) & between(k)
      blank.add " ".repeat(widths[k]) & between(k)
    var first = true
    for paragraph in r[^1].split('\n'):
      for piece in wrap(paragraph, lastWidth):
        lines.add ((if first: lead else: blank), piece)
        used = max(used, piece.runeLen)
        first = false
    if first: # (an empty last cell)
      lines.add (lead, "")
  for i, l in lines:
    result.add (" ".repeat(indent) & l.lead & l.text).strip(leading = false)
    if i == 0 and header.len > 1:
      # the rule under the headings: the headings' line drawn over, crossed where a line divides the columns
      var rule = ""
      for r in l.lead.runes:
        rule.add(if r == "│".runeAt(0): "┼" else: "─")
      result.add " ".repeat(indent) & rule & "─".repeat(used)
