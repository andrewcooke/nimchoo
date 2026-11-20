## Styled text written as markup, the way all output is written: `~"<good imported> {n} files <hide ({t:.1f}s)>"`.  A `<`
## opens a style, named by the word after it and ended by one space; the matching `>` closes it.  (Angle brackets, as they
## are rare in the program's text; `[` is in every synopsis.)  Text between backticks is literal text: `` `nch climbs` `` is
## exactly `<code nch climbs>`.  Styles nest, and a nested one changes only the attributes it gives (`core/theme.nim`);
## `<default ...>` goes back to the look of plain text, whatever is around it.  A backslash before `<`, `>`, a backtick or a
## backslash is that character.
##
## A style may run over a newline: the text is read into lines (`style.Line`), and each span carries its styles, so a line
## is drawn on its own (it starts from nothing and ends with a reset), and can be cut or printed without the next.
##
## Reading the markup needs no theme, so it can be checked before a theme is known.  There is no fixed set of styles: a
## name is whatever a theme defines, and one the theme lacks changes nothing.

import std/[macros, strformat, strutils]
import ../../core/[errors, line]
import ./style

{.push raises: [].}

func parseMarkup*(text: string): seq[Line] {.raises: [MarkupError].} =
  ## The lines of `text`.
  result = @[newSeq[Span]()]
  var open: seq[tuple[name: string, at: int, tick: bool]]
    # (tick: opened by a backtick, which closes it)
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
      if i + 1 < text.len and text[i + 1] in {'<', '>', '\\', '`'}:
        buffer.add text[i + 1]
        i += 2
      else:
        raiseMarkup(
          "a backslash goes only before <, >, ` or \\ (write \\\\ for a backslash)",
          i + 1,
        )
    of '`':
      flush()
      if open.len > 0 and open[^1].tick:
        discard open.pop()
      else:
        open.add (codeStyle, i + 1, true)
      inc i
    of '<':
      var j = i + 1
      while j < text.len and text[j] in {'a' .. 'z', '0' .. '9', '-'}:
        inc j
      let name = text[i + 1 ..< j]
      if not isStyleName(name):
        raiseMarkup(
          "a < starts a style, so the name of one follows it (write \\< for a <)", i + 1
        )
      if j >= text.len or text[j] != ' ':
        raiseMarkup(
          fmt"the name of a style is followed by a space: <{name} text>", j + 1
        )
      flush()
      open.add (name, i + 1, false)
      i = j + 1
    of '>':
      if open.len == 0:
        raiseMarkup("this > closes no style (write \\> for a >)", i + 1)
      if open[^1].tick:
        raiseMarkup(
          "a > inside literal text (write \\> for a >, or close the backtick first)",
          i + 1,
        )
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
    if open[^1].tick:
      raiseMarkup("a backtick is not closed (write \\` for a backtick)", open[^1].at)
    raiseMarkup(fmt"<{open[^1].name} is not closed", open[^1].at)
  flush()

const
  holeStart = '\x01' ## (where a value goes, while the markup around it is read)
  holeEnd = '\x02'

func holes(
    text: string
): tuple[markup: string, exprs: seq[string]] {.raises: [MarkupError].} =
  ## `text` with each `{...}` replaced by a mark that the markup leaves alone, and what was in them; `{{` and `}}` are
  ## braces, as in `fmt`.
  var i = 0
  while i < text.len:
    let c = text[i]
    if c == '{' and i + 1 < text.len and text[i + 1] == '{':
      result.markup.add '{'
      i += 2
    elif c == '}' and i + 1 < text.len and text[i + 1] == '}':
      result.markup.add '}'
      i += 2
    elif c == '{':
      let close = text.find('}', i + 1)
      if close < 0:
        raiseMarkup("a { is not closed (write {{ for a brace)", i + 1)
      result.markup.add holeStart & $result.exprs.len & holeEnd
      result.exprs.add text[i + 1 ..< close]
      i = close + 1
    elif c == '}':
      raiseMarkup("this } closes nothing (write }} for a brace)", i + 1)
    elif c in {holeStart, holeEnd}:
      raiseMarkup("a control character in the text", i + 1)
    else:
      result.markup.add c
      inc i

macro `~`*(literal: string{lit}): Line =
  ## A line written as markup, with values as `fmt` puts them (`~"<good imported> {n} files <hide ({t:.1f}s)>"`).  The
  ## markup is read when the program is compiled: a bracket or a backtick not closed, or a style the program does not use
  ## (`programStyles`), is a compile error.  A value is text, whatever it holds: no markup is read in it (an activity called
  ## `<bad>` or with a backtick in its name is not markup).  One line: a newline is an error (one `~` per line).
  let text = literal.strVal
  var lines: seq[Line]
  var exprs: seq[string]
  try:
    let h = holes(text)
    exprs = h.exprs
    lines = parseMarkup(h.markup)
  except MarkupError as e:
    error("~: " & e.msg, literal)
  if lines.len != 1:
    error("~: one line only (a newline is not allowed)", literal)
  let spans = nnkBracket.newTree()
  for sp in lines[0]:
    var names = nnkBracket.newTree()
    for s in sp.styles:
      if $s notin programStyles:
        error(
          "~: there is no style '" & $s & "' (the program uses " &
            programStyles.join(", ") & ")",
          literal,
        )
      names.add newCall(bindSym"anyStyle", newLit($s))
    # the text: literal pieces and the values (as `fmt` puts them), joined; no markup is read in a value
    var parts: seq[NimNode]
    var piece = ""
    var i = 0
    let t = sp.text
    while i < t.len:
      if t[i] == holeStart:
        let close = t.find(holeEnd, i)
        if piece.len > 0:
          parts.add newLit(piece)
          piece = ""
        let k = parseInt(t[i + 1 ..< close])
        parts.add newCall(bindSym"fmt", newLit("{" & exprs[k] & "}"))
        i = close + 1
      else:
        piece.add t[i]
        inc i
    if piece.len > 0 or parts.len == 0:
      parts.add newLit(piece)
    var joined = parts[0]
    for p in parts[1 ..^ 1]:
      joined = infix(joined, "&", p)
    spans.add nnkObjConstr.newTree(
      bindSym"Span",
      nnkExprColonExpr.newTree(ident"text", joined),
      nnkExprColonExpr.newTree(ident"styles", prefix(names, "@")),
    )
  result = newCall(bindSym"@", spans)
  if spans.len == 0:
    result = quote:
      newSeq[Span]()
