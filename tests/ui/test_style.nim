import std/[tables, unittest]
import nimchoo/core/theme
import nimchoo/packages/ui/style
import ../support/styles

suite "ui style: measuring and cutting":
  test "width counts characters, over all spans":
    check width(@[span("abc"), span("de")]) == 5
    check width(@[span("héllo")]) == 5
    check width(@[]) == 0
    check text(@[span("ab"), span("cd", "bad")]) == "abcd"

  test "a line that fits is not changed":
    let line = @[span("abc", "bad"), span("def")]
    check line.truncated(6) == line
    check line.truncated(10) == line

  test "a line that is too long is cut, ending in an ellipsis":
    let line = @[span("abc", "bad"), span("def", "good")]
    check text(line.truncated(4)) == "abc…"
    check text(line.truncated(5)) == "abcd…"
    check width(line.truncated(4)) == 4
    check width(line.truncated(5)) == 5

  test "the cut keeps the look of what it cuts":
    let cut = @[span("abc", "bad"), span("def", "good")].truncated(5)
    check styleOf(cut[0]) == "bad"
    check styleOf(cut[1]) == "good"
    check cut[^1].text == "…"
    check styleOf(cut[^1]) == "good"

  test "cuts fall between characters, not inside them":
    check text(@[span("héllo wörld")].truncated(6)) == "héllo…"

  test "nothing fits in no room, a column holds the ellipsis":
    check @[span("abc")].truncated(0).len == 0
    check @[span("abc")].truncated(-3).len == 0
    check text(@[span("abc")].truncated(1)) == "…"

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

  test "the built-in themes are themes, with the same styles":
    for t in builtInThemes:
      var names: seq[string]
      for n in parseTheme(t.text).styles.keys:
        names.add n
      check names.len == styleNames.len
      for n in styleNames:
        check n in names

suite "ui style: merging":
  test "spans of the same style side by side become one, with the spaces between them":
    let l = merged(
      @[span("a", "select"), span("  "), span("b", "select"), span("  "), span("c")]
    )
    check l.len == 2
    check l[0].text == "a  b" and styleOf(l[0]) == "select"
    check l[1].text == "  c" and l[1].styles.len == 0

  test "spaces between different styles, or text that is not space, stay as they are":
    check merged(@[span("a", "good"), span(" "), span("b", "bad")]).len == 3
    check merged(@[span("a", "good"), span("x"), span("b", "good")]).len == 3
    check merged(@[span("a"), span("b")]).len == 1

suite "ui style: marks where there is no colour":
  test "a selected line is in brackets; the others have a space where the bracket would be":
    check bracketed(@[span("a"), span("b", "select")], true).text == "[ab]"
    check bracketed(@[span("ab")], false).text == " ab"

suite "ui style: rendering looks that run on":
  test "spans side by side that look the same share their codes":
    let p = Paint(theme: parseTheme("select fg=blue"), colour: true)
    check render(@[span("a", "select"), span(" ", "select"), span("b", "select")], p) ==
      "\e[34ma b\e[0m"
    check render(@[span("a", "select"), span(" "), span("b", "select")], p) ==
      "\e[34ma\e[0m \e[34mb\e[0m"
