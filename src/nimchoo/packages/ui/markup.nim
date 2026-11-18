## Styled text written as markup: `[good imported] 3 files [hide (1.2s)]`.  A bracket opens a style, named by the word
## after it and ended by one space; the matching `]` closes it.  Styles nest, and a nested one changes only the attributes
## it gives (`core/theme.nim`); `[default ...]` goes back to the look of plain text, whatever is around it.  `\[`, `\]` and
## `\\` are a bracket and a backslash.
##
## A style may run over a newline: the text is read into lines (`style.Line`), and each span carries its styles, so a line
## is drawn on its own (it starts from nothing and ends with a reset), and can be cut or printed without the next.
##
## Reading the markup needs no theme, so it can be checked before a theme is known.  There is no fixed set of styles: a
## name is whatever a theme defines, and one the theme lacks changes nothing.

import std/strformat
import ../../core/[errors, theme]
import ./style

{.push raises: [].}

func parseMarkup*(text: string): seq[Line] {.raises: [MarkupError].} =
  ## The lines of `text`.
  result = @[newSeq[Span]()]
  var open: seq[tuple[name: string, at: int]]
  var buffer = ""
  template flush() =
    if buffer.len > 0:
      var names: seq[StyleName]
      for o in open:
        names.add anyStyle(o.name)
      result[^1].add Span(text: buffer, styles: names)
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
      result.add newSeq[Span]()
      inc i
    else:
      buffer.add text[i]
      inc i
  if open.len > 0:
    raiseMarkup(fmt"[{open[^1].name} is not closed", open[^1].at)
  flush()

func styled*(paint: Paint, text: string): seq[string] {.raises: [MarkupError].} =
  ## The lines of `text`, written as markup, for a terminal.
  for line in parseMarkup(text):
    result.add render(line, paint)
