## Styled text: a line is a list of spans, each a piece of text in the styles it is in (the outermost first; none: plain
## text).  A style is a name; what it looks like is the theme's to say (`theme.nim`), so the same line is drawn in whatever
## theme is in force, and with or without colour (`ui/style.render()`).  Lines, not strings full of escape codes, so that
## they can be measured, wrapped, cut to a width and laid out in tables (`ruled.nim`) without splitting a code.  The one kind
## of styled text: the usages, the views and the messages are all made of it (markup, `~"..."` of `ui/markup`, makes it too).
##
## The styles the program uses are one list (`programStyles`), and a name written in the code is checked against it when it
## is compiled (`span("failed", "bad")`, `styleName"select"`): a misspelt style is a compile error.  The built-in themes
## define them all (a test checks); a theme that lacks one draws its text as the text around it.

import std/strutils
from std/unicode import Rune, runeLen, runeSubStr, runes

{.push raises: [].}

const
  baseStyles* =
    ["default", "em", "hide", "select", "good", "bad", "warn", "code", "file"]
    ## the styles the program uses, each for one thing: `default` around everything; `em` what to read first (titles,
    ## headings); `hide` the bookkeeping, what was not recorded, the lines of tables; `select` the selection and nothing
    ## else; `good` done; `bad` failed, deleted; `warn` advisory; `code` literal text (a command, an option, a name in
    ## the program: what is between backticks); `file` the path of a file or a directory
  codeStyle* = "code"
    ## the style of literal text (`` `nch climbs` `` in `~"..."` is `<code nch climbs>`): in colour the style marks it;
    ## without colour, and inside a warning or a failure, backticks round it do (`text`, `theme.render`)
  altPrefix* = "alt-"
    ## every other row of a table that asks for it (`alternated`) is in the alt version of each style: `alt-default` for
    ## plain text, `alt-code` for `code` ...; a theme defines each as the style it stands for unless it says otherwise (`theme.parseTheme`)

func withAlts(names: openArray[string]): seq[string] =
  for n in names:
    result.add n
  for n in names:
    result.add altPrefix & n

const programStyles* = withAlts(baseStyles)
  ## the styles the program uses, each for one thing, and the `alt` version of each: the names in the code are checked
  ## against these

type
  StyleName* = distinct string ## the name of a style

  Span* = object
    text*: string
    styles*: seq[StyleName] ## the outermost first; none: plain text

  Line* = seq[Span]

func `==`*(a, b: StyleName): bool {.borrow.}
func `$`*(s: StyleName): string {.borrow.}

const ellipsis = "…"

template styleName*(name: static string): StyleName =
  ## The style `name`, which must be one the program uses (`programStyles`, checked when compiled).
  static:
    doAssert name in programStyles,
      "no style '" & name & "' (the program uses " & programStyles.join(", ") & ")"
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

const noBreak* = "\u00A0"
  ## a space that a line is not broken at when it is wrapped (`unbroken`); drawn as a space (`theme.render`)

func unbroken*(text: string): string =
  ## `text` kept on one line when it is wrapped: an item of a list ("route (importer)").
  text.replace(" ", noBreak)

func within*(line: Line, style: StyleName): Line =
  ## The line with `style` outside the styles of each span (a message in `bad` or `warn`: `theme.render` draws it in one
  ## colour, its literal text with backticks).
  for s in line:
    result.add Span(text: s.text, styles: @[style] & s.styles)

func plain*(text: string): Line =
  ## A line of text with no style.
  @[span(text)]

func width*(line: Line): int =
  ## Columns the line takes (one per character: wide characters are not counted as two).
  for s in line:
    result += s.text.runeLen

func isCode*(s: Span): bool =
  ## Whether the span is literal text (`codeStyle`, or its `alt` version).
  for st in s.styles:
    if string(st) == codeStyle or string(st) == altPrefix & codeStyle:
      return true

func text*(line: Line): string =
  ## The line's text, without any styling (what it measures and holds).
  for s in line:
    result.add s.text

