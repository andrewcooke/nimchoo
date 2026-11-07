## Styled text for terminal displays: a line is a list of spans, each a piece
## of text with a look (a colour of the palette, and bold).  Keeping lines as spans, not as
## strings full of escape codes, means they can be measured and cut to a width
## without splitting an escape sequence, and rendered with or without colour.

import std/unicode
import ./palette
export palette

{.push raises: [].}

type
  Look* = object
    colour*: Color ## white (the default) is ordinary text
    bold*: bool

  Span* = object
    text*: string
    look*: Look

  Line* = seq[Span]

const ellipsis = "…"

func span*(text: string, colour = white, bold = false): Span =
  Span(text: text, look: Look(colour: colour, bold: bold))

func plain*(text: string): Line =
  @[span(text)]

func width*(line: Line): int =
  ## Columns the line takes (one per character: wide characters are not
  ## counted as two).
  for s in line:
    result += s.text.runeLen

func text*(line: Line): string =
  ## The line without any styling.
  for s in line:
    result.add s.text

func truncated*(line: Line, maxWidth: int): Line =
  ## The line cut to `maxWidth` columns; if it was cut, it ends in an ellipsis.
  if maxWidth <= 0:
    return @[]
  if line.width <= maxWidth:
    return line
  var room = maxWidth - 1 # the ellipsis takes a column
  for s in line:
    if room <= 0:
      break
    let n = s.text.runeLen
    if n <= room:
      result.add s
      room -= n
    else:
      result.add Span(text: s.text.runeSubStr(0, room), look: s.look)
      room = 0
  if result.len > 0:
    result.add Span(text: ellipsis, look: result[^1].look)
  else:
    result.add span(ellipsis)

func render*(line: Line, colour: bool): string =
  ## The line as text for a terminal: with escape codes if `colour`.
  for s in line:
    let styled = colour and (s.look.colour != white or s.look.bold)
    if styled:
      result.add terminalCode(s.look.colour)
      if s.look.bold:
        result.add "\e[1m"
    result.add s.text
    if styled:
      result.add resetCode
