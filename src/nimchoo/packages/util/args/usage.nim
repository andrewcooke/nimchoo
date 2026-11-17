## The option list of a command's usage text, made from the descriptions of its options (`OptDoc`), so that it cannot
## differ from what the parser accepts; and the tables a usage shows of what the registry holds (`tableLines`: the subjects
## and frames of `map`).  A command's usage is its synopsis and introduction, written by hand, then
## this list, then any closing prose.  Pure: the width to wrap to is given.

import std/[sequtils, strutils]
import ../../../core/wrap
import ./args
export wrap

{.push raises: [].}

const
  indent = 2
  gap = 2
  maxLabel = 24 ## a longer label has its help on the next line
  minHelpWidth = 30

func label(d: OptDoc): string =
  ## The names and the value, indented two more for each level (an option that goes with the one before it).
  result = " ".repeat(2 * d.level) & d.names.join(", ")
  if d.metavar.len > 0:
    result.add(
      if d.arity == aOptional:
        " [" & d.metavar & "]"
      else:
        " " & d.metavar
    )

func optionLines*(docs: seq[OptDoc], width: int): seq[string] =
  ## The lines for the options: two spaces, the names and the value, the help in a column, wrapped to `width`.
  var labelWidth = 0
  for d in docs:
    let n = label(d).len
    if n <= maxLabel:
      labelWidth = max(labelWidth, n)
  let column = indent + labelWidth + gap
  let helpWidth = max(minHelpWidth, width - column)
  for d in docs:
    let l = label(d)
    let help = wrap(d.help, helpWidth)
    if l.len > maxLabel:
      result.add " ".repeat(indent) & l
      for h in help:
        result.add " ".repeat(column) & h
    else:
      for i, h in help:
        if i == 0:
          result.add (
            " ".repeat(indent) & l.alignLeft(labelWidth) & " ".repeat(gap) & h
          ).strip(leading = false)
        else:
          result.add " ".repeat(column) & h
      if help.len == 0:
        result.add " ".repeat(indent) & l

func tableLines*(header: seq[string], rows: seq[seq[string]], width: int): seq[string] =
  ## A table for a usage text, indented like the options: every column but the last as wide as its widest cell (and its
  ## heading), the last wrapped to what is left of `width` (but never narrower than the help of an option), two spaces
  ## between columns.  Every row has as many cells as the header.
  doAssert header.len > 0 and rows.allIt(it.len == header.len), "a cell for each column"
  var widths = header.mapIt(it.len)
  for r in rows:
    for k in 0 ..< r.high:
      widths[k] = max(widths[k], r[k].len)
  var column = indent
  for k in 0 ..< header.high:
    column += widths[k] + gap
  let lastWidth = max(minHelpWidth, width - column)
  for r in @[header] & rows:
    var lead = " ".repeat(indent)
    for k in 0 ..< r.high:
      lead.add r[k].alignLeft(widths[k]) & " ".repeat(gap)
    for i, piece in wrap(r[^1], lastWidth):
      result.add (if i == 0: lead else: " ".repeat(column)) & piece
