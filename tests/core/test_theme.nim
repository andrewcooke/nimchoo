import std/[options, strutils, tables, unittest]
import nimchoo/core/errors
import nimchoo/core/theme

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

  test "the styles keep the order of the file, each followed by its alt-X":
    let t = parseTheme("b\na\nc\n")
    var names: seq[string]
    for n in t.styles.keys:
      names.add n
    check names == @["b", "alt-b", "a", "alt-a", "c", "alt-c"]

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
    check problem("a reverse=on") == "line 1: reverse is yes or no, not 'on'"
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
      "a fg=red\nb fg=bright-red bg=blue\nc fg=#010203 bg=#040506\nd weight=dim italic=yes underline=yes reverse=yes"
    )
    check terminalCodes(terminalLook.over(t.styles["a"])) == "\e[31m"
    check terminalCodes(terminalLook.over(t.styles["b"])) == "\e[91;44m"
    check terminalCodes(terminalLook.over(t.styles["c"])) == "\e[38;2;1;2;3;48;2;4;5;6m"
    check terminalCodes(terminalLook.over(t.styles["d"])) == "\e[2;3;4;7m"

suite "ui theme: v(NAME, GAMMA)":
  func fgOf(t: Theme, name: string): Colour =
    t.styles[name].fg.get

  func rgb(r, g, b: uint8): Colour =
    Colour(kind: ckRgb, r: r, g: g, b: b)

  test "the value of a colour above, raised to gamma: more than 1 darker, less than 1 lighter":
    let t = parseTheme(
      "cmd fg=#a0a0c0\nalt-cmd fg=v(cmd, 1.2)\ngrey fg=#808080\ndark fg=v(grey, 2)\nlight fg=v(dark, 0.5)"
    )
    check t.fgOf("alt-cmd") == rgb(0x97, 0x97, 0xb5)
      # (V 0.753 → 0.711: the hue and saturation kept)
    check t.fgOf("dark") == rgb(0x40, 0x40, 0x40)
    check t.fgOf("light") == rgb(0x80, 0x80, 0x80)

  test "black and white, and anything of value 1, stay as they are":
    let t = parseTheme(
      "w fg=#ffffff\nr fg=#ff0000\nk fg=#000000\na fg=v(w, 3)\nb fg=v(r, 3)\nc fg=v(k, 0.2)"
    )
    check t.fgOf("a") == rgb(255, 255, 255) and t.fgOf("b") == rgb(255, 0, 0) and
      t.fgOf("c") == rgb(0, 0, 0)

  test "the colour is the one the style is drawn in: what it leaves out comes from default; bg from bg":
    let t = parseTheme(
      "default fg=#808080\nx weight=bold\ny fg=v(x, 2)\nz bg=#808080\nw bg=v(z, 2)"
    )
    check t.fgOf("y") == rgb(0x40, 0x40, 0x40)
    check t.styles["w"].bg.get == rgb(0x40, 0x40, 0x40)

  test "a space inside the brackets is part of the colour":
    check parseTheme("a fg=#808080\nb fg=v(a,2) weight=bold\nc fg=v( a , 2 )").fgOf("c") ==
      rgb(0x40, 0x40, 0x40)

  test "a name not above, a colour with no value, or a gamma that is not a positive number, is an error on its line":
    check problem("b fg=v(a, 2)\na fg=#808080").contains("no style a above this line")
    check problem("a fg=red\nb fg=v(a, 2)").contains("not a #rrggbb colour")
    check problem("a fg=#808080\nb fg=v(a, 0)").contains("more than 0")
    check problem("a fg=#808080\nb fg=v(a, x)").contains("is a number")
    check problem("a fg=#808080\nb fg=v(a)").contains("not v(NAME, GAMMA)")
    check problem("a fg=#808080\nb fg=v(a, 0)").contains("2") # (the line)

suite "ui theme: alt":
  test "each style comes with its alt-X, defined as X; an alt-X line changes what it gives, the rest stays X's":
    let t = parseTheme("cmd fg=#a0a0c0\npkg fg=#ffffff bg=#303040\nalt-pkg fg=#000000")
    check t.styles["alt-cmd"] == t.styles["cmd"]
    check t.styles["alt-pkg"].fg.get == Colour(kind: ckRgb, r: 0, g: 0, b: 0)
    check t.styles["alt-pkg"].bg.get == t.styles["pkg"].bg.get # (pkg's background)
    check "alt-nothing" notin t.styles

  test "the alt-X line may come before X":
    let t = parseTheme("alt-pkg fg=#000000\npkg fg=#ffffff bg=#303040")
    check t.styles["alt-pkg"].fg.get == Colour(kind: ckRgb, r: 0, g: 0, b: 0) and
      t.styles["alt-pkg"].bg.get == t.styles["pkg"].bg.get

  test "an alt-X can be used in v() below X, and is given only once":
    check parseTheme("cmd fg=#808080\nx fg=v(alt-cmd, 2)").styles["x"].fg.get ==
      Colour(kind: ckRgb, r: 0x40, g: 0x40, b: 0x40)
    check problem("cmd fg=#808080\nalt-cmd fg=red\nalt-cmd fg=blue").contains(
      "given twice"
    )
