## Page templates: text with `{{tags}}` that are filled in from values.  A subset of Mustache
## (https://mustache.github.io), enough for the pages and small enough to read in one sitting.
##
##     {{name}}            the value, with & < > " escaped for HTML
##     {{{name}}}          the value as it is (also `{{&name}}`): for what is trusted, such as a
##                         URL, a hash or `true`
##     {{#name}}..{{/name}}  the part is shown if the value is true, a text that is not empty, or
##                         a list (once for each item, which can have values of its own); not shown
##                         if it is false, empty or missing
##     {{^name}}..{{/name}}  the part is shown if that is the other way round
##     {{! a comment }}    nothing
##
## A tag on a line of its own (a section or its end, or a comment) leaves no blank line.  Names are
## letters, digits, `_` and `-`.  Inside a list's item, names the item lacks are looked up in the
## values around it.
##
## Unlike Mustache, a name that nothing has is an error (`TemplateError`, with the line), because in
## a page it means a mistake in the template or in the code, not an empty space.  More (loops over
## lists of lists, partials, lambdas) can come from a library if it is ever wanted.
##
## Pure: text and values in, text out.

import std/[sequtils, strutils, tables]
import ./errors
export errors

{.push raises: [].}

type
  ValueKind* = enum vkText, vkFlag, vkList

  Context* = ref object
    values: Table[string, Value]

  Value* = object
    case kind*: ValueKind
    of vkText: text*: string
    of vkFlag: flag*: bool
    of vkList: items*: seq[Context]

func text*(s: string): Value = Value(kind: vkText, text: s)
func flag*(b: bool): Value = Value(kind: vkFlag, flag: b)
func list*(items: seq[Context]): Value = Value(kind: vkList, items: items)

func context*(values: openArray[(string, Value)]): Context =
  ## The values of a page (or of one item of a list).
  result = Context(values: initTable[string, Value]())
  for (k, v) in values: result.values[k] = v

func htmlEscape*(s: string): string =
  ## `s` as text in a page: markup in it is shown, not obeyed.
  for c in s:
    case c
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '&': result.add "&amp;"
    of '"': result.add "&quot;"
    else: result.add c

type
  Kind = enum kText, kVar, kRaw, kOpen, kInverted, kClose, kComment

  Token = object
    kind: Kind
    text: string          ## the text, or the name
    line: int

  NodeKind = enum nText, nVar, nRaw, nSection

  Node = ref object
    kind: NodeKind
    text: string          ## the text, or the name
    inverted: bool
    children: seq[Node]
    line: int

  Template* = object
    nodes: seq[Node]

func isNameChar(c: char): bool = c in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-'}

proc tokenize(source: string): seq[Token] {.raises: [TemplateError].} =
  ## The template cut into text and tags.
  var i = 0
  var line = 1
  var textStart = 0
  template flushText(upTo: int) =
    if upTo > textStart: result.add Token(kind: kText, text: source[textStart ..< upTo], line: line)
  while i < source.len:
    if source[i] == '\n': inc line
    if i + 1 < source.len and source[i] == '{' and source[i + 1] == '{':
      let triple = i + 2 < source.len and source[i + 2] == '{'
      let closer = if triple: "}}}" else: "}}"
      let bodyStart = i + (if triple: 3 else: 2)
      let stop = source.find(closer, bodyStart)
      if stop < 0: raiseTemplate("a tag is not closed", line)
      let body = source[bodyStart ..< stop].strip
      flushText(i)
      var kind = kVar
      var name = body
      if triple: kind = kRaw
      elif body.len > 0:
        case body[0]
        of '&': kind = kRaw; name = body[1 .. ^1].strip
        of '#': kind = kOpen; name = body[1 .. ^1].strip
        of '^': kind = kInverted; name = body[1 .. ^1].strip
        of '/': kind = kClose; name = body[1 .. ^1].strip
        of '!': kind = kComment; name = ""
        else: discard
      if kind != kComment and (name.len == 0 or not name.allIt(isNameChar(it))):
        raiseTemplate("'" & body & "' is not a name", line)
      result.add Token(kind: kind, text: name, line: line)
      for c in source[i ..< stop + closer.len]:
        if c == '\n': inc line
      i = stop + closer.len
      textStart = i
    else:
      inc i
  flushText(source.len)

