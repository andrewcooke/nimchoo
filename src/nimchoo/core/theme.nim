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
##
## A colour can also be taken from a style above it: `NAME.fg` and `NAME.bg` are NAME's foreground and background as it
## is drawn (what NAME leaves out it has from `default`): `select bg=code.fg`.  And `v(COLOUR, GAMMA)` is a colour with
## its value, the V of HSV from 0 to 1, raised to GAMMA (more than 1 darker, less than 1 lighter; black and white stay as
## they are): `alt-code fg=v(code.fg, 1.2)`, `v(#a0a0c0, 2)`, `v(v(code.bg, 2), 0.8)`.  Only a `#rrggbb` colour has a value;
## it is worked out when the theme is read.

import std/[math, options, sequtils, strformat, strutils, tables]
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
      ## why it is the one in force (`--theme`, `$NCH_THEME` ...: `nch --config`)

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
  ## `#rrggbb`, one of the sixteen names, or `terminal`.
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
    fmt"'{value}' is not a colour (#rrggbb, NAME.fg, NAME.bg, v(COLOUR, GAMMA), terminal, or one of {basicNames.join("" "")})",
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

func withValue(c: Colour, gamma: float): Colour =
  ## `c` (a `#rrggbb`) with its value V (of HSV) raised to `gamma`.  Changing only V keeps the hue and the saturation, and
  ## so the proportions of red, green and blue: the colour is the same as scaled by V^gamma / V.
  let v = max([c.r, c.g, c.b]).float / 255.0
  if v == 0.0:
    return c
  let k = pow(v, gamma) / v
  func scaled(x: uint8): uint8 =
    uint8(clamp(round(x.float * k), 0.0, 255.0))

  Colour(kind: ckRgb, r: scaled(c.r), g: scaled(c.g), b: scaled(c.b))

func over(base, top: Style): Style =
  ## `base` with what `top` gives instead.
  func pick[T](a, b: Option[T]): Option[T] =
    (if b.isSome: b else: a)

  Style(
    fg: pick(base.fg, top.fg),
    bg: pick(base.bg, top.bg),
    weight: pick(base.weight, top.weight),
    underline: pick(base.underline, top.underline),
    italic: pick(base.italic, top.italic),
    reverse: pick(base.reverse, top.reverse),
  )

func lookOfName(defined: OrderedTable[string, Style], name: string): Look =
  ## How a style defined above is drawn: the terminal's own look, with `default`, then the style.
  result = terminalLook.over(defined.getOrDefault(defaultStyle))
  if name != defaultStyle:
    result = result.over(defined.getOrDefault(name))

func ofStyle(
    name, part: string, defined: OrderedTable[string, Style], line: int
): Colour {.raises: [ThemeError].} =
  ## NAME's colour for `part` (fg or bg), as it is drawn.
  if name notin defined:
    raiseTheme(fmt"{name}.{part}: there is no style {name} above this line", line)
  let look = lookOfName(defined, name)
  if part == "fg": look.fg else: look.bg

func colourOf(
  value: string, defined: OrderedTable[string, Style], line: int
): Colour {.raises: [ThemeError].}

func derived(
    value: string, defined: OrderedTable[string, Style], line: int
): Colour {.raises: [ThemeError].} =
  ## The colour of `v(COLOUR, GAMMA)`: COLOUR with its value raised to GAMMA.
  let comma = value.rfind(',')
  if comma < 0:
    raiseTheme(fmt"'{value}' is not v(COLOUR, GAMMA)", line)
  let arg = value[2 ..< comma].strip
  let gammaText = value[comma + 1 ..^ 2].strip
  var gamma: float
  try:
    gamma = parseFloat(gammaText)
  except ValueError:
    raiseTheme(fmt"v({arg}, {gammaText}): the gamma is a number", line)
  if not (gamma > 0.0) or gamma == Inf:
    raiseTheme(fmt"v({arg}, {gammaText}): the gamma is more than 0", line)
  let c = colourOf(arg, defined, line)
  if c.kind != ckRgb:
    raiseTheme(
      fmt"v({arg}, ...): {arg} is not a #rrggbb colour, so it has no value to change",
      line,
    )
  withValue(c, gamma)

func colourOf(
    value: string, defined: OrderedTable[string, Style], line: int
): Colour {.raises: [ThemeError].} =
  ## A colour as written: `#rrggbb`, a name, `terminal`, `NAME.fg`, `NAME.bg`, or `v(COLOUR, GAMMA)`.
  if value.startsWith("v(") and value.endsWith(")"):
    return derived(value, defined, line)
  let dot = value.rfind('.')
  if dot > 0 and isStyleName(value[0 ..< dot]):
    let part = value[dot + 1 ..^ 1]
    if part notin ["fg", "bg"]:
      raiseTheme(fmt"'{value}': a style's colour is NAME.fg or NAME.bg", line)
    return ofStyle(value[0 ..< dot], part, defined, line)
  if value in defined and value notin basicNames:
    raiseTheme(fmt"'{value}' is a style: its colour is {value}.fg or {value}.bg", line)
  parseColour(value, line)

