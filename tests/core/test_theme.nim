import std/[options, strutils, tables, unittest]
import nimchoo/core/errors
import nimchoo/core/[line, theme]
import nimchoo/packages/ui/style

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

suite "ui theme: NAME.fg, NAME.bg and v(COLOUR, GAMMA)":
  func fgOf(t: Theme, name: string): Colour =
    t.styles[name].fg.get

  func rgb(r, g, b: uint8): Colour =
    Colour(kind: ckRgb, r: r, g: g, b: b)

  test "the value of a colour above, raised to gamma: more than 1 darker, less than 1 lighter":
    let t = parseTheme(
      "cmd fg=#a0a0c0\nalt-cmd fg=v(cmd.fg, 1.2)\ngrey fg=#808080\ndark fg=v(grey.fg, 2)\nlight fg=v(dark.fg, 0.5)"
    )
    check t.fgOf("alt-cmd") == rgb(0x97, 0x97, 0xb5)
      # (V 0.753 → 0.711: the hue and saturation kept)
    check t.fgOf("dark") == rgb(0x40, 0x40, 0x40)
    check t.fgOf("light") == rgb(0x80, 0x80, 0x80)

  test "black and white, and anything of value 1, stay as they are":
    let t = parseTheme(
      "w fg=#ffffff\nr fg=#ff0000\nk fg=#000000\na fg=v(w.fg, 3)\nb fg=v(r.fg, 3)\nc fg=v(k.fg, 0.2)"
    )
    check t.fgOf("a") == rgb(255, 255, 255) and t.fgOf("b") == rgb(255, 0, 0) and
      t.fgOf("c") == rgb(0, 0, 0)

  test "the colour is the one the style is drawn in: what it leaves out comes from default; bg from bg":
    let t = parseTheme(
      "default fg=#808080\nx weight=bold\ny fg=v(x.fg, 2)\nz bg=#808080\nw bg=v(z.bg, 2)"
    )
    check t.fgOf("y") == rgb(0x40, 0x40, 0x40)
    check t.styles["w"].bg.get == rgb(0x40, 0x40, 0x40)

  test "a space inside the brackets is part of the colour":
    check parseTheme("a fg=#808080\nb fg=v(a.fg,2) weight=bold\nc fg=v( a.fg , 2 )")
      .fgOf("c") == rgb(0x40, 0x40, 0x40)

  test "a name not above, a colour with no value, or a gamma that is not a positive number, is an error on its line":
    check problem("b fg=v(a.fg, 2)\na fg=#808080").contains(
      "no style a above this line"
    )
    check problem("a fg=red\nb fg=v(a.fg, 2)").contains("not a #rrggbb colour")
    check problem("a fg=#808080\nb fg=v(a.fg, 0)").contains("more than 0")
    check problem("a fg=#808080\nb fg=v(a.fg, x)").contains("is a number")
    check problem("a fg=#808080\nb fg=v(a)").contains("not v(COLOUR, GAMMA)")
    check problem("a fg=#808080\nb fg=v(a.fg, 0)").contains("2") # (the line)

  test "NAME.fg and NAME.bg are a style's colours as drawn, either one in fg= or bg=":
    let t = parseTheme(
      "default fg=#808080\na bg=#102030\nb fg=a.bg bg=a.fg\nc fg=red\nd bg=c.fg\ne fg=default.fg"
    )
    check t.fgOf("b") == rgb(0x10, 0x20, 0x30)
    check t.styles["b"].bg.get == rgb(0x80, 0x80, 0x80) # (a's from default)
    check t.styles["d"].bg.get == Colour(kind: ckBasic, index: 1)
    check t.fgOf("e") == rgb(0x80, 0x80, 0x80)

  test "v() takes a colour: #rrggbb, NAME.fg or NAME.bg, or another v()":
    let t = parseTheme(
      "a fg=#808080 bg=#ffffff\nb fg=v(#808080, 2)\nc fg=v(a.bg, 1)\nd bg=v(a.fg, 2)\ne fg=v(v(a.fg, 2), 0.5)"
    )
    check t.fgOf("b") == rgb(0x40, 0x40, 0x40)
    check t.fgOf("c") == rgb(255, 255, 255)
    check t.styles["d"].bg.get == rgb(0x40, 0x40, 0x40)
    check t.fgOf("e") == rgb(0x80, 0x80, 0x80)

  test "a style's colour is NAME.fg or NAME.bg: a bare name is an error, and so is any other part":
    check problem("default fg=#808080\nhide fg=v(default, 2.5)").contains(
      "'default' is a style: its colour is default.fg or default.bg"
    )
    check problem("a fg=#808080\nb fg=a").contains("a.fg or a.bg")
    check problem("a fg=#808080\nb fg=a.weight").contains("NAME.fg or NAME.bg")
    check problem("b fg=a.fg\na fg=#808080").contains("no style a above this line")
    check problem("b fg=v(red, 2)").contains("red is not a #rrggbb colour")
    check problem("b fg=v(#80808, 2)").contains("is not a colour")

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
    check parseTheme("cmd fg=#808080\nx fg=v(alt-cmd.fg, 2)").styles["x"].fg.get ==
      Colour(kind: ckRgb, r: 0x40, g: 0x40, b: 0x40)
    check problem("cmd fg=#808080\nalt-cmd fg=red\nalt-cmd fg=blue").contains(
      "given twice"
    )

suite "ui theme: shades":
  let t = parseTheme(
    "default fg=#a0a0a0\n" & "default-lo bg=#000000\n" & "default-hi bg=#ffffff\n" &
      "form-lo bg=#ff0000 weight=bold\n" & "form-hi bg=#0000ff weight=bold\n"
  )
  test "a shade is drawn between its ends, else default's; its other attributes are its low end's":
    let grey = lookOf(t, @[anyStyle("fitness,0.50")])
    check grey.bg == Colour(kind: ckRgb, r: 128, g: 128, b: 128) and
      grey.fg == Colour(kind: ckRgb, r: 160, g: 160, b: 160)
    check lookOf(t, @[anyStyle("fitness,0.00")]).bg ==
      Colour(kind: ckRgb, r: 0, g: 0, b: 0)
    let form = lookOf(t, @[anyStyle("form,1.00")])
    check form.bg == Colour(kind: ckRgb, r: 0, g: 0, b: 255) and form.weight == wtBold
    check lookOf(t, @[anyStyle("alt-form,0.00")]).bg ==
      Colour(kind: ckRgb, r: 255, g: 0, b: 0)
  test "what is not a shade is an ordinary name (and one the theme lacks changes nothing)":
    check shadeOf("fitness,0.5") == some(("fitness", 0.5))
    check shadeOf("fitness").isNone and shadeOf("fitness,2").isNone and
      shadeOf(",0.5").isNone
    check lookOf(t, @[anyStyle("fitness,x")]).bg == baseLook(t).bg
  test "the ends go together, in #rrggbb, each colour in both or neither":
    check problem("a-lo bg=#000000\n").contains("has no a-hi")
    check problem("a-hi bg=#000000\n").contains("has no a-lo")
    check problem("a-lo bg=red\na-hi bg=blue\n").contains("#rrggbb")
    check problem("a-lo bg=#000000\na-hi fg=#000000\n").contains(
      "given in one and not the other"
    )
  test "the built-in themes have default-lo and default-hi":
    for (name, text) in builtInThemes:
      let th = parseTheme(text)
      check "default-lo" in th.styles and "default-hi" in th.styles
