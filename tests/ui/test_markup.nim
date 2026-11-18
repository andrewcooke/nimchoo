import std/[strutils, unittest]
import nimchoo/core/errors
import nimchoo/packages/ui/[markup, theme]

proc problem(text: string): string =
  try:
    discard parseMarkup(text)
    "no error"
  except MarkupError as e:
    e.msg

func piece(text: string, styles: varargs[string]): Piece =
  Piece(text: text, styles: @styles)

suite "ui markup: reading":
  test "text with no markup is one piece in no style":
    check parseMarkup("plain text") == @[@[piece("plain text")]]
    check parseMarkup("") == @[newSeq[Piece]()]

  test "a style covers its text, and the space after its name is not text":
    check parseMarkup("[good imported] 3 files") ==
      @[@[piece("imported", "good"), piece(" 3 files")]]
    check parseMarkup("[good  two]") == @[@[piece(" two", "good")]]

  test "styles nest, the outermost first":
    check parseMarkup("[em a [hide b] c]") ==
      @[@[piece("a ", "em"), piece("b", "em", "hide"), piece(" c", "em")]]

  test "a style runs over a newline, and each line has its own pieces":
    check parseMarkup("[hide one\ntwo] three") ==
      @[@[piece("one", "hide")], @[piece("two", "hide"), piece(" three")]]

  test "brackets and backslashes are escaped with a backslash":
    check parseMarkup("\\[x\\] a\\\\b") == @[@[piece("[x] a\\b")]]
    check parseMarkup("[em \\]]") == @[@[piece("]", "em")]]

  test "markup that cannot be read is refused, with where":
    check problem("a ] b") == "at 3: this ] closes no style (write \\] for a bracket)"
    check problem("a [em b") == "at 3: [em is not closed"
    check problem("[ x]").startsWith("at 1: a [ starts a style")
    check problem("[Em x]").startsWith("at 1: a [ starts a style")
    check problem("[em]") ==
      "at 4: the name of a style is followed by a space: [em text]"
    check problem("a \\n").startsWith("at 3: a backslash goes only before")

suite "ui markup: painting and rendering":
  let t = parseTheme("default fg=white\nem weight=bold\nred fg=red\nline underline=yes")

  test "every piece has the base look with its styles over it, in order":
    let p = paint(t, parseMarkup("a [red b [em c]] [line [red d]]")[0])
    check p[0].look == baseLook(t)
    check p[1].look.fg == Colour(kind: ckBasic, index: 1)
    check p[2].look.fg == Colour(kind: ckBasic, index: 1)
    check p[2].look.weight == wtBold
    check p[4].look.underline
    check p[4].look.fg == Colour(kind: ckBasic, index: 1)

  test "default inside a style goes back to the base look":
    let p = paint(t, parseMarkup("[em [line [default x]]]")[0])
    check p[0].look == baseLook(t)

  test "a style the theme does not have changes nothing":
    check paint(t, parseMarkup("[red a [blue b]]")[0])[1].look ==
      paint(t, parseMarkup("[red a]")[0])[0].look

  test "each piece starts its look and ends with a reset; without colour, only the text":
    let plain = parseTheme("red fg=red")
    check styled(plain, "a [red b]\n[red c] d", true) ==
      @["a \e[31mb\e[0m", "\e[31mc\e[0m d"]
    check styled(plain, "a [red b]\n[red c] d", false) == @["a b", "c d"]
