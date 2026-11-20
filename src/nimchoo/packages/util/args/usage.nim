## The option list of a command's usage text, made from the descriptions of its options (`OptDoc`), so that it cannot
## differ from what the parser accepts; and the tables a usage shows of what the registry holds (`tableLines`: the subjects
## and frames of `map`).  A command's usage is styled lines (`core/line.nim`): its synopsis and introduction, written by
## hand, then this list, then any closing prose, put together by `usageOf`.  Pure: the width to wrap to is given.

import std/[sequtils, strutils]
import ../../../core/[line, ruled, wrap]
import ./args
export wrap, line

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

func synopsisLines*(text: string): seq[Line] =
  ## The synopsis of a usage: "usage:" in `em`, and each command line in `code` (the indent before the others is not).
  for l in text.splitLines:
    var lead = l.len - l.strip(trailing = false).len
    if l.startsWith("usage: "):
      lead = "usage: ".len
    if l.strip.len == 0:
      result.add plain(l)
    elif l.startsWith("usage: "):
      result.add @[span("usage:", "em"), span(" "), span(l[lead .. ^1], "code")]
    else:
      result.add @[span(l[0 ..< lead]), span(l[lead .. ^1], "code")]

func proseLines*(text: string, width: int): seq[Line] =
  ## Paragraphs wrapped to `width` (`wrap.prose`), as lines.
  for l in prose(text, width).split('\n'):
    result.add plain(l)

func heading*(text: string): seq[Line] =
  ## A heading in a usage ("commands:"), in `em`.
  @[@[span(text, "em")]]

func usageOf*(parts: varargs[seq[Line]]): seq[Line] =
  ## A usage made of its parts (the synopsis, the introduction, the options ...), a blank line between each two.
  for k, p in parts:
    if k > 0 and p.len > 0:
      result.add plain("")
    result.add p

func optionLines*(docs: seq[OptDoc], width: int): seq[Line] =
  ## The lines for the options: two spaces, the names and the value (in `code`), the help in a column, wrapped to `width`.
  var labelWidth = 0
  for d in docs:
    let n = label(d).len
    if n <= maxLabel:
      labelWidth = max(labelWidth, n)
  let column = indent + labelWidth + gap
  let helpWidth = max(minHelpWidth, width - column)
  for d in docs:
    let l = label(d)
    let names = l.strip(trailing = false)
    let lead = span(" ".repeat(indent + l.len - names.len))
    let help = wrap(d.help, helpWidth)
    if l.len > maxLabel or help.len == 0:
      result.add @[lead, span(names, "code")]
      for h in help:
        result.add plain(" ".repeat(column) & h)
    else:
      for i, h in help:
        if i == 0:
          let first: Line =
            @[lead, span(names, "code"), span(" ".repeat(labelWidth - l.len + gap) & h)]
          result.add first.stripped
        else:
          result.add plain(" ".repeat(column) & h)

func tableLines*(header: seq[string], rows: seq[seq[string]], width: int): seq[Line] =
  ## A table for a usage text, indented like the options, with lines between the columns and under the headings
  ## (`core/ruled.nim`).
  ruled(header, rows.mapIt(it.mapIt(plain(it))), width, indent, alternate = false)
    # (a few rows, beside text: no alternate rows)
