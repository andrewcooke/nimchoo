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
##
## **Shades**: a style named `NAME,FRACTION` (`fitness,0.37`: made by the program, never written in a theme) is drawn from
## the *stops* of the shade, the styles `NAME-0`, `NAME-1` and any between (`NAME-0.5`, `NAME-0.25`): its colours are
## interpolated in HSV (`between`) between the two stops either side of the fraction, its other attributes the lower
## one's.  A theme without stops for NAME has the shade drawn by `default-0` ... `default-1`.  A shade's stops run from 0
## to 1, and each gives the same colours, `#rrggbb` (checked when the theme is read).

import std/[algorithm, math, options, sequtils, strformat, strutils, tables]
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
  shadeSeparator* = ',' ## between a shade's style and its fraction: `fitness,0.37`
  firstStop* = "-0" ## the stop of a shade at 0: `fitness-0` (and `-1` at 1: `stopOf`)
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

func stopOf*(name: string): Option[tuple[shade: string, at: float]] =
  ## A stop of a shade, `fitness-0.5`: the shade and where it is (0 to 1); none for any other name.
  let dash = name.rfind('-')
  if dash <= 0:
    return
  let tail = name[dash + 1 ..^ 1]
  if tail.len == 0 or not tail.allCharsInSet({'0' .. '9', '.'}) or tail.count('.') > 1 or
      tail[0] == '.' or tail[^1] == '.':
    return
  try:
    let at = parseFloat(tail)
    if at >= 0 and at <= 1:
      return some((name[0 ..< dash], at))
  except ValueError:
    discard

func isStyleName*(s: string): bool =
  ## A name of a style: a lower-case letter, then lower-case letters, digits and hyphens; or the stop of a shade, a name
  ## and its place, `fitness-0.5`.
  s.len > 0 and s[0] in {'a' .. 'z'} and (
    s.allCharsInSet({'a' .. 'z', '0' .. '9', '-'}) or (
      stopOf(s).isSome and
      stopOf(s).get.shade.allCharsInSet({'a' .. 'z', '0' .. '9', '-'})
    )
  )

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

type Hsv = tuple[h, s, v: float] ## h in degrees, 0 to 360; s and v 0 to 1

func toHsv(c: Colour): Hsv =
  let (r, g, b) = (c.r.float / 255, c.g.float / 255, c.b.float / 255)
  let hi = max([r, g, b])
  let d = hi - min([r, g, b])
  result.v = hi
  result.s = (if hi == 0: 0.0 else: d / hi)
  if d > 0:
    let h =
      if hi == r:
        (g - b) / d
      elif hi == g:
        (b - r) / d + 2
      else:
        (r - g) / d + 4
    result.h = floorMod(h * 60, 360)

func toColour(c: Hsv): Colour =
  let f = c.h / 60
  let i = int(floor(f)) mod 6
  let x = f - floor(f)
  let (p, q, t) = (c.v * (1 - c.s), c.v * (1 - c.s * x), c.v * (1 - c.s * (1 - x)))
  let (r, g, b) =
    case i
    of 0:
      (c.v, t, p)
    of 1:
      (q, c.v, p)
    of 2:
      (p, c.v, t)
    of 3:
      (p, q, c.v)
    of 4:
      (t, p, c.v)
    else:
      (c.v, p, q)
  func byte(x: float): uint8 =
    uint8(clamp(round(x * 255), 0.0, 255.0))

  Colour(kind: ckRgb, r: byte(r), g: byte(g), b: byte(b))

func between*(a, b: Colour, k: float): Colour =
  ## The colour `k` (0 to 1) of the way from `a` to `b` (both `#rrggbb`: a bug otherwise), each of h, s and v separately;
  ## h the shorter way round (a grey has no hue, so it takes the other's).
  doAssert a.kind == ckRgb and b.kind == ckRgb
  var (x, y) = (toHsv(a), toHsv(b))
  if x.s == 0:
    x.h = y.h
  if y.s == 0:
    y.h = x.h
  var dh = y.h - x.h
  if dh > 180:
    dh -= 360
  elif dh < -180:
    dh += 360
  toColour(
    (floorMod(x.h + k * dh, 360.0), x.s + k * (y.s - x.s), x.v + k * (y.v - x.v))
  )

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
  # the stops of a shade: from 0 to 1, each place once, each giving the same colours, #rrggbb
  var shades: OrderedTable[string, seq[tuple[at: float, name: string]]]
  for name in result.styles.keys:
    let stop = stopOf(name)
    if stop.isSome and not name.startsWith(altPrefix):
      shades.mgetOrPut(stop.get.shade, @[]).add (stop.get.at, name)
  for shade, stops in shades.mpairs:
    stops.sort()
    if stops[0].at != 0 or stops[^1].at != 1:
      raiseTheme(fmt"the stops of {shade} run from {shade}-0 to {shade}-1", 0)
    for k in 1 ..< stops.len:
      if stops[k].at == stops[k - 1].at:
        raiseTheme(fmt"{stops[k - 1].name} and {stops[k].name} are one place", 0)
    let first = result.styles.getOrDefault(stops[0].name)
    for (_, name) in stops:
      let st = result.styles.getOrDefault(name)
      for (a, b, part) in [(first.fg, st.fg, "fg"), (first.bg, st.bg, "bg")]:
        if a.isSome != b.isSome:
          raiseTheme(
            fmt"{stops[0].name} and {name}: {part} is given in one and not the other", 0
          )
        if b.isSome and b.get.kind != ckRgb:
          raiseTheme(fmt"{name}: a shade's colours are #rrggbb ({part})", 0)

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
  ## Text drawn for a terminal, piece by piece, each piece in a look of its own, with the rule that holds wherever text is
  ## drawn (`Globals.inTheme`, `style.render`): the lines of a table in `lineStyle`.  A look is started where it begins and
  ## reset where it ends.  A backtick is a character like any other: what is typed is a `code` span of a `Line` (`~"..."`),
  ## never found in a text (a name with a backtick in it is drawn with it).
  text*: string ## what is drawn so far
  inForce: string ## the codes of the look being drawn

