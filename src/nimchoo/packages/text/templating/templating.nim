## Page templates: text with `{{tags}}` that are filled in from values.  A subset of Mustache
## (https://mustache.github.io), enough for the pages and small enough to read in one sitting.
##
##     {{name}}            the value, with & < > " escaped for HTML
##     {{{name}}}          the value as it is (also `{{&name}}`): for what is trusted, such as a
##                         URL, a hash or `true`
##     {{! a comment }}    nothing
##
## A comment on a line of its own leaves no blank line.  Names are letters, digits, `_` and `-`.
##
## Unlike Mustache, a name that nothing has is an error (`TemplateError`, with the line), because in
## a page it means a mistake in the template or in the code, not an empty space.  Sections, loops,
## partials and lambdas are not here: no page uses them, and a library can give them if one ever does.
##
## Pure: text and values in, text out.

import std/[sequtils, strutils, tables]
import ../../../core/errors
export errors

{.push raises: [].}

type
  Value* = object
    text*: string

  Context* = ref object
    values: Table[string, Value]

func text*(s: string): Value =
  ## A value that is text.
  Value(text: s)
func flag*(b: bool): Value =
  ## A value that is yes or no, shown as `true` or `false` (for use in a script).
  Value(text: if b: "true" else: "false")

func context*(values: openArray[(string, Value)]): Context =
  ## The values of a page.
  result = Context(values: initTable[string, Value]())
  for (k, v) in values:
    result.values[k] = v

func htmlEscape*(s: string): string =
  ## `s` as text in a page: markup in it is shown, not obeyed.
  for c in s:
    case c
    of '<':
      result.add "&lt;"
    of '>':
      result.add "&gt;"
    of '&':
      result.add "&amp;"
    of '"':
      result.add "&quot;"
    else:
      result.add c

type
  Kind = enum
    kText
    kVar
    kRaw
    kComment

  Token = object
    kind: Kind
    text: string ## the text, or the name
    line: int

  Template* = object
    tokens: seq[Token] ## text, variables and raw variables (comments are gone)

func isNameChar(c: char): bool =
  c in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-'}

proc tokenize(source: string): seq[Token] {.raises: [TemplateError].} =
  ## The template cut into text and tags.
  var i = 0
  var line = 1
  var textStart = 0
  template flushText(upTo: int) =
    if upTo > textStart:
      result.add Token(kind: kText, text: source[textStart ..< upTo], line: line)

  while i < source.len:
    if source[i] == '\n':
      inc line
    if i + 1 < source.len and source[i] == '{' and source[i + 1] == '{':
      let triple = i + 2 < source.len and source[i + 2] == '{'
      let closer = if triple: "}}}" else: "}}"
      let bodyStart = i + (if triple: 3 else: 2)
      let stop = source.find(closer, bodyStart)
      if stop < 0:
        raiseTemplate("a tag is not closed", line)
      let body = source[bodyStart ..< stop].strip
      flushText(i)
      var kind = kVar
      var name = body
      if triple:
        kind = kRaw
      elif body.len > 0:
        case body[0]
        of '&':
          kind = kRaw
          name = body[1 .. ^1].strip
        of '!':
          kind = kComment
          name = ""
        else:
          discard
      if kind != kComment and (name.len == 0 or not name.allIt(isNameChar(it))):
        raiseTemplate("'" & body & "' is not a name", line)
      result.add Token(kind: kind, text: name, line: line)
      for c in source[i ..< stop + closer.len]:
        if c == '\n':
          inc line
      i = stop + closer.len
      textStart = i
    else:
      inc i
  flushText(source.len)

proc isBlank(s: string): bool =
  s.allIt(it in {' ', '\t', '\r'})

proc standalone(tokens: var seq[Token]) =
  ## A comment on a line of its own takes the whole line with it.
  var lineStartAt = -1 # the text that begins a line because a tag took the line before
  for k in 0 ..< tokens.len:
    if tokens[k].kind != kComment:
      continue
    var before = "" # what is on the line before the tag
    var beforeOk = k == 0
    if k > 0 and tokens[k - 1].kind == kText:
      let t = tokens[k - 1].text
      let nl = t.rfind('\n')
      before = t[nl + 1 .. ^1]
      beforeOk = isBlank(before) and (nl >= 0 or k - 1 == 0 or k - 1 == lineStartAt)
    var afterOk = k == tokens.high
    var skip = 0 # how much of the text after the tag goes
    if k < tokens.high and tokens[k + 1].kind == kText:
      let t = tokens[k + 1].text
      let nl = t.find('\n')
      if nl >= 0 and isBlank(t[0 ..< nl]):
        afterOk = true
        skip = nl + 1
      elif nl < 0 and isBlank(t) and k + 1 == tokens.high:
        afterOk = true
        skip = t.len
    if beforeOk and afterOk:
      if before.len > 0:
        tokens[k - 1].text =
          tokens[k - 1].text[0 ..< tokens[k - 1].text.len - before.len]
      if skip > 0:
        tokens[k + 1].text = tokens[k + 1].text[skip .. ^1]
        lineStartAt = k + 1

proc parse*(source: string): Template {.raises: [TemplateError].} =
  ## The template, ready to fill in.  Raises TemplateError if a tag is wrong.
  var tokens = tokenize(source)
  standalone(tokens)
  for t in tokens:
    if t.kind != kComment and not (t.kind == kText and t.text.len == 0):
      result.tokens.add t

proc render*(t: Template, values: Context): string {.raises: [TemplateError].} =
  ## The template filled in.  Raises TemplateError for a name the values do not have.
  for tok in t.tokens:
    case tok.kind
    of kText:
      result.add tok.text
    of kVar, kRaw:
      if not values.values.hasKey(tok.text):
        raiseTemplate("there is no value called '" & tok.text & "'", tok.line)
      let s = values.values.getOrDefault(tok.text).text
      result.add (if tok.kind == kVar: htmlEscape(s) else: s)
    of kComment:
      discard

proc render*(source: string, values: Context): string {.raises: [TemplateError].} =
  ## `parse` and `render` in one.
  render(parse(source), values)
