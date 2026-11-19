## Themes: what each style of text looks like on a terminal, read from a theme file.  The theme in force is in `Globals`
## (chosen by the `themes` package when `nch` starts); an empty one draws everything as the terminal's own text.  A style names only the attributes it
## changes (foreground, background, weight, underline, italic, reverse); one nested inside another replaces those and keeps the rest
## (`markup.nim`).  The style `default` surrounds all text, and what it leaves out is the terminal's own, so every piece of
## text has a complete look.
##
## The file has one style per line: its name, then any of `fg=COLOUR`, `bg=COLOUR`, `weight=bold|normal|dim`,
## `underline=yes|no`, `italic=yes|no` and `reverse=yes|no` (foreground and background swapped).  A colour is `#rrggbb`, one of the sixteen terminal colours (`red`,
## `bright-red` ...: they follow the terminal's own palette), or `terminal` (the terminal's own text or background colour).
## Blank lines and lines starting with `#` are ignored.

import std/[options, strformat, strutils, tables]
from std/unicode import Rune, runes, `$`, `==`
import ./[errors, line]

{.push raises: [].}

type
  ColourKind* = enum
    ckTerminal ## the terminal's own foreground or background
    ckBasic ## one of the sixteen colours of the terminal's palette
    ckRgb ## an exact colour (true colour)

  Colour* = object
    case kind*: ColourKind
    of ckTerminal:
      discard
    of ckBasic:
      index*: range[0 .. 15] ## 0-7 the normal colours, 8-15 the bright ones
    of ckRgb:
      r*, g*, b*: uint8

  Weight* = enum
    wtNormal
    wtBold
    wtDim

  Style* = object
    ## what a style changes: none for an attribute it keeps from the style around it
    fg*, bg*: Option[Colour]
    weight*: Option[Weight]
    underline*, italic*, reverse*: Option[bool]

  Look* = object ## how a piece of text is drawn: every attribute
    fg*, bg*: Colour
    weight*: Weight
    underline*, italic*, reverse*: bool

  Theme* = object
    styles*: OrderedTable[string, Style] ## in the order of the file
    name*: string
      ## what it is called (the file's name without `.theme`; "" when read from text)
    origin*: string
      ## why it is the one in force (`--theme`, `$NCH_THEME` ...: `nch packages --config`)

const
  defaultStyle* = "default" ## the style around all text
  basicNames = [
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
    "bright-black", "bright-red", "bright-green", "bright-yellow", "bright-blue",
    "bright-magenta", "bright-cyan", "bright-white",
  ]
  terminalLook* = Look(
    fg: Colour(kind: ckTerminal),
    bg: Colour(kind: ckTerminal),
    weight: wtNormal,
    underline: false,
    italic: false,
    reverse: false,
  ) ## the terminal's own look: what `default` starts from

func `==`*(a, b: Colour): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of ckTerminal:
    true
  of ckBasic:
    a.index == b.index
  of ckRgb:
    a.r == b.r and a.g == b.g and a.b == b.b

func isStyleName*(s: string): bool =
  ## A name of a style: a lower-case letter, then lower-case letters, digits and hyphens.
  s.len > 0 and s[0] in {'a' .. 'z'} and s.allCharsInSet({'a' .. 'z', '0' .. '9', '-'})

func parseColour(value: string, line: int): Colour {.raises: [ThemeError].} =
  if value == "terminal":
    return Colour(kind: ckTerminal)
  let i = basicNames.find(value)
  if i >= 0:
    return Colour(kind: ckBasic, index: i)
  if value.len == 7 and value[0] == '#' and value[1 .. ^1].allCharsInSet(HexDigits):
    try:
      return Colour(
        kind: ckRgb,
        r: uint8(parseHexInt(value[1 .. 2])),
        g: uint8(parseHexInt(value[3 .. 4])),
        b: uint8(parseHexInt(value[5 .. 6])),
      )
    except ValueError:
      raiseAssert "six hex digits were checked"
  raiseTheme(
    fmt"'{value}' is not a colour (#rrggbb, terminal, or one of {basicNames.join("" "")})",
    line,
  )

func parseYes(key, value: string, line: int): bool {.raises: [ThemeError].} =
  case value
  of "yes":
    true
  of "no":
    false
  else:
    raiseTheme(fmt"{key} is yes or no, not '{value}'", line)

func parseStyle(words: seq[string], line: int): Style {.raises: [ThemeError].} =
  ## The attributes after the name, each `key=value`, none twice.
  for word in words:
    let kv = word.split('=', maxsplit = 1)
    if kv.len != 2 or kv[1].len == 0:
      raiseTheme(
        fmt"'{word}' is not key=value (fg=, bg=, weight=, underline=, italic=, reverse=)",
        line,
      )
    let (key, value) = (kv[0], kv[1])
    template once(field: untyped, v: untyped) =
      if result.field.isSome:
        raiseTheme(fmt"{key} is given twice", line)
      result.field = some(v)

    case key
    of "fg":
      once(fg, parseColour(value, line))
    of "bg":
      once(bg, parseColour(value, line))
    of "weight":
      let w =
        case value
        of "normal":
          wtNormal
        of "bold":
          wtBold
        of "dim":
          wtDim
        else:
          raiseTheme(fmt"weight is bold, normal or dim, not '{value}'", line)
      once(weight, w)
    of "underline":
      once(underline, parseYes(key, value, line))
    of "italic":
      once(italic, parseYes(key, value, line))
    of "reverse":
      once(reverse, parseYes(key, value, line))
    else:
      raiseTheme(
        fmt"'{key}' is not an attribute (they are fg, bg, weight, underline, italic, reverse)",
        line,
      )

