import std/[options, strutils, tables, unittest]
import nimchoo/core/errors
import nimchoo/packages/ui/theme

proc problem(text: string): string =
  try:
    discard parseTheme(text)
    "no error"
  except ThemeError as e:
    e.msg

suite "ui theme: reading a theme file":
  test "a style gives only the attributes it names":
    let t =
      parseTheme("# a comment\n\nlink  underline=yes\nem fg=#ff8000 weight=bold\n")
    check t.styles["link"].underline == some(true)
    check t.styles["link"].fg.isNone
    check t.styles["link"].weight.isNone
    check t.styles["em"].fg == some(Colour(kind: ckRgb, r: 255, g: 128, b: 0))
    check t.styles["em"].weight == some(wtBold)

  test "the styles keep the order of the file":
    let t = parseTheme("b\na\nc\n")
    var names: seq[string]
    for n in t.styles.keys:
      names.add n
    check names == @["b", "a", "c"]

  test "colours are terminal, one of the sixteen, or #rrggbb":
    let t = parseTheme("x fg=terminal bg=bright-blue\ny fg=red bg=#000000")
    check t.styles["x"].fg == some(Colour(kind: ckTerminal))
    check t.styles["x"].bg == some(Colour(kind: ckBasic, index: 12))
    check t.styles["y"].fg == some(Colour(kind: ckBasic, index: 1))
    check t.styles["y"].bg == some(Colour(kind: ckRgb, r: 0, g: 0, b: 0))

  test "what cannot be used is refused, with its line":
    check problem("a\na fg=red") == "line 2: the style a is given twice"
    check problem("a fg=red fg=blue") == "line 1: fg is given twice"
    check problem("a size=2").startsWith("line 1: 'size' is not an attribute")
    check problem("a fg=#12345").startsWith("line 1: '#12345' is not a colour")
    check problem("a fg=orange").startsWith("line 1: 'orange' is not a colour")
    check problem("a weight=heavy") ==
      "line 1: weight is bold, normal or dim, not 'heavy'"
    check problem("a underline=true") == "line 1: underline is yes or no, not 'true'"
    check problem("a fg").startsWith("line 1: 'fg' is not key=value")
    check problem("Bad fg=red").startsWith("line 1: 'Bad' is not a name of a style")

suite "ui theme: looks":
  test "a style over a look replaces what it gives and keeps the rest":
    let t = parseTheme("bold weight=bold\nred fg=red\nplain-weight weight=normal")
    let l = terminalLook.over(t.styles["bold"]).over(t.styles["red"])
    check l.weight == wtBold
    check l.fg == Colour(kind: ckBasic, index: 1)
    check l.over(t.styles["plain-weight"]).weight == wtNormal
    check l.over(t.styles["plain-weight"]).fg == Colour(kind: ckBasic, index: 1)

  test "the base look is the terminal's own, with what default changes":
    check baseLook(parseTheme("")) == terminalLook
    check baseLook(parseTheme("default bg=black")).bg == Colour(kind: ckBasic, index: 0)
    check baseLook(parseTheme("default bg=black")).fg == Colour(kind: ckTerminal)

  test "the terminal codes of a look":
    check terminalCodes(terminalLook) == ""
    let t = parseTheme(
      "a fg=red\nb fg=bright-red bg=blue\nc fg=#010203 bg=#040506\nd weight=dim italic=yes underline=yes"
    )
    check terminalCodes(terminalLook.over(t.styles["a"])) == "\e[31m"
    check terminalCodes(terminalLook.over(t.styles["b"])) == "\e[91;44m"
    check terminalCodes(terminalLook.over(t.styles["c"])) == "\e[38;2;1;2;3;48;2;4;5;6m"
    check terminalCodes(terminalLook.over(t.styles["d"])) == "\e[2;3;4m"
