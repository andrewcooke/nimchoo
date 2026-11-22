## Styled text is written with `~"..."` (`<good imported>`), not built from `span(text, "good")`: a literal style name in a
## `span(...)` is refused outside `core/` and `ui/`, which are the builders.  A style chosen by a value (`span(text, style)`),
## a line that is a join of data (the cells of a table) and `span(text)` with no style are fine.  A test over the whole source
## for the class of mistake: a new line of output built the old way.

import std/[os, strutils, unittest]

func callArgs(src: string, open: int): seq[string] =
  ## The top-level arguments of the call whose `(` is at `open`: strings are skipped over, brackets counted.
  var depth = 0
  var cur = ""
  var i = open
  while i < src.len:
    let c = src[i]
    if c == '"':
      cur.add c
      inc i
      while i < src.len and src[i] != '"':
        if src[i] == '\\' and i + 1 < src.len:
          cur.add src[i]
          inc i
        cur.add src[i]
        inc i
      cur.add '"'
    elif c in {'(', '[', '{'}:
      inc depth
      if depth > 1:
        cur.add c
    elif c in {')', ']', '}'}:
      dec depth
      if depth == 0:
        result.add cur.strip
        return
      cur.add c
    elif c == ',' and depth == 1:
      result.add cur.strip
      cur = ""
    else:
      cur.add c
    inc i

func literalStyles(src: string): seq[int] =
  ## The lines of the `span(` calls whose second argument is a literal style name ("good", styleName"good").
  var at = 0
  while true:
    at = src.find("span(", at)
    if at < 0:
      break
    let open = at + 4
    if at == 0 or src[at - 1] notin IdentChars + {'.', '"'}:
      let args = callArgs(src, open)
      if args.len >= 2 and
          (args[1].startsWith("\"") or args[1].startsWith("styleName\"")):
        result.add src[0 ..< at].count('\n') + 1
    at = open

suite "spans: styled text is written as markup":
  test "the checker finds a literal style, and leaves a value, a plain span and a table's cells":
    check literalStyles("let a = span(\"x\", \"good\")").len == 1
    check literalStyles("let a = span(x & \", \", styleName\"bad\")").len == 1
    check literalStyles("let a = span(text, style)").len == 0
    check literalStyles("let a = span(\"a, b\")").len == 0
    check literalStyles("let a = span(f(x, \"y\"), selectedStyle)").len == 0

  test "no span names its style as a literal outside core and ui":
    var bad: seq[string]
    for path in walkDirRec("src"):
      let slashed = path.replace('\\', '/')
      if path.endsWith(".nim") and not path.endsWith("registry.nim") and
          not slashed.startsWith("src/nimchoo/core/") and
          not slashed.startsWith("src/nimchoo/packages/ui/"):
        for line in literalStyles(readFile(path)):
          bad.add path & ":" & $line
    check bad.len == 0
    if bad.len > 0:
      echo "write ~\"<style text>\" instead of span(text, \"style\"):\n" & bad.join(
        "\n"
      )
