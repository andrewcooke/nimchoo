import std/[sequtils, strutils, unicode, unittest]
import nimchoo/core/ruled

suite "ruled tables":
  test "lines between the columns, a rule under the headings, crossed where they meet":
    let ls = ruledLines(@["a", "bb", "c"], @[@["xxx", "y", "z"]], 80)
    check ls ==
      @["a   │ bb │ c", "────┼────┼──", "xxx │ y  │ z"]

  test "columns in right are aligned to the right":
    let ls = ruledLines(@["name", "n"], @[@["x", "7"], @["y", "12"]], 80, right = {})
    check ls[2] == "x    │ 7"
    let r = ruledLines(
      @["name", "n", "what"], @[@["x", "7", "a"], @["y", "12", "b"]], 80, right = {1}
    )
    check r[2] == "x    │  7 │ a" and r[3] == "y    │ 12 │ b"

  test "a newline in the last cell starts a paragraph, under the same column; an empty cell leaves a row":
    let ls = ruledLines(@["a", "b"], @[@["x", "one\ntwo"], @["y", ""]], 80)
    check ls[2] == "x │ one" and ls[3] == "  │ two" and ls[4] == "y │"

  test "the last column is wrapped to the width, never narrower than the minimum, and the rule is as wide as the table":
    let ls =
      ruledLines(@["a", "b"], @[@["x", "word ".repeat(30).strip]], 50, indent = 2)
    check ls.allIt(it.runeLen <= 50) and ls.len > 3
    check ls[1].runeLen == ls.mapIt(it.runeLen).max
    let narrow = ruledLines(@["a", "b"], @[@["x", "word ".repeat(30).strip]], 5)
    check narrow[2].runeLen >= minLastWidth
