## What each fuzzed reader is made to do with an input and what must hold afterwards (the level-1 tests in tests/*/test_fuzz.nim
## and the libFuzzer harnesses in tests/fuzz/ share it): the expected errors are caught, anything else is a failure.

import std/[options, sequtils, strutils, tables]
import nimchoo/core/errors
import nimchoo/packages/cache/cache
import nimchoo/packages/fit/load
import nimchoo/packages/util/xlsx/xlsx
import nimchoo/packages/util/zip/zipbytes
import nimchoo/packages/web/request

proc useZip*(z: string) {.raises: [ZipError].} =
  ## Everything the program does with a zip file, with the limits it would use (smaller: the test is quick).
  let entries = listEntries(z)
  for name, e in entries:
    discard extractEntry(z, e, 1_000_000)
  discard readEntry(z, "a.txt", 1_000_000)

proc useXlsx*(x: string) {.raises: [XlsxError].} =
  ## Everything the program does with a workbook: open it, read its sheets.
  let wb = openWorkbook(x)
  for sheet in ["One", "Two", "Missing"]:
    try:
      for row in wb.rows(sheet):
        discard row.cell(0)
    except XlsxError:
      discard # (a bad sheet does not stop the others being read)

proc loads*(x: string) {.raises: [ProfileError, XlsxError].} =
  discard loadProfileFromBytes(x)

func hasControl(s: string): bool =
  s.anyIt(it < ' ' or it == '\x7f')

proc requestProblem*(raw: string, pages: seq[WebPage]): string =
  ## What is wrong with what the request checks did with this address, if anything ("" if all is well), given the
  ## pages the server may run.
  let parsed = parseTarget(raw)
  if parsed.isNone:
    return ""
  let t = parsed.get
  if t.path.len == 0 or t.path[0] != '/':
    return "a path that does not start with a slash"
  # the address of a redirect (the Location header, the log)
  let shown = t.withoutParam(tokenParam)
  if shown.hasControl:
    return "a control character in the address of a redirect"
  let again = parseTarget(shown)
  if again.isNone:
    return "the address of a redirect cannot be read"
  if again.get.path != t.path:
    return "the address of a redirect has another path"
  if again.get.query != t.query.filterIt(it[0] != tokenParam):
    return "the address of a redirect has another query"
  let route = route(t, pages)
  if route.isNone:
    return ""
  let rt = route.get
  if rt.isFile:
    if not isCacheFileName(rt.fileName) or '/' in rt.fileName or rt.fileName.hasControl:
      return "a file route that is not a cache file name"
    return ""
  let rule = pages.filterIt(it.command == rt.command)
  if rule.len != 1:
    return "a command that is not on the list"
  var i = 0
  var seen: seq[string]
  if rt.args.len > 0 and not rt.args[0].startsWith("--"):
    # (the word of a command that takes one: it passed its check)
    if rule[0].word == nil or not rule[0].word(rt.args[0]):
      return "a word that the command does not take, or that is not one"
    inc i
  while i < rt.args.len:
    let a = rt.args[i]
    if not a.startsWith("--") or a == "--worker":
      return "an argument that is not an option of the command"
    let name = a[2 .. ^1]
    if name in seen:
      return "an option twice"
    seen.add name
    if name in rule[0].flags:
      inc i
    elif rule[0].options.anyIt(it.name == name):
      # (an option takes one word)
      var j = i + 1
      while j < rt.args.len and j == i + 1:
        let v = rt.args[j]
        if v.len == 0 or v.hasControl or v.anyIt(it == ' ') or "--" in v:
          return "an option with a value that is not one"
        inc j
      if j == i + 1:
        return "an option with no value"
      i = j
    else:
      return "an option the command does not have"
  ""