func parseTheme*(text: string): Theme {.raises: [ThemeError].} =
  ## The theme in `text`, the contents of a theme file.
  var line = 0
  for raw in text.splitLines:
    inc line
    let s = raw.strip
    if s.len == 0 or s.startsWith('#'):
      continue
    let words = s.splitWhitespace
    let name = words[0]
    if not isStyleName(name):
      raiseTheme(
        fmt"'{name}' is not a name of a style (lower-case letters, digits and hyphens, starting with a letter)",
        line,
      )
    if name in result.styles:
      raiseTheme(fmt"the style {name} is given twice", line)
    result.styles[name] = parseStyle(words[1 ..^ 1], line)

func over*(look: Look, style: Style): Look =
  ## `look` with what `style` changes.
  result = look
  if style.fg.isSome:
    result.fg = style.fg.get
  if style.bg.isSome:
    result.bg = style.bg.get
  if style.weight.isSome:
    result.weight = style.weight.get
  if style.underline.isSome:
    result.underline = style.underline.get
  if style.italic.isSome:
    result.italic = style.italic.get
  if style.reverse.isSome:
    result.reverse = style.reverse.get

func baseLook*(theme: Theme): Look =
  ## The look of text in no style but `default`: the terminal's own, with what `default` changes.
  terminalLook.over(theme.styles.getOrDefault(defaultStyle))

func colourCode(c: Colour, background: bool): string =
  case c.kind
  of ckTerminal:
    ""
  of ckBasic:
    let base =
      if c.index < 8:
        (if background: 40 else: 30)
      else:
        (if background: 100 else: 90)
    $(base + c.index mod 8)
  of ckRgb:
    (if background: "48" else: "38") & fmt";2;{c.r};{c.g};{c.b}"

func terminalCodes*(look: Look): string =
  ## The escape code that starts `look` ("" for the terminal's own look: nothing to start).
  var parts: seq[string]
  case look.weight
  of wtNormal:
    discard
  of wtBold:
    parts.add "1"
  of wtDim:
    parts.add "2"
  if look.italic:
    parts.add "3"
  if look.underline:
    parts.add "4"
  if look.reverse:
    parts.add "7"
  for (c, background) in [(look.fg, false), (look.bg, true)]:
    let code = colourCode(c, background)
    if code.len > 0:
      parts.add code
  if parts.len == 0:
    ""
  else:
    "\e[" & parts.join(";") & "m" # (a code built from its parts)

func asStyle*(look: Look): Style =
  ## A style that gives every attribute of `look` (so that it looks the same whatever it is inside).
  Style(
    fg: some(look.fg),
    bg: some(look.bg),
    weight: some(look.weight),
    underline: some(look.underline),
    italic: some(look.italic),
    reverse: some(look.reverse),
  )

const
  lineStyle* = "hide"
    ## the style that the lines of a table or a tree (the box-drawing characters, `│ ─ ┼ └`) are drawn in, wherever they
    ## are
  typedStyle* = "cmd"
    ## the style of what is between backticks, wherever it is: a command, an option, a path, what a person would type (in
    ## colour the backticks are left out: the style marks it; without colour they are the mark)

func isLineDrawing*(r: Rune): bool =
  ## Whether `r` is a box-drawing character (U+2500 to U+257F).
  int32(r) in 0x2500'i32 .. 0x257F'i32

type Drawer* = object
  ## Text drawn for a terminal, piece by piece, each piece in a look of its own, with the two rules that hold wherever text
  ## is drawn (`Globals.inTheme`, `style.render`): the lines of a table in `lineStyle`, and what is between backticks in
  ## `typedStyle`, over the piece's own look.  A look is started where it begins and reset where it ends.  What is between
  ## backticks runs on from one piece to the next and over the end of a line (a phrase can be wrapped).
  text*: string ## what is drawn so far
  inForce: string ## the codes of the look being drawn
  inTyped: bool ## between backticks

func draw*(d: var Drawer, theme: Theme, look: Look, text: string) =
  ## Draw `text` in `look`.
  let plain = terminalCodes(look)
  let lines = terminalCodes(look.over(theme.styles.getOrDefault(lineStyle)))
  let typed = terminalCodes(look.over(theme.styles.getOrDefault(typedStyle)))
  for r in text.runes:
    var want = plain
    if r == Rune('`'):
      d.inTyped = not d.inTyped
      continue # (in colour the style marks it: the backtick is not drawn)
    if r.isLineDrawing:
      want = lines
    elif d.inTyped:
      want = typed
    if want != d.inForce:
      if d.inForce.len > 0:
        d.text.add "\e[0m"
      d.text.add want
      d.inForce = want
    d.text.add $r

func endLine*(d: var Drawer) =
  ## The end of a line: a reset, so that nothing runs on (what is between backticks goes on in the next line).
  if d.inForce.len > 0:
    d.text.add "\e[0m"
    d.inForce = ""

type Paint* = object
  ## how lines are drawn: the theme in force, and whether in colour at all
  theme*: Theme
  colour*: bool

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
  ## own (`Drawer`).
  if not paint.colour:
    return line.text
  var d: Drawer
  for s in line:
    d.draw(paint.theme, lookOf(paint.theme, s.styles), s.text)
  d.endLine()
  d.text