func plainText*(line: Line): string =
  ## The line as it is drawn without colour, and as it is logged: literal text (`isCode`) between backticks, its mark when
  ## there is no colour.  (Two columns wider than `text` for each piece of literal text: a table or a usage laid out by
  ## `width` is that much out of line without colour; decided 2026-11-20 not to matter.)
  for s in line:
    if s.isCode:
      result.add '`' & s.text & '`'
    else:
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

func isBetween(text: string): bool =
  ## Whether `text` is only what goes between the columns of a table: spaces and box-drawing characters (U+2500 to U+257F).
  for r in text.runes:
    if int32(r) != int32(' ') and int32(r) notin 0x2500'i32 .. 0x257F'i32:
      return false
  true

func joined(line: Line): Line =
  ## The spans side by side that have the same styles made one; empty ones dropped.
  for s in line:
    if s.text.len == 0:
      continue
    if result.len > 0 and result[^1].styles == s.styles:
      result[^1].text.add s.text
    else:
      result.add s

func merged*(line: Line): Line =
  ## The line with the spans that have the same styles side by side made one (empty ones dropped), and the plain spaces
  ## (and lines of a table) between two spans in the selection's style in that style: so that the selection (a row of it,
  ## the columns about it) is one band, without gaps between the columns.  (Only the selection: two names of packages side
  ## by side stay two.)
  var spans = joined(line)
  for i in 1 ..< spans.high:
    if spans[i].styles.len == 0 and spans[i].text.isBetween and
        styleName"select" in spans[i - 1].styles and
        spans[i - 1].styles == spans[i + 1].styles:
      spans[i].styles = spans[i - 1].styles
  joined(spans)

func stripped*(line: Line): Line =
  ## The line without the spaces at its end.
  result = line.merged
  while result.len > 0:
    result[^1].text = result[^1].text.strip(leading = false)
    if result[^1].text.len > 0:
      break
    result.setLen(result.len - 1)

func bracketed*(line: Line, selected: bool): Line =
  ## The line marked for where there is no colour, as the calendar marks a day: `[` before it and `]` after it if it is
  ## `selected`, a space before it if not (so that lines with and without the mark line up).
  if selected:
    @[span("[")] & line & @[span("]")]
  else:
    @[span(" ")] & line

func alternated*(line: Line): Line =
  ## The line in the alt version of each of its styles (`alt-code` for `code`; `alt-default` for plain text): a row of a
  ## table told from its neighbours (`ruled.ruledRows(alternate)`), whatever the theme makes of it.
  for s in line:
    var styles: seq[StyleName]
    for st in s.styles:
      styles.add StyleName(
        if ($st).startsWith(altPrefix):
          $st
        else:
          altPrefix & $st
      )
    if styles.len == 0:
      styles = @[StyleName(altPrefix & "default")]
    result.add Span(text: s.text, styles: styles)

func wrapped*(line: Line, width: int): seq[Line] =
  ## The line broken into lines of at most `width` characters at spaces (a longer word has a line of its own, a newline
  ## starts a new line, two spaces after a full stop stay two unless the line ends there); each word keeps its styles, and
  ## a space between two words in the same style is in it too (a phrase in a style is not broken by plain spaces).
  var paragraphs: seq[seq[Line]] =
    @[@[newSeq[Span]()]] # paragraphs of words, a word being spans
  for s in line:
    var piece = ""
    for ch in s.text:
      case ch
      of ' ':
        paragraphs[^1][^1].add Span(text: piece, styles: s.styles)
        piece = ""
        paragraphs[^1].add newSeq[Span]()
      of '\n':
        paragraphs[^1][^1].add Span(text: piece, styles: s.styles)
        piece = ""
        paragraphs.add @[newSeq[Span]()]
      else:
        piece.add ch
    paragraphs[^1][^1].add Span(text: piece, styles: s.styles)
  for words in paragraphs:
    var current: Line
    var length = 0
    var started = false
    for word in words:
      let n = word.text.runeLen
      if not started:
        current = word
        length = n
        started = true
      elif length + 1 + n <= width:
        let between =
          if current.len > 0 and word.len > 0 and current[^1].styles == word[0].styles:
            current[^1].styles
          else:
            @[]
        current.add Span(text: " ", styles: between)
        current.add word
        length += 1 + n
      else:
        result.add current.stripped
        current = word
        length = n
    result.add current.stripped
