import std/[os, sequtils, strutils, unicode, unittest]
import nimchoo/core/[line, ruled]

func ruledLines(
    header: seq[string],
    rows: seq[seq[string]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
): seq[string] =
  ## The table of plain cells, as text.
  ruled(header, rows.mapIt(it.mapIt(plain(it))), width, indent, right).mapIt(it.text)

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
    check ls[2] == "x │ one" and ls[3] == "  │ two" and ls[4] == "y"
      # (an empty last cell: no line before it)

  test "the last column is wrapped to the width, never narrower than the minimum, and the rule is as wide as the table":
    let ls =
      ruledLines(@["a", "b"], @[@["x", "word ".repeat(30).strip]], 50, indent = 2)
    check ls.allIt(it.runeLen <= 50) and ls.len > 3
    check ls[1].runeLen == ls.mapIt(it.runeLen).max
    let narrow = ruledLines(@["a", "b"], @[@["x", "word ".repeat(30).strip]], 5)
    check narrow[2].runeLen >= minLastWidth

suite "ruled tables: cells in styles":
  test "a styled cell in a table: the text is that of the plain table, the style kept":
    let lines =
      ruled(@["a", "b"], @[@[plain("x"), @[span("go "), span("ff", "code")]]], 80)
    check lines.mapIt(it.text) ==
      @["a │ b", "──┼──────", "x │ go ff"]
    check span("ff", "code") in lines[2]

suite "ruled tables: narrow columns":
  test "with narrow, the other columns wrap too, and a row is as tall as its tallest cell":
    let ls = ruled(@["", ""], @[@["defines extension points", "x"]], 80, narrow = 10)
      .mapIt(it.text)
    check ls == @["defines   │ x", "extension │", "points    │"]

suite "ruled tables: the only tables":
  test "no other code lines up columns (with align, alignLeft or a run of spaces): every table is ruled":
    # (the exceptions: the two that make the tables, the log file's own format, a developer's timings, the diagram of
    # the layers, and the calendar's grid (a margin as wide as its labels, not a table); and padding a number with zeros, `align($m, 2, '0')`, which is not a column)
    const allowed = [
      "core/ruled.nim", "util/args/usage.nim", "core/logfile.nim",
      "profiling/profiling.nim", "core/inventory.nim", "calendar/calendar.nim",
    ]
    var found: seq[string]
    let top = currentSourcePath().parentDir.parentDir.parentDir / "src"
    for path in walkDirRec(top):
      if not path.endsWith(".nim") or allowed.anyIt(path.endsWith(it)):
        continue
      for i, l in readFile(path).splitLines.toSeq:
        if ("alignLeft(" in l or "align(" in l or "\" \".repeat(" in l) and
            ", '0')" notin l:
          found.add path.relativePath(top) & ":" & $(i + 1)
    check found.len == 0
    if found.len > 0:
      echo "columns lined up by hand (use core/ruled.nim): ", found.join(", ")

suite "ruled tables: alternate":
  test "with alternate, every other row is in the alt version of its styles, all through":
    let ls = ruled(
      @["", ""],
      @[@[plain("a"), @[span("one", "code")]], @[plain("b"), @[span("two", "code")]]],
      80,
      alternate = true,
    )
    check ls[0] == @[span("a │ "), span("one", "code")]
    check ls[1] == @[span("b │ ", "alt-default"), span("two", "alt-code")]
