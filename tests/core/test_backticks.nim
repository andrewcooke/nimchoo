## What a person would type (an option, a command) is between backticks in every text the program shows, so that it is drawn
## in the style of what is typed (`theme.typedStyle`; without colour, the backticks mark it).  This test reads the string
## literals of the source and fails on any option (`-v`, `--names`) in the prose outside backticks, so that a new text
## cannot forget them.  Synopses (a literal starting `usage: `) are drawn in `code` another way (`usage.synopsisLines()`), and two files
## hold literals that are not prose: the completion script (shell) and the git command lines of `version.nim`.

import std/[os, sequtils, strutils, unittest]

const notProse = ["completion.nim", "version.nim"]
  ## files whose literals are code for other programs

type Literal = tuple[text: string, line: int]

func literals(src: string): seq[Literal] =
  ## The string literals of Nim source: "...", r"..." and fmt"..." (raw: "" is a quote), """...""".  Comments are skipped.
  var i = 0
  var line = 1
  while i < src.len:
    let c = src[i]
    if c == '\n':
      inc line
      inc i
    elif c == '#':
      while i < src.len and src[i] != '\n':
        inc i
    elif c == '\'' and i + 2 < src.len and src[i + 2] == '\'':
      i += 3 # (a character literal: '"')
    elif c == '\'' and i + 3 < src.len and src[i + 1] == '\\' and src[i + 3] == '\'':
      i += 4 # ('\"')
    elif c == '"':
      let start = line
      var text = ""
      if src.continuesWith("\"\"\"", i):
        i += 3
        while i < src.len and not src.continuesWith("\"\"\"", i):
          if src[i] == '\n':
            inc line
          text.add src[i]
          inc i
        i += 3
      else:
        let raw = i > 0 and src[i - 1] in IdentChars # (r"...", fmt"...")
        inc i
        while i < src.len:
          if raw and src[i] == '"' and i + 1 < src.len and src[i + 1] == '"':
            text.add '"'
            i += 2
          elif src[i] == '"':
            inc i
            break
          elif not raw and src[i] == '\\' and i + 1 < src.len:
            text.add src[i .. i + 1]
            i += 2
          else:
            text.add src[i]
            inc i
      result.add (text, start)
    else:
      inc i

func untyped(text: string, inside: var bool): seq[string] =
  ## The options (`-v`, `--names`) in `text` that are not between backticks; `inside` says whether it starts between them,
  ## and is left saying whether it ends between them (a phrase can be split over pieces joined with `&`).
  var outside = ""
  for c in text:
    if c == '`':
      inside = not inside
    elif not inside:
      outside.add c
  var i = 0
  while i < outside.len:
    if outside[i] == '-' and
        (i == 0 or outside[i - 1] notin IdentChars + {'\'', '/', '.', '}', '-'}):
      var j = i + 1
      if j < outside.len and outside[j] == '-':
        inc j
      if j < outside.len and outside[j] in Letters:
        var k = j
        while k < outside.len and outside[k] in IdentChars + {'-'}:
          inc k
        result.add outside[i ..< k]
        i = k
        continue
    inc i

suite "what is typed is between backticks":
  test "every option in the prose of the program is between backticks":
    var found: seq[string]
    let top = currentSourcePath().parentDir.parentDir.parentDir / "src"
    for path in walkDirRec(top):
      if not path.endsWith(".nim") or path.endsWith("registry.nim") or
          notProse.anyIt(path.endsWith(it)):
        continue
      var inside = false
        # (a literal that ends between backticks goes on in the next one: pieces of one text)
      for lit in literals(readFile(path)):
        if ' ' notin lit.text or lit.text.startsWith("usage: "):
          if lit.text.count('`') mod 2 == 1:
            inside = not inside
          continue
        for option in untyped(lit.text, inside):
          found.add path.relativePath(top) & ":" & $lit.line & ": " & option
    check found.len == 0
    if found.len > 0:
      echo found.len, " options outside backticks:"
      for f in found:
        echo "  ", f

  test "the check itself: options outside backticks are found, those inside are not":
    var inside = false
    check untyped("use --names or -v", inside) == @["--names", "-v"]
    check untyped("use `--names 62` or `-v`", inside).len == 0
    check untyped("-33.42,-70.63 and 2018-08-27 and e-bike and {l}-hash", inside).len ==
      0
    check untyped("run `nch climbs ", inside).len == 0 and inside
    check untyped(" --all` now, not --this", inside) == @["--this"] and not inside
    check literals("let a = \"x --y\" # \"not --this\"\nlet b = fmt\"a \"\"q\"\" --z\"") ==
      @[("x --y", 1), ("a \"q\" --z", 2)]