proc isBlank(s: string): bool = s.allIt(it in {' ', '\t', '\r'})

proc standalone(tokens: var seq[Token]) =
  ## A section tag, its end or a comment on a line of its own takes the whole line with it.
  var lineStartAt = -1                               # the text that begins a line because a tag took the line before
  for k in 0 ..< tokens.len:
    if tokens[k].kind notin {kOpen, kInverted, kClose, kComment}: continue
    var before = ""                                  # what is on the line before the tag
    var beforeOk = k == 0
    if k > 0 and tokens[k - 1].kind == kText:
      let t = tokens[k - 1].text
      let nl = t.rfind('\n')
      before = t[nl + 1 .. ^1]
      beforeOk = isBlank(before) and (nl >= 0 or k - 1 == 0 or k - 1 == lineStartAt)
    var afterOk = k == tokens.high
    var skip = 0                                     # how much of the text after the tag goes
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
      if before.len > 0: tokens[k - 1].text = tokens[k - 1].text[0 ..< tokens[k - 1].text.len - before.len]
      if skip > 0:
        tokens[k + 1].text = tokens[k + 1].text[skip .. ^1]
        lineStartAt = k + 1

proc parse*(source: string): Template {.raises: [TemplateError].} =
  ## The template, ready to fill in.  Raises TemplateError if a tag is wrong.
  var tokens = tokenize(source)
  standalone(tokens)
  var stack: seq[Node] = @[Node(kind: nSection, text: "", children: @[])]    # the root, then each open section
  for t in tokens:
    case t.kind
    of kText:
      if t.text.len > 0: stack[^1].children.add Node(kind: nText, text: t.text, line: t.line)
    of kVar: stack[^1].children.add Node(kind: nVar, text: t.text, line: t.line)
    of kRaw: stack[^1].children.add Node(kind: nRaw, text: t.text, line: t.line)
    of kComment: discard
    of kOpen, kInverted:
      let n = Node(kind: nSection, text: t.text, inverted: t.kind == kInverted, line: t.line)
      stack[^1].children.add n
      stack.add n
    of kClose:
      if stack.len == 1: raiseTemplate("{{/" & t.text & "}} closes nothing", t.line)
      if stack[^1].text != t.text:
        raiseTemplate("{{/" & t.text & "}} closes {{#" & stack[^1].text & "}} (opened on line " &
                      $stack[^1].line & ")", t.line)
      stack.setLen stack.len - 1
  if stack.len > 1:
    raiseTemplate("{{#" & stack[^1].text & "}} is never closed", stack[^1].line)
  Template(nodes: stack[0].children)

proc lookup(scopes: seq[Context], name: string, line: int): Value {.raises: [TemplateError].} =
  for i in countdown(scopes.high, 0):
    if scopes[i].values.hasKey(name):
      for k, v in scopes[i].values:
        if k == name: return v
  raiseTemplate("there is no value called '" & name & "'", line)

func shows(v: Value): bool =
  ## Whether a section on the value is shown.
  case v.kind
  of vkText: v.text.len > 0
  of vkFlag: v.flag
  of vkList: v.items.len > 0

proc renderNodes(nodes: seq[Node], scopes: seq[Context], output: var string) {.raises: [TemplateError].} =
  for n in nodes:
    case n.kind
    of nText: output.add n.text
    of nVar, nRaw:
      let v = lookup(scopes, n.text, n.line)
      let s = case v.kind
        of vkText: v.text
        of vkFlag: (if v.flag: "true" else: "false")
        of vkList: raiseTemplate("'" & n.text & "' is a list, which a tag cannot show", n.line)
      output.add (if n.kind == nVar: htmlEscape(s) else: s)
    of nSection:
      let v = lookup(scopes, n.text, n.line)
      if n.inverted:
        if not shows(v): renderNodes(n.children, scopes, output)
      elif shows(v):
        if v.kind == vkList:
          for item in v.items: renderNodes(n.children, scopes & @[item], output)
        else:
          renderNodes(n.children, scopes, output)

proc render*(t: Template, values: Context): string {.raises: [TemplateError].} =
  ## The template filled in.  Raises TemplateError for a name the values do not have.
  renderNodes(t.nodes, @[values], result)

proc render*(source: string, values: Context): string {.raises: [TemplateError].} =
  ## `parse` and `render` in one.
  render(parse(source), values)
