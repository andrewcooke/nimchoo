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

type RuledLine* = tuple[row: int, line: Line]
  ## a line of a table and the row it shows (-1: the headings or the rule under them)

func ruledRows*(
    header: seq[Line],
    rows: seq[seq[Line]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
    rowStyles: seq[seq[StyleName]] = @[],
): seq[RuledLine] =
  ## The table, `indent` spaces in, as styled lines, each with the row it shows: every column but the last as wide as its
  ## widest cell (and its heading), those in `right` aligned to the right (the last too), and a column in `together` followed by the next
  ## with two spaces and no line (narrow columns that belong together: `L  U  B  T`); the last wrapped to what is left of
  ## `width` (but never narrower than `minLastWidth`), a newline in it starting a paragraph of its own.  Every row has as
  ## many cells as the header (the headings are styled lines: a column about the selection in its style).  A row with styles in `rowStyles` (by row; none: plain) is in them all through, the lines
  ## between its columns too, outside the styles of its cells: a row of the selection is one band.  Headings that are all
  ## empty are not shown (a list of labels and values: `nch packages NAME`).
  doAssert header.len > 0 and rows.allIt(it.len == header.len), "a cell for each column"
  doAssert rowStyles.len in [0, rows.len], "styles for every row, or none"
  var widths = header.mapIt(it.width)
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
  var lastColumn = header[^1].width
    # (for a last column to the right: as wide as its widest cell, if that fits)
  for r in rows:
    lastColumn = max(lastColumn, r[^1].width)
  lastColumn = min(lastColumn, lastWidth)
  var lines: seq[tuple[row: int, lead, text: Line]]
  var ruleLead = ""
    # (the headings' line, every line between columns in it, for the rule)
  for k in 0 ..< header.high:
    ruleLead.add " ".repeat(widths[k]) & between(k)
  var used = 0 # how wide the last column is
  let headed = header.anyIt(it.width > 0) # (no headings: no line for them, and no rule)
  for n, r in @[header] & rows:
    if n == 0 and not headed:
      continue
    var lead, blank: Line
    let lastEmpty = r[^1].width == 0
      # (then nothing follows the last line between columns)
    for k in 0 ..< r.high:
      let room = " ".repeat(max(0, widths[k] - r[k].width))
      if k in right:
        lead.add span(room)
        lead.add r[k]
      else:
        lead.add r[k]
        lead.add span(room)
      if not (lastEmpty and k == r.high - 1):
        lead.add span(between(k))
      blank.add span(" ".repeat(widths[k]) & between(k))
    for i, wrapped in r[^1].wrapped(lastWidth):
      let piece =
        if header.high in right:
          @[span(" ".repeat(max(0, lastColumn - wrapped.width)))] & wrapped
        else:
          wrapped
      lines.add (n - 1, (if i == 0: lead else: blank), piece)
      used = max(used, piece.width)
  for i, l in lines:
    var line = stripped(l.lead & l.text)
    if l.row >= 0 and rowStyles.len > 0 and rowStyles[l.row].len > 0:
      for s in line.mitems:
        s.styles = rowStyles[l.row] & s.styles
    result.add (l.row, @[span(" ".repeat(indent))] & line)
    if i == 0 and headed and header.len > 1:
      # the rule under the headings: the headings' line drawn over, crossed where a line divides the columns
      var rule = ""
      let lead =
        if used == 0: # (the last column is empty all through: no line before it)
          ruleLead[0 ..< ruleLead.len - between(header.high - 1).len]
        else:
          ruleLead
      for r in lead.runes:
        rule.add(if r == "│".runeAt(0): "┼" else: "─")
      result.add (-1, plain(" ".repeat(indent) & rule & "─".repeat(used)))

func ruledRows*(
    header: seq[string],
    rows: seq[seq[Line]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
    rowStyles: seq[seq[StyleName]] = @[],
): seq[RuledLine] =
  ## The same, with headings of plain text.
  ruledRows(header.mapIt(plain(it)), rows, width, indent, right, together, rowStyles)

func ruled*(
    header: seq[string],
    rows: seq[seq[Line]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
    rowStyles: seq[seq[StyleName]] = @[],
): seq[Line] =
  ## The table as `ruledRows()` makes it, without saying which row each line shows.
  ruledRows(header, rows, width, indent, right, together, rowStyles).mapIt(it.line)

func ruled*(
    header: seq[string],
    rows: seq[seq[string]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
): seq[Line] =
  ## A table of plain cells.
  ruled(header, rows.mapIt(it.mapIt(plain(it))), width, indent, right, together)
