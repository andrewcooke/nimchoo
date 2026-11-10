## The option list of a command's usage text, made from the descriptions of its options (`OptDoc`), so that it cannot
## differ from what the parser accepts.  A command's usage is its synopsis and introduction, written by hand, then
## this list, then any closing prose.  Pure: the width to wrap to is given.

import std/strutils
import ./args

{.push raises: [].}

const
  indent = 2
  gap = 2
  maxLabel = 24 ## a longer label has its help on the next line
  minHelpWidth = 30

func label(d: OptDoc): string =
  result = d.names.join(", ")
  if d.metavar.len > 0:
    result.add " " & d.metavar

func wrap*(text: string, width: int): seq[string] =
  ## `text` broken into lines of at most `width` characters at spaces (a longer word has a line of its own).  A
  ## newline in the text starts a new line.  Two spaces after a full stop stay two, unless the line ends there.
  for paragraph in text.split('\n'):
    var line = ""
    for word in paragraph.split(' '):
      if line.len == 0:
        line = word
      elif line.len + 1 + word.len <= width:
        line.add " " & word
      else:
        result.add line.strip(leading = false)
        line = word
    result.add line.strip(leading = false)

func prose*(text: string, width: int): string =
  ## Paragraphs of text wrapped to `width`: the paragraphs are separated by a blank line, and a line break inside one is
  ## only where the source was broken, so it becomes a space.  (For the introduction and the notes of a usage.)
  var paragraphs: seq[string]
  for p in text.strip(chars = {'\n'}).split("\n\n"):
    paragraphs.add wrap(p.replace('\n', ' '), width).join("\n")
  paragraphs.join("\n\n")

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
