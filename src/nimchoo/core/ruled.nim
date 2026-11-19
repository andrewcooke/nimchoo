## Tables with lines between the columns and a rule under the headings, as the program shows them in its usages and in
## `nch packages`:
##
##     subject    │ what is marked
##     ───────────┼───────────────────────────────
##     activities │ a day is marked when ...
##
## The lines are box-drawing characters, which the theme draws in its `lineStyle` wherever they are (`theme.nim`).  A cell
## is text, or pieces of text each in a style of the theme (`Cell`: a command's name in `cmd`), wrapped by words like text.
## Pure: the width to wrap to is given.

import std/[sequtils, strutils, unicode]

{.push raises: [].}

const minLastWidth* = 30
  ## the last column is never narrower than this, however narrow the width

type
  Run* = tuple[text, style: string]
    ## a piece of text in a style of the theme ("": the text around it)
  Cell* = seq[Run] ## what a cell holds, or a line of a table

func plainCell*(text: string): Cell =
  ## A cell of text in no style.
  @[(text, "")]

func cellText*(c: Cell): string =
  ## The text of a cell or a line, without its styles.
  for r in c:
    result.add r.text

func merged(c: Cell): Cell =
  ## The pieces side by side in the same style made one; empty ones dropped.
  for r in c:
    if r.text.len == 0:
      continue
    if result.len > 0 and result[^1].style == r.style:
      result[^1].text.add r.text
    else:
      result.add r

func stripped(c: Cell): Cell =
  ## Without the spaces at its end.
  result = c.merged
  while result.len > 0:
    result[^1].text = result[^1].text.strip(leading = false)
    if result[^1].text.len > 0:
      break
    result.setLen(result.len - 1)

func wrapCell*(cell: Cell, width: int): seq[Cell] =
  ## The cell broken into lines of at most `width` characters at spaces, as `wrap` breaks text (a longer word has a line of
  ## its own, a newline starts a new line, two spaces after a full stop stay two unless the line ends there); each word
  ## keeps its styles.
  var paragraphs: seq[seq[Cell]] =
    @[@[newSeq[Run]()]] # paragraphs of words, a word being pieces
  for r in cell:
    var piece = ""
    for ch in r.text:
      case ch
      of ' ':
        paragraphs[^1][^1].add (piece, r.style)
        piece = ""
        paragraphs[^1].add newSeq[Run]()
      of '\n':
        paragraphs[^1][^1].add (piece, r.style)
        piece = ""
        paragraphs.add @[newSeq[Run]()]
      else:
        piece.add ch
    paragraphs[^1][^1].add (piece, r.style)
  for words in paragraphs:
    var line: Cell
    var length = 0
    var started = false
    for word in words:
      let n = word.cellText.runeLen
      if not started:
        line = word
        length = n
        started = true
      elif length + 1 + n <= width:
        # (the space between two words in the same style is in it too: a phrase in a style is not broken by plain spaces)
        let between =
          if line.len > 0 and word.len > 0 and line[^1].style == word[0].style:
            line[^1].style
          else:
            ""
        line.add (" ", between)
        line.add word
        length += 1 + n
      else:
        result.add line.stripped
        line = word
        length = n
    result.add line.stripped

func ruledCells*(
    header: seq[string],
    rows: seq[seq[Cell]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
): seq[Cell] =
  ## The table, `indent` spaces in, as lines of styled pieces: every column but the last as wide as its widest cell (and
  ## its heading), those in `right` aligned to the right, and a column in `together` followed by the next with two spaces
  ## and no line (narrow columns that belong together: `L  U  B  T`); the last wrapped to what is left of `width` (but
  ## never narrower than `minLastWidth`), a newline in it starting a paragraph of its own.  Every row has as many cells as
  ## the header.
  doAssert header.len > 0 and rows.allIt(it.len == header.len), "a cell for each column"
  var widths = header.mapIt(it.runeLen)
  for r in rows:
    for k in 0 ..< r.high:
      widths[k] = max(widths[k], r[k].cellText.runeLen)
  func between(k: int): string =
    ## what follows column `k`
    if k in together: "  " else: " │ "

  var column = indent
  for k in 0 ..< header.high:
    column += widths[k] + between(k).runeLen
  let lastWidth = max(minLastWidth, width - column)
  var lines: seq[tuple[lead, text: Cell]]
  var used = 0 # how wide the last column is
  for r in @[header.mapIt(plainCell(it))] & rows:
    var lead, blank: Cell
    for k in 0 ..< r.high:
      let text = r[k].cellText
      let room = " ".repeat(max(0, widths[k] - text.runeLen))
      if k in right:
        lead.add (room, "")
        lead.add r[k]
      else:
        lead.add r[k]
        lead.add (room, "")
      lead.add (between(k), "")
      blank.add (" ".repeat(widths[k]) & between(k), "")
    for i, piece in wrapCell(r[^1], lastWidth):
      lines.add ((if i == 0: lead else: blank), piece)
      used = max(used, piece.cellText.runeLen)
  for i, l in lines:
    result.add stripped(@[(" ".repeat(indent), "")] & l.lead & l.text)
    if i == 0 and header.len > 1:
      # the rule under the headings: the headings' line drawn over, crossed where a line divides the columns
      var rule = ""
      for r in l.lead.cellText.runes:
        rule.add(if r == "│".runeAt(0): "┼" else: "─")
      result.add plainCell(" ".repeat(indent) & rule & "─".repeat(used))

func ruledLines*(
    header: seq[string],
    rows: seq[seq[string]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
): seq[string] =
  ## The same, for cells of text in no style, as lines of text.
  ruledCells(
    header, rows.mapIt(it.mapIt(plainCell(it))), width, indent, right, together
  )
    .mapIt(it.cellText)
