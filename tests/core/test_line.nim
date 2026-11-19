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

suite "lines: marks where there is no colour":
  test "a selected line is in brackets; the others have a space where the bracket would be":
    check bracketed(@[span("a"), span("b", "select")], true).text == "[ab]"
    check bracketed(@[span("ab")], false).text == " ab"

suite "lines: wrapping":
  test "a cell is wrapped by words as text is, and each word keeps its style":
    let line = @[span("one two "), span("three", "cmd"), span(" four")]
    let ls = line.wrapped(9)
    check ls.mapIt(it.text) == @["one two", "three", "four"]
    check ls[1] == @[span("three", "cmd")]
    check plain("a.  b").wrapped(80).mapIt(it.text) ==
      @["a.  b"] # (two spaces after a full stop stay)
    check plain("a\nb").wrapped(80).len == 2 # (a newline starts a line)

  test "a phrase in one style keeps the style over its spaces, across lines too":
    let ls = @[span("x "), span("in a style", "em"), span(" y")].wrapped(80)
    check ls == @[@[span("x "), span("in a style", "em"), span(" y")]]
