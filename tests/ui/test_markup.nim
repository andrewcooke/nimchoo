import std/[sequtils, strutils, unittest]
import nimchoo/core/errors
import nimchoo/core/theme
import nimchoo/packages/ui/[markup, style]

proc problem(text: string): string =
  try:
    discard parseMarkup(text)
    "no error"
  except MarkupError as e:
    e.msg

func piece(text: string, styles: varargs[string]): Span =
  var names: seq[StyleName]
  for s in styles:
    names.add anyStyle(s)
  Span(text: text, styles: names)

suite "ui markup: reading":
  test "text with no markup is one piece in no style":
    check parseMarkup("plain text") == @[@[piece("plain text")]]
    check parseMarkup("") == @[newSeq[Span]()]

  test "a style covers its text, and the space after its name is not text":
    check parseMarkup("<good imported> 3 files") ==
      @[@[piece("imported", "good"), piece(" 3 files")]]
    check parseMarkup("<good  two>") == @[@[piece(" two", "good")]]

  test "styles nest, the outermost first":
    check parseMarkup("<em a <hide b> c>") ==
      @[@[piece("a ", "em"), piece("b", "em", "hide"), piece(" c", "em")]]

  test "a style runs over a newline, and each line has its own pieces":
    check parseMarkup("<hide one\ntwo> three") ==
      @[@[piece("one", "hide")], @[piece("two", "hide"), piece(" three")]]

  test "brackets and backslashes are escaped with a backslash":
    check parseMarkup("\\<x\\> a\\\\b") == @[@[piece("<x> a\\b")]]
    check parseMarkup("<em \\>>") == @[@[piece(">", "em")]]

  test "markup that cannot be read is refused, with where":
    check problem("a > b") == "at 3: this > closes no style (write \\> for a >)"
    check problem("a <em b") == "at 3: <em is not closed"
    check problem("< x>").startsWith("at 1: a < starts a style")
    check problem("<Em x>").startsWith("at 1: a < starts a style")
    check problem("<em>") ==
      "at 4: the name of a style is followed by a space: <em text>"
    check problem("a \\n").startsWith("at 3: a backslash goes only before")

suite "ui markup: drawing":
  let t = parseTheme("default fg=white\nem weight=bold\nred fg=red\nline underline=yes")

  func looks(t: Theme, text: string): seq[Look] =
    for sp in parseMarkup(text)[0]:
      result.add lookOf(t, sp.styles)

  test "every span has the base look with its styles over it, in order":
    let p = looks(t, "a <red b <em c>> <line <red d>>")
    check p[0] == baseLook(t)
    check p[1].fg == Colour(kind: ckBasic, index: 1)
    check p[2].fg == Colour(kind: ckBasic, index: 1)
    check p[2].weight == wtBold
    check p[4].underline
    check p[4].fg == Colour(kind: ckBasic, index: 1)

  test "default inside a style goes back to the base look":
    check looks(t, "<em <line <default x>>>")[0] == baseLook(t)

  test "a style the theme does not have changes nothing":
    check looks(t, "<red a <blue b>>")[1] == looks(t, "<red a>")[0]

  test "each span starts its look and ends with a reset; without colour, only the text":
    let red = parseTheme("red fg=red")
    check styled(Paint(theme: red, colour: true), "a <red b>\n<red c> d") ==
      @["a \e[31mb\e[0m", "\e[31mc\e[0m d"]
    check styled(Paint(theme: red, colour: false), "a <red b>\n<red c> d") ==
      @["a b", "c d"]

suite "ui markup: styled, read when compiled":
  test "the markup is read, and the values are put in as fmt puts them":
    let n = 3
    let l = styled"<good imported> {n} files <hide ({1.25:.2f}s)>"
    check l.text == "imported 3 files (1.25s)"
    check l.mapIt($it.styles) == @["@[good]", "@[]", "@[hide]"]

  test "a value is plain text, whatever it holds":
    let name = "<bad> x \\<y"
    let l = styled"<em {name}>"
    check l.len == 1 and l[0].text == name and l[0].styles == @[anyStyle("em")]

  test "braces are doubled, as in fmt; a line with nothing is empty":
    check styled"{{x}}".text == "{x}"
    check styled"".len == 0

  test "markup that cannot be read, or a style the built-in theme lacks, does not compile":
    check compiles(styled"<good x>")
    check not compiles(styled"<goood x>")
    check not compiles(styled"<good x")
    check not compiles(styled"x {y")
    check not compiles(styled"x }")
