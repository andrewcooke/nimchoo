## Styled text for terminal displays: a line is a list of spans, each a piece of text in the styles it is in (the outermost
## first; none: plain text).  A style is a name; what it looks like is the theme's to say (`core/theme.nim`), so the same
## line is drawn in whatever theme is in force, and with or without colour (a `Paint`).  Keeping lines as spans, not as
## strings full of escape codes, means they can be measured and cut to a width without splitting an escape sequence.
##
## The names the program uses are those of the built-in dark theme (`dark.txt`, beside this file), and a name written in
## the code is checked against them when it is compiled (`span("failed", "bad")`, `styleName"select"`): a misspelt style is
## a compile error.  A theme that lacks one draws its text as the text around it.

import std/[strutils, tables, unicode]
import ../../core/[errors, globals, theme]
export theme.Theme

{.push raises: [].}

type
  StyleName* = distinct string ## the name of a style

  Span* = object
    text*: string
    styles*: seq[StyleName] ## the outermost first; none: plain text

  Line* = seq[Span]

  Paint* = object
    ## how lines are drawn: the theme in force, and whether in colour at all
    theme*: Theme
    colour*: bool

func `==`*(a, b: StyleName): bool {.borrow.}
func `$`*(s: StyleName): string {.borrow.}

func namesIn(text: string): seq[string] =
  ## The names of the styles of a built-in theme (which is tested to be one).
  try:
    for name in parseTheme(text).styles.keys:
      result.add name
  except ThemeError as e:
    raiseAssert "a built-in theme: " & e.msg

const
  builtInThemes* = [
    (name: "dark", text: staticRead("dark.txt")),
    (name: "light", text: staticRead("light.txt")),
  ] ## the themes the program carries (the `themes` package unpacks them)
  styleNames* = namesIn(builtInThemes[0].text)
    ## the styles the program may use: those of the built-in dark theme
  ellipsis = "…"

template styleName*(name: static string): StyleName =
  ## The style `name`, which the built-in theme must have (checked when compiled).
  static:
    doAssert name in styleNames,
      "no style '" & name & "' in the built-in theme (it has " & styleNames.join(", ") &
        ")"
  StyleName(name)

func anyStyle*(name: string): StyleName =
  ## The style `name`, whatever it is: for markup read while the program runs (a theme may define styles of its own).
  StyleName(name)

func span*(text: string): Span =
  ## A piece of plain text.
  Span(text: text)

func span*(text: string, style: StyleName): Span =
  ## A piece of text in a style.
  Span(text: text, styles: @[style])

template span*(words: string, style: static string): Span =
  ## A piece of text in the style named (checked when compiled).
  span(words, styleName(style))

template span*(words: string, outer, inner: static string): Span =
  ## A piece of text in one style inside another (`span("5", "bad", "em")`).
  Span(text: words, styles: @[styleName(outer), styleName(inner)])

func plain*(text: string): Line =
  ## A line of text with no style.
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
      result.add Span(text: s.text.runeSubStr(0, room), styles: s.styles)
      room = 0
  if result.len > 0:
    result.add Span(text: ellipsis, styles: result[^1].styles)
  else:
    result.add span(ellipsis)

func merged*(line: Line): Line =
  ## The line with the spans that have the same styles side by side made one, and the plain spaces between two spans of
  ## the same style in that style: so that a style with a background (a row of the selection) runs on across the
  ## columns, without gaps between them.
  for i, s in line:
    var styles = s.styles
    if styles.len == 0 and s.text.strip.len == 0 and i > 0 and i < line.high and
        line[i - 1].styles.len > 0 and line[i - 1].styles == line[i + 1].styles:
      styles = line[i - 1].styles
    if result.len > 0 and result[^1].styles == styles:
      result[^1].text.add s.text
    else:
      result.add Span(text: s.text, styles: styles)

func bracketed*(line: Line, selected: bool): Line =
  ## The line marked for where there is no colour, as the calendar marks a day: `[` before it and `]` after it if it is
  ## `selected`, a space before it if not (so that lines with and without the mark line up).
  if selected:
    @[span("[")] & line & @[span("]")]
  else:
    @[span(" ")] & line

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
  var inForce = "" # the codes of the look being drawn
  for s in line:
    let start =
      if paint.colour:
        terminalCodes(lookOf(paint.theme, s.styles))
      else:
        ""
    if start != inForce:
      if inForce.len > 0:
        result.add "\e[0m"
      result.add start
      inForce = start
    result.add s.text
  if inForce.len > 0:
    result.add "\e[0m"

func paintOf*(g: Globals, o: OutStream): Paint =
  ## How lines are drawn on `o`: in the theme in force, in colour if `o` is.
  Paint(theme: g.theme, colour: g.colour[o])

proc show*(g: Globals, o: OutStream, line: Line) =
  ## Write a line to `o`, drawn as `o` is.
  g.sayRendered(o, render(line, paintOf(g, o)) & "\n")
