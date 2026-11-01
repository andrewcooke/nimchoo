## Styled text for terminal displays: a line is a list of spans, each a piece
## of text with a look (colour, bold, dim).  Keeping lines as spans, not as
## strings full of escape codes, means they can be measured and cut to a width
## without splitting an escape sequence, and rendered with or without colour.

import std/unicode
from std/terminal import ForegroundColor, ansiForegroundColorCode, ansiStyleCode,
    styleBright, styleDim, ansiResetCode

{.push raises: [].}

type
  Color* = enum
    cNone, cRed, cGreen, cYellow, cBlue, cMagenta, cCyan, cWhite

  Look* = object
    fg*: Color
    bold*, dim*: bool

  Span* = object
    text*: string
    look*: Look

  Line* = seq[Span]

const
  ellipsis = "…"

func span*(text: string, fg = cNone, bold = false, dim = false): Span =
  Span(text: text, look: Look(fg: fg, bold: bold, dim: dim))

func plain*(text: string): Line = @[span(text)]

func width*(line: Line): int =
  ## Columns the line takes (one per character: wide characters are not
  ## counted as two).
  for s in line: result += s.text.runeLen

func text*(line: Line): string =
  ## The line without any styling.
  for s in line: result.add s.text

func truncated*(line: Line, maxWidth: int): Line =
  ## The line cut to `maxWidth` columns; if it was cut, it ends in an ellipsis.
  if maxWidth <= 0: return @[]
  if line.width <= maxWidth: return line
  var room = maxWidth - 1             # the ellipsis takes a column
  for s in line:
    if room <= 0: break
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

func fgOf(c: Color): ForegroundColor =
  case c
  of cRed: fgRed
  of cGreen: fgGreen
  of cYellow: fgYellow
  of cBlue: fgBlue
  of cMagenta: fgMagenta
  of cCyan: fgCyan
  of cWhite: fgWhite
  of cNone: fgDefault

func render*(line: Line, colour: bool): string =
  ## The line as text for a terminal: with escape codes if `colour`.
  for s in line:
    let styled = colour and (s.look.fg != cNone or s.look.bold or s.look.dim)
    if styled:
      if s.look.fg != cNone: result.add ansiForegroundColorCode(fgOf(s.look.fg))
      if s.look.bold: result.add ansiStyleCode(styleBright)
      if s.look.dim: result.add ansiStyleCode(styleDim)
    result.add s.text
    if styled: result.add ansiResetCode
