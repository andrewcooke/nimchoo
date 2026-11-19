## The option list of a command's usage text, made from the descriptions of its options (`OptDoc`), so that it cannot
## differ from what the parser accepts; and the tables a usage shows of what the registry holds (`tableLines`: the subjects
## and frames of `map`).  A command's usage is its synopsis and introduction, written by hand, then
## this list, then any closing prose.  Pure: the width to wrap to is given.

import std/strutils
import ../../../core/[ruled, theme, wrap]
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

func marked(l: string): string =
  ## The label with its names and value marked as text to type (`theme.typedStart`): in colour they are drawn in the style
  ## of what is typed; the marks take no room, so the columns are those of the plain text.
  let names = l.strip(trailing = false)
  " ".repeat(l.len - names.len) & typedStart & names & typedEnd

func synopsisText*(text: string): string =
  ## The synopsis of a usage with each of its command lines marked as text to type (`theme.typedStart`: drawn in the style
  ## of commands, taking no room); "usage:" and the indent before the others are not.
  var lines: seq[string]
  for l in text.splitLines:
    var lead = l.len - l.strip(trailing = false).len
    if l.startsWith("usage: "):
      lead = "usage: ".len
    lines.add(
      if l.strip.len == 0:
        l
      else:
        l[0 ..< lead] & typedStart & l[lead .. ^1] & typedEnd
    )
  lines.join("\n")

func optionLines*(docs: seq[OptDoc], width: int): seq[string] =
  ## The lines for the options: two spaces, the names and the value (marked as text to type), the help in a column,
  ## wrapped to `width`.
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
      result.add " ".repeat(indent) & marked(l)
      for h in help:
        result.add " ".repeat(column) & h
    else:
      for i, h in help:
        if i == 0:
          result.add (
            " ".repeat(indent) & marked(l) & " ".repeat(labelWidth - l.len + gap) & h
          ).strip(leading = false)
        else:
          result.add " ".repeat(column) & h
      if help.len == 0:
        result.add " ".repeat(indent) & marked(l)

func tableLines*(header: seq[string], rows: seq[seq[string]], width: int): seq[string] =
  ## A table for a usage text, indented like the options, with lines between the columns and under the headings
  ## (`core/ruled.nim`).
  ruledLines(header, rows, width, indent)
