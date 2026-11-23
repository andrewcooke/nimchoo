## The option list of a command's usage text, made from the descriptions of its options (`OptDoc`), so that it cannot
## differ from what the parser accepts; and the tables a usage shows of what the registry holds (`tableLines`: the subjects
## and frames of `map`).  A command's usage is styled lines (`core/line.nim`): its synopsis and introduction, written by
## hand, then this list, then any closing prose and sections, put together by `usageOf` in one order.  Pure: the width to wrap to is given.

import std/[options, strutils, unicode]
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
  if d.metavar.isSome:
    result.add(
      if d.arity == aOptional:
        " [" & d.metavar.get & "]"
      else:
        " " & d.metavar.get
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
      result.add ~"<em usage:> `{l[lead .. ^1]}`"
    else:
      result.add ~"{l[0 ..< lead]}`{l[lead .. ^1]}`"

func stepMark(p: Line): int =
  ## The width of the mark of a step of a numbered list ("3. "), or 0 if the paragraph is not one.
  let t = p.text
  var i = 0
  while i < t.len and t[i] in {'0' .. '9'}:
    inc i
  if i > 0 and i + 1 < t.len and t[i] == '.' and t[i + 1] == ' ':
    i + 2
  else:
    0

func proseLines*(paragraphs: seq[Line], width: int): seq[Line] =
  ## Paragraphs (each a `~"..."` line) wrapped to `width` by words, each word keeping its style, a blank line between two.
  ## A paragraph that starts "1. ", "2. " ... is a step of a numbered list: no blank line between two steps, and a step
  ## that is wrapped goes on under its text, not under its number.
  for k, p in paragraphs:
    let mark = stepMark(p)
    if k > 0 and not (mark > 0 and stepMark(paragraphs[k - 1]) > 0):
      result.add plain("")
    if mark == 0:
      result.add p.wrapped(width)
    else:
      for n, l in p.wrapped(max(1, width - mark)):
        result.add(
          if n == 0:
            l
          else:
            plain(spaces(mark)) & l
        )

func optionLines*(docs: seq[OptDoc], width: int): seq[Line] =
  ## The lines for the options: two spaces, the names and the value (in `code`), the help in a column, wrapped to `width`.
  var labelWidth = 0
  for d in docs:
    let n = label(d).runeLen
    if n <= maxLabel:
      labelWidth = max(labelWidth, n)
  let column = indent + labelWidth + gap
  let helpWidth = max(minHelpWidth, width - column)
  for d in docs:
    let l = label(d)
    let names = l.strip(trailing = false)
    let lead = " ".repeat(indent + l.runeLen - names.runeLen)
    let help = d.help.wrapped(helpWidth)
    let pad = " ".repeat(column)
    if l.runeLen > maxLabel or d.help.len == 0:
      result.add ~"{lead}`{names}`"
      for h in help:
        if h.len > 0:
          result.add ~"{pad}" & h
    else:
      for i, h in help:
        if i == 0:
          let between = " ".repeat(labelWidth - l.runeLen + gap)
          let first: Line = ~"{lead}`{names}`{between}" & h
          result.add first.stripped
        else:
          result.add ~"{pad}" & h

func tableLines*(header: seq[string], rows: seq[seq[Line]], width: int): seq[Line] =
  ## A table for a usage text, indented like the options, with lines between the columns and under the headings
  ## (`core/ruled.nim`).
  ruled(header, rows, width, indent, alternate = false)
    # (a few rows, beside text: no alternate rows)

type Section* = tuple[heading: string, lines: seq[Line]]
  ## a part of a usage after the notes, under its heading ("commands", "kinds"): a table, a list

func usageOf*(
    synopsis: string,
    width: int,
    intro: seq[Line] = @[],
    options: seq[OptDoc] = @[],
    notes: seq[Line] = @[],
    sections: seq[Section] = @[],
): seq[Line] =
  ## A usage, its parts always in this order, a blank line between each two: the synopsis (`synopsisLines`), the
  ## introduction and the options (`optionLines`), the notes (the prose a list of paragraphs, `proseLines`, wrapped to
  ## `width`), then each section under
  ## its heading, in `em`, lower case, with a colon ("commands:").
  var parts = @[synopsisLines(synopsis)]
  if intro.len > 0:
    parts.add proseLines(intro, width)
  if options.len > 0:
    parts.add optionLines(options, width)
  if notes.len > 0:
    parts.add proseLines(notes, width)
  for s in sections:
    parts.add @[~"<em {s.heading.toLowerAscii}:>"] & s.lines
  for k, p in parts:
    if k > 0:
      result.add plain("")
    result.add p
