## Tables with lines between the columns and a rule under the headings, as the program shows them in its usages and in
## `nch packages`:
##
##     subject    │ what is marked
##     ───────────┼───────────────────────────────
##     activities │ a day is marked when ...
##
## The lines are box-drawing characters, which the theme draws in its `lineStyle` wherever they are (`theme.nim`).  A cell
## is a styled line (`line.nim`: a command's name in `code`), wrapped by words like text.
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
    narrow = 0,
    alternate = true,
): seq[RuledLine] =
  ## The table, `indent` spaces in, as styled lines, each with the row it shows: every column but the last as wide as its
  ## widest cell (and its heading), or wrapped to `narrow` if that is not 0; those in `right` aligned to the right (the last
  ## too), and a column in `together` followed by the next with two spaces and no line (narrow columns that belong
  ## together: `L  U  B  T`); the last wrapped to what is left of `width` (but never narrower than `minLastWidth`), a
  ## newline in it starting a paragraph of its own.  Every row has as many cells as the header (the headings are styled
  ## lines: a column about the selection in its style).  A row with styles in `rowStyles` (by row; none: plain) is in them
  ## all through, the lines between its columns too, outside the styles of its cells: a row of the selection is one band.
  ## Headings that are all empty are not shown (a list of labels and values: `nch packages NAME`).  With `alternate` (as every table
  ## is unless it says otherwise), every other row is in the `alt` version of its styles (`line.alternated`): rows told
  ## apart.
  doAssert header.len > 0 and rows.allIt(it.len == header.len), "a cell for each column"
  doAssert rowStyles.len in [0, rows.len], "styles for every row, or none"
  let headed = header.anyIt(it.width > 0) # (no headings: no line for them, and no rule)
  let all = (if headed: @[header] else: @[]) & rows
  let first = (if headed: -1 else: 0) # (the row the first of `all` is)
  func cellLines(cell: Line): seq[Line] =
    if narrow > 0:
      cell.wrapped(narrow)
    else:
      @[cell]

  var widths = newSeq[int](header.len)
  for r in all:
    for k in 0 ..< r.high:
      for l in cellLines(r[k]):
        widths[k] = max(widths[k], l.width)
  func between(k: int): string =
    ## what follows column `k`
    if k in together: "  " else: " │ "

  var column = indent
  for k in 0 ..< header.high:
    column += widths[k] + between(k).runeLen
  let lastWidth = max(minLastWidth, width - column)
  var lastColumn = 0
    # (for a last column to the right: as wide as its widest cell, if that fits)
  for r in all:
    lastColumn = max(lastColumn, r[^1].width)
  lastColumn = min(lastColumn, lastWidth)
  var lines: seq[tuple[row: int, lead, text: Line]]
  var used = 0 # how wide the last column is
  for n, r in all:
    var cells: seq[seq[Line]]
    for k in 0 ..< r.high:
      cells.add cellLines(r[k])
    cells.add r[^1].wrapped(lastWidth)
    let lastEmpty = r[^1].width == 0
      # (then nothing follows the last line between columns)
    for i in 0 ..< cells.mapIt(it.len).max:
      var lead: Line
      for k in 0 ..< r.high:
        let piece = (if i < cells[k].len: cells[k][i] else: @[])
        let room = span(" ".repeat(max(0, widths[k] - piece.width)))
        lead.add(
          if k in right:
            @[room] & piece
          else:
            piece & @[room]
        )
        if not (lastEmpty and k == r.high - 1):
          lead.add span(between(k))
      var text = (if i < cells[^1].len: cells[^1][i] else: @[])
      if header.high in right and text.width > 0:
        text = @[span(" ".repeat(max(0, lastColumn - text.width)))] & text
      lines.add (n + first, lead, text)
      used = max(used, text.width)
  for i, l in lines:
    var line = stripped(l.lead & l.text)
    if l.row >= 0 and rowStyles.len > 0 and rowStyles[l.row].len > 0:
      for s in line.mitems:
        s.styles = rowStyles[l.row] & s.styles
    if alternate and l.row >= 0 and l.row mod 2 == 1:
      line = line.alternated
    result.add (l.row, (if indent > 0: @[span(" ".repeat(indent))] else: @[]) & line)
    if l.row == -1 and header.len > 1 and (i == lines.high or lines[i + 1].row != -1):
      # the rule under the headings: crossed where a line divides the columns, as wide as the table
      var rule = ""
      for k in 0 ..< header.high:
        if used == 0 and k == header.high - 1:
          # (the last column is empty all through: no line before it)
          rule.add "─".repeat(widths[k])
        else:
          rule.add "─".repeat(widths[k]) &
            (if k in together: "──" else: "─┼─")
      result.add (-1, plain(" ".repeat(indent) & rule & "─".repeat(used)))

func ruledRows*(
    header: seq[string],
    rows: seq[seq[Line]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
    rowStyles: seq[seq[StyleName]] = @[],
    narrow = 0,
    alternate = true,
): seq[RuledLine] =
  ## The same, with headings of plain text.
  ruledRows(
    header.mapIt(plain(it)),
    rows,
    width,
    indent,
    right,
    together,
    rowStyles,
    narrow,
    alternate,
  )

func ruled*(
    header: seq[string],
    rows: seq[seq[Line]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
    rowStyles: seq[seq[StyleName]] = @[],
    narrow = 0,
    alternate = true,
): seq[Line] =
  ## The table as `ruledRows()` makes it, without saying which row each line shows.
  ruledRows(header, rows, width, indent, right, together, rowStyles, narrow, alternate)
    .mapIt(it.line)

func ruled*(
    header: seq[string],
    rows: seq[seq[string]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
    narrow = 0,
    alternate = true,
): seq[Line] =
  ## A table of plain cells.
  ruled(
    header,
    rows.mapIt(it.mapIt(plain(it))),
    width,
    indent,
    right,
    together,
    narrow = narrow,
    alternate = alternate,
  )
