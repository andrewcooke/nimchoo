## Styled lines (`core/line.nim`) drawn for a terminal: in the theme in force, with or without colour (a `Paint`).  The
## built-in themes (`dark.theme`, `light.theme`, beside this file) define every style the program uses (a test checks).

import std/tables
import ../../core/[globals, line, theme]
export theme.Theme, line

{.push raises: [].}

type Paint* = object
  ## how lines are drawn: the theme in force, and whether in colour at all
  theme*: Theme
  colour*: bool

const builtInThemes* = [
  (name: "dark", text: staticRead("dark.theme")),
  (name: "light", text: staticRead("light.theme")),
] ## the themes the program carries (the `themes` package unpacks them)

func lookOf*(theme: Theme, styles: seq[StyleName]): Look =
  ## How text in `styles` looks: the theme's base look with each style over it in turn (`default` goes back to the base;
  ## a style the theme lacks changes nothing).
  let base = baseLook(theme)
  result = base
  for s in styles:
    if $s == defaultStyle:
      result = base
    else:
      result = result.over(theme.styles.getOrDefault($s))

func render*(line: Line, paint: Paint): string =
  ## The line as text for a terminal: each look is started (if in colour) where it begins and reset where it ends, and the
  ## line ends with a reset, so that nothing runs on to the next line.  Spans side by side that look the same share one.
  ## The lines of a table or a tree in a span (`│ ─ ├`), and what is between backticks, are in their styles over the span's
  ## own (`theme.Drawer`).
  if not paint.colour:
    for s in line:
      result.add withoutMarks(s.text)
    return
  var d: Drawer
  for s in line:
    d.draw(paint.theme, lookOf(paint.theme, s.styles), s.text)
  d.endLine()
  d.text

func paintOf*(g: Globals, o: OutStream): Paint =
  ## How lines are drawn on `o`: in the theme in force, in colour if `o` is.
  Paint(theme: g.theme, colour: g.colour[o])

proc show*(g: Globals, o: OutStream, line: Line) =
  ## Write a line to `o`, drawn as `o` is.
  g.sayRendered(o, render(line, paintOf(g, o)) & "\n")
