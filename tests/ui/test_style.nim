import std/unittest
import nimchoo/packages/ui/style

suite "ui style: measuring and cutting":
  test "width counts characters, over all spans":
    check width(@[span("abc"), span("de")]) == 5
    check width(@[span("héllo")]) == 5
    check width(@[]) == 0
    check text(@[span("ab"), span("cd", red)]) == "abcd"

  test "a line that fits is not changed":
    let line = @[span("abc", red), span("def")]
    check line.truncated(6) == line
    check line.truncated(10) == line

  test "a line that is too long is cut, ending in an ellipsis":
    let line = @[span("abc", red), span("def", green)]
    check text(line.truncated(4)) == "abc…"
    check text(line.truncated(5)) == "abcd…"
    check width(line.truncated(4)) == 4
    check width(line.truncated(5)) == 5

  test "the cut keeps the look of what it cuts":
    let cut = @[span("abc", red), span("def", green)].truncated(5)
    check cut[0].look.colour == red
    check cut[1].look.colour == green
    check cut[^1].text == "…"
    check cut[^1].look.colour == green

  test "cuts fall between characters, not inside them":
    check text(@[span("héllo wörld")].truncated(6)) == "héllo…"

  test "nothing fits in no room, a column holds the ellipsis":
    check @[span("abc")].truncated(0).len == 0
    check @[span("abc")].truncated(-3).len == 0
    check text(@[span("abc")].truncated(1)) == "…"

suite "ui style: rendering":
  test "without colour it is just the text":
    check render(@[span("a", red, bold = true), span("b")], false) == "ab"

  test "with colour, styled spans get codes and a reset":
    check render(@[span("go", green)], true) == "\e[32mgo\e[0m"
    check render(@[span("no", red, bold = true)], true) == "\e[31m\e[1mno\e[0m"
    check render(@[span("sh", grey)], true) == "\e[38;5;240msh\e[0m"

  test "unstyled spans get no codes":
    check render(@[span("a"), span("b", yellow), span("c")], true) == "a\e[33mb\e[0mc"
