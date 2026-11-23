import std/[sequtils, unittest]
import nimchoo/core/line
import ../support/styles

suite "lines: measuring and cutting":
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

suite "lines: merging":
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

  test "the selection is one band: the lines of a table between its cells join it, in pieces too; no other style does":
    let l = merged(
      @[
        span("a", "select"),
        span("  "),
        span(" │ "),
        span("b", "select"),
        span(" │ c"),
      ]
    )
    check l.len == 2 and l[0].text == "a   │ b" and styleOf(l[0]) == "select"
    check merged(@[span("a", "code"), span(" │ "), span("b", "code")]).len == 3

suite "lines: marks where there is no colour":
  test "a selected line is in brackets; the others have a space where the bracket would be":
    check bracketed(@[span("a"), span("b", "select")], true).text == "[ab]"
    check bracketed(@[span("ab")], false).text == " ab"

suite "lines: wrapping":
  test "a cell is wrapped by words as text is, and each word keeps its style":
    let line = @[span("one two "), span("three", "code"), span(" four")]
    let ls = line.wrapped(9)
    check ls.mapIt(it.text) == @["one two", "three", "four"]
    check ls[1] == @[span("three", "code")]
    check plain("a.  b").wrapped(80).mapIt(it.text) ==
      @["a.  b"] # (two spaces after a full stop stay)
    check plain("a\nb").wrapped(80).len == 2 # (a newline starts a line)
    check plain("end.  Next one").wrapped(4).mapIt(it.text) ==
      @["end.", "Next", "one"] # (no line starts with the second space of a full stop)

  test "a phrase in one style keeps the style over its spaces, across lines too":
    let ls = @[span("x "), span("in a style", "em"), span(" y")].wrapped(80)
    check ls == @[@[span("x "), span("in a style", "em"), span(" y")]]

suite "lines: stripping":
  test "the spaces at the end go, a span of nothing but spaces too (as unicode.strip leaves it)":
    check @[span("a"), span("b ", "code"), span("  ")].stripped ==
      @[span("a"), span("b", "code")]
    check plain("   ").stripped.len == 0

  test "a piece kept whole is not broken where it has spaces":
    let ls = @[span("aaaa " & unbroken("route (importer)") & " b")].wrapped(10)
    check ls.mapIt(it.text) == @["aaaa", unbroken("route (importer)"), "b"]

suite "lines: shades pass through":
  test "a shade's name is a style like any other: cutting, merging, wrapping, alternating and bands keep it":
    let a = shaded("fitness", 0.37)
    let b = shaded("fitness", 0.38)
    check $a == "fitness,0.37" and $shaded("x", 1.5) == "x,1.00" and
      $shaded("x", -1) == "x,0.00"
    let l = @[span("ab", a), span("cd", b)]
    check truncated(l, 3)[0].styles == @[a]
    check merged(l).len == 2 # (two shades are two looks)
    check wrapped(l, 80)[0].mapIt(it.styles) == @[@[a], @[b]]
    check alternated(l)[0].styles.mapIt($it) == @["alt-fitness,0.37"]
    check within(l, styleName"select")[0].styles == @[styleName"select", a]