func attributeWords(words: seq[string]): seq[string] =
  ## The words of a line joined where a space is inside brackets (`fg=v(code.fg, 1.2)` is one).
  var depth = 0
  for w in words:
    if depth > 0:
      result[^1].add " " & w
    else:
      result.add w
    depth += w.count('(') - w.count(')')

func parseStyle(
    words: seq[string], line: int, defined: OrderedTable[string, Style]
): Style {.raises: [ThemeError].} =
  ## The attributes after the name, each `key=value`, none twice; `defined` are the styles above (for `NAME.fg` and `NAME.bg`).
  for word in attributeWords(words):
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
      once(fg, colourOf(value, defined, line))
    of "bg":
      once(bg, colourOf(value, defined, line))
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
  ## The theme in `text`, the contents of a theme file.  Each style X comes with `alt-X` (the style of every other row of
  ## a table that asks for it: `line.alternated`), defined as X; a line `alt-X ...` changes what it gives, and the rest
  ## stays X's (`alt-code fg=...` keeps code's background), whichever of the two lines comes first.
  var line = 0
  var given: seq[string] # (the names on the lines: an alt-X made from X is not given)
  var altGiven: Table[string, Style] # (what each alt-X line gives, by X)
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
    if name in given:
      raiseTheme(fmt"the style {name} is given twice", line)
    given.add name
    let style = parseStyle(words[1 ..^ 1], line, result.styles)
    if name.startsWith(altPrefix):
      let x = name[altPrefix.len ..^ 1]
      altGiven[x] = style
      result.styles[name] = result.styles.getOrDefault(x).over(style)
    else:
      result.styles[name] = style
      result.styles[altPrefix & name] = style.over(altGiven.getOrDefault(name))

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
  messageStyles* = ["warn", "bad"]
    ## the styles of warnings and failures: what is in them is drawn all in them, backticks and all (no `codeStyle`
    ## inside), so that a message is one colour

func isLineDrawing*(r: Rune): bool =
  ## Whether `r` is a box-drawing character (U+2500 to U+257F).
  int32(r) in 0x2500'i32 .. 0x257F'i32

type Drawer* = object
  ## Text drawn for a terminal, piece by piece, each piece in a look of its own, with the two rules that hold wherever text
  ## is drawn (`Globals.inTheme`, `style.render`): the lines of a table in `lineStyle`, and what is between backticks in
  ## `codeStyle`, over the piece's own look.  A look is started where it begins and reset where it ends.  What is between
  ## backticks runs on from one piece to the next and over the end of a line (a phrase can be wrapped).
  text*: string ## what is drawn so far
  inForce: string ## the codes of the look being drawn
  inTyped: bool ## between backticks

func draw*(d: var Drawer, theme: Theme, look: Look, text: string, typing = true) =
  ## Draw `text` in `look`; without `typing`, what is between backticks is drawn as it is, backticks and all (a message:
  ## `messageStyles`).
  let plain = terminalCodes(look)
  let lines = terminalCodes(look.over(theme.styles.getOrDefault(lineStyle)))
  let typed = terminalCodes(look.over(theme.styles.getOrDefault(codeStyle)))
  for r in text.runes:
    var want = plain
    if r == Rune('`') and typing:
      d.inTyped = not d.inTyped
      continue # (in colour the style marks it: the backtick is not drawn)
    if r.isLineDrawing:
      want = lines
    elif d.inTyped and typing:
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
  ## own (`Drawer`).  A space that is not to be broken (`line.noBreak`) is drawn as a space.
  if not paint.colour:
    return line.plainText.replace(noBreak, " ")
  var d: Drawer
  for s in line:
    # (a warning or a failure is one colour: literal text in it keeps its backticks, not its style)
    let message = s.styles.anyIt(($it).replace(altPrefix, "") in messageStyles)
    if message and s.isCode:
      let own = s.styles.filterIt(($it).replace(altPrefix, "") != codeStyle)
      d.draw(
        paint.theme,
        lookOf(paint.theme, own),
        ('`' & s.text & '`').replace(noBreak, " "),
        typing = false,
      )
    else:
      d.draw(
        paint.theme,
        lookOf(paint.theme, s.styles),
        s.text.replace(noBreak, " "),
        typing = not message,
      )
  d.endLine()
  d.text
