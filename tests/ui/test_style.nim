import std/[tables, unittest]
import nimchoo/core/theme
import nimchoo/packages/ui/[markup, style]

suite "ui style: rendering":
  let paint = Paint(
    theme: parseTheme("good fg=green\nbad fg=red\nem weight=bold\nhide fg=#585858"),
    colour: true,
  )

  test "without colour it is just the text":
    var plainPaint = paint
    plainPaint.colour = false
    check render(@[span("a", "bad", "em"), span("b")], plainPaint) == "ab"

  test "with colour, styled spans get their codes and a reset":
    check render(@[span("go", "good")], paint) == "\e[32mgo\e[0m"
    check render(@[span("no", "bad", "em")], paint) == "\e[1;31mno\e[0m"
    check render(@[span("sh", "hide")], paint) == "\e[38;2;88;88;88msh\e[0m"

  test "plain spans get no codes, unless default gives them a look":
    check render(@[span("a"), span("b", "warn"), span("c")], paint) == "abc"
      # (this theme has no warn)
    let dark = Paint(theme: parseTheme("default fg=white"), colour: true)
    check render(@[span("a")], dark) == "\e[37ma\e[0m"

  test "a style the theme lacks changes nothing, and default goes back to the base":
    let t = parseTheme("default fg=white\nem weight=bold")
    check lookOf(t, @[anyStyle("nosuch")]) == baseLook(t)
    check lookOf(t, @[styleName"em", styleName"default"]) == baseLook(t)
    check lookOf(t, @[styleName"em"]).weight == wtBold

  test "the built-in themes are themes, each with every style the program uses":
    for t in builtInThemes:
      var names: seq[string]
      for n in parseTheme(t.text).styles.keys:
        names.add n
      for n in programStyles: # (each X with its alt-X)
        check n in names

suite "ui style: rendering looks that run on":
  test "spans side by side that look the same share their codes":
    let p = Paint(theme: parseTheme("select fg=blue"), colour: true)
    check render(@[span("a", "select"), span(" ", "select"), span("b", "select")], p) ==
      "\e[34ma b\e[0m"
    check render(@[span("a", "select"), span(" "), span("b", "select")], p) ==
      "\e[34ma\e[0m \e[34mb\e[0m"

suite "ui style: the lines of a table or a tree":
  test "they are drawn in the line style over the span's own; without colour, as they are":
    let p = Paint(theme: parseTheme("hide fg=bright-black\nbad fg=red"), colour: true)
    check render(@[span("├── x")], p) == "\e[90m├──\e[0m x"
    check render(@[span("│a", "bad")], p) == "\e[90m│\e[0m\e[31ma\e[0m"
    var plain = p
    plain.colour = false
    check render(@[span("├── x")], plain) == "├── x"

  test "a code span is in the typed style, over the span's own; a backtick in a value is drawn as it is":
    let p = Paint(theme: parseTheme("code fg=blue\nem weight=bold"), colour: true)
    check render(@[span("run "), span("nch db", "code")], p) == "run \e[34mnch db\e[0m"
    check render(@[span("x", "em", "code")], p) == "\e[1;34mx\e[0m"
    check render(@[span("a name with `ticks`")], p) == "a name with `ticks`"
    let name = "a`b"
    check render(~"the activity `{name}`", p) == "the activity \e[34ma`b\e[0m"

suite "ui style: messages are one colour":
  test "in a warning or a failure what is between backticks is drawn as it is, in the message's style":
    let p =
      Paint(theme: parseTheme("code fg=blue\nwarn fg=red\nbad fg=red"), colour: true)
    check render(@[span("use `nch db`", "warn")], p) == "\e[31muse `nch db`\e[0m"
    check render(@[span("use `nch db`", "alt-bad")], p) == "\e[31muse `nch db`\e[0m"
    check render(@[span("use "), span("nch db", "code")], p) == "use \e[34mnch db\e[0m"
      # (elsewhere, code)
