## Styled text written as markup: `[good imported] 3 files [hide (1.2s)]`.  A bracket opens a style, named by the word
## after it and ended by one space; the matching `]` closes it.  Styles nest, and a nested one changes only the attributes
## it gives (`theme.nim`); `[default ...]` goes back to the look of plain text, whatever is around it.  `\[`, `\]` and `\\`
## are a bracket and a backslash.
##
## A style may run over a newline: the text is read into lines, and each line's pieces carry their styles, so a line is
## drawn on its own (it starts from nothing and ends with a reset), and can be cut or printed without the next.
##
## Reading the markup (`parseMarkup`) needs no theme, so it can be checked before a theme is known; `paint` gives each piece
## its look from a theme.  There is no fixed set of styles: a name is whatever a theme defines.

import std/[strformat, tables]
import ../../core/errors
import ./theme

{.push raises: [].}

type
  Piece* = object ## text and the styles it is in, the outermost first
    text*: string
    styles*: seq[string]

  Painted* = object ## text and its look
    text*: string
    look*: Look

func parseMarkup*(text: string): seq[seq[Piece]] {.raises: [MarkupError].} =
  ## The lines of `text`, each a list of pieces.
  result = @[newSeq[Piece]()]
  var open: seq[tuple[name: string, at: int]]
  var buffer = ""
  template flush() =
    if buffer.len > 0:
      var names: seq[string]
      for o in open:
        names.add o.name
      result[^1].add Piece(text: buffer, styles: names)
      buffer = ""

  var i = 0
  while i < text.len:
    case text[i]
    of '\\':
      if i + 1 < text.len and text[i + 1] in {'[', ']', '\\'}:
        buffer.add text[i + 1]
        i += 2
      else:
        raiseMarkup(
          "a backslash goes only before [, ] or \\ (write \\\\ for a backslash)", i + 1
        )
    of '[':
      var j = i + 1
      while j < text.len and text[j] in {'a' .. 'z', '0' .. '9', '-'}:
        inc j
      let name = text[i + 1 ..< j]
      if not isStyleName(name):
        raiseMarkup(
          "a [ starts a style, so the name of one follows it (write \\[ for a bracket)",
          i + 1,
        )
      if j >= text.len or text[j] != ' ':
        raiseMarkup(
          fmt"the name of a style is followed by a space: [{name} text]", j + 1
        )
      flush()
      open.add (name, i + 1)
      i = j + 1
    of ']':
      if open.len == 0:
        raiseMarkup("this ] closes no style (write \\] for a bracket)", i + 1)
      flush()
      discard open.pop()
      inc i
    of '\n':
      flush()
      result.add newSeq[Piece]()
      inc i
    else:
      buffer.add text[i]
      inc i
  if open.len > 0:
    raiseMarkup(fmt"[{open[^1].name} is not closed", open[^1].at)
  flush()

func paint*(theme: Theme, line: seq[Piece]): seq[Painted] =
  ## The pieces of a line with their looks.  A style the theme does not have changes nothing (a theme need not have them
  ## all; the names the program uses are checked against the built-in theme when it is compiled).
  let base = baseLook(theme)
  for p in line:
    var look = base
    for name in p.styles:
      if name == defaultStyle:
        look = base
      else:
        look = look.over(theme.styles.getOrDefault(name))
    result.add Painted(text: p.text, look: look)

func render*(line: seq[Painted], colour: bool): string =
  ## The line as text for a terminal: each piece starts its look (if `colour`) and ends with a reset, so that nothing runs
  ## on to the next piece or the next line.
  for p in line:
    let start =
      if colour:
        terminalCodes(p.look)
      else:
        ""
    result.add start
    result.add p.text
    if start.len > 0:
      result.add "\e[0m"

func styled*(
    theme: Theme, text: string, colour: bool
): seq[string] {.raises: [MarkupError].} =
  ## The lines of `text`, written as markup, for a terminal.
  for line in parseMarkup(text):
    result.add render(paint(theme, line), colour)