func draw*(d: var Drawer, theme: Theme, look: Look, text: string) =
  ## Draw `text` in `look`.
  let plain = terminalCodes(look)
  let lines = terminalCodes(look.over(theme.styles.getOrDefault(lineStyle)))
  for r in text.runes:
    var want = plain
    if r.isLineDrawing:
      want = lines
    if want != d.inForce:
      if d.inForce.len > 0:
        d.text.add "\e[0m"
      d.text.add want
      d.inForce = want
    d.text.add $r

func endLine*(d: var Drawer) =
  ## The end of a line: a reset, so that nothing runs on.
  if d.inForce.len > 0:
    d.text.add "\e[0m"
    d.inForce = ""

type Paint* = object
  ## how lines are drawn: the theme in force, and whether in colour at all
  theme*: Theme
  colour*: bool

func shadeOf*(name: string): Option[tuple[base: string, k: float]] =
  ## A shade's name, `fitness,0.37`, as the style it is of and the fraction (0 to 1); none for any other name.
  let comma = name.find(shadeSeparator)
  if comma <= 0:
    return
  try:
    let k = parseFloat(name[comma + 1 ..^ 1])
    if k >= 0 and k <= 1:
      return some((name[0 ..< comma], k))
  except ValueError:
    discard

func stopsOf(theme: Theme, shade: string): seq[tuple[at: float, style: Style]] =
  ## The stops of a shade in the theme, in order (none if it has none).
  for name, st in theme.styles.pairs:
    let stop = stopOf(name)
    if stop.isSome and stop.get.shade == shade:
      result.add (stop.get.at, st)
  result.sort(
    proc(a, b: tuple[at: float, style: Style]): int =
      cmp(a.at, b.at)
  )

func hasShade*(theme: Theme, name: string): bool =
  ## Whether the theme can draw the shade `name`: it has stops for NAME (`NAME-0` ...), or for `default`.
  (name & firstStop) in theme.styles or (defaultStyle & firstStop) in theme.styles

func styleOf(theme: Theme, name: string): Style =
  ## What a style changes: the theme's, or a shade's, interpolated between the two stops either side of its fraction (or
  ## `default`'s stops, when the theme has none of its own for it; an `alt-` shade between the `alt-` stops).
  let shade = shadeOf(name)
  if shade.isNone:
    return theme.styles.getOrDefault(name)
  let (base, k) = shade.get
  let alt = (if base.startsWith(altPrefix): altPrefix else: "")
  var stops = stopsOf(theme, base)
  if stops.len == 0:
    stops = stopsOf(theme, alt & defaultStyle)
  if stops.len == 0:
    return
  var i = 0 # the stop at or below k, the next above it
  while i + 2 < stops.len and stops[i + 1].at <= k:
    inc i
  let (lo, hi) = (stops[i], stops[min(i + 1, stops.high)])
  let f = (if hi.at > lo.at: clamp((k - lo.at) / (hi.at - lo.at), 0.0, 1.0)
  else: 0.0)
  result = lo.style
  if lo.style.fg.isSome and hi.style.fg.isSome:
    result.fg = some(between(lo.style.fg.get, hi.style.fg.get, f))
  if lo.style.bg.isSome and hi.style.bg.isSome:
    result.bg = some(between(lo.style.bg.get, hi.style.bg.get, f))

func lookOf*(theme: Theme, styles: seq[StyleName]): Look =
  ## How text in `styles` looks: the theme's base look with each style over it in turn (`default` goes back to the base;
  ## a style the theme lacks changes nothing).
  let base = baseLook(theme)
  result = base
  for s in styles:
    if $s == defaultStyle:
      result = base
    else:
      result = result.over(styleOf(theme, $s))

func render*(line: Line, paint: Paint): string =
  ## The line as text for a terminal: each look is started (if in colour) where it begins and reset where it ends, and the
  ## line ends with a reset, so that nothing runs on to the next line.  Spans side by side that look the same share one.
  ## The lines of a table or a tree in a span (`│ ─ ├`) are in their style over the span's own (`Drawer`); a `code` span
  ## is a span of its own (in a message it has its backticks, so that the message is one colour).  A space that is not to be broken (`line.noBreak`) is drawn as a space.
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
      )
    else:
      d.draw(paint.theme, lookOf(paint.theme, s.styles), s.text.replace(noBreak, " "))
  d.endLine()
  d.text
