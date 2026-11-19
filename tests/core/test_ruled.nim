import std/[os, sequtils, strutils, unicode, unittest]
import nimchoo/core/[line, ruled]

func ruledLines(
    header: seq[string],
    rows: seq[seq[string]],
    width: int,
    indent = 0,
    right: set[0 .. 31] = {},
    together: set[0 .. 31] = {},
): seq[string] =
  ## The table of plain cells, as text.
  ruled(header, rows.mapIt(it.mapIt(plain(it))), width, indent, right, together).mapIt(
    it.text
  )

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

  test "columns together have two spaces between them, and the rule runs straight under them":
    let ls = ruledLines(
      @["name", "L", "U", "what"],
      @[@["x", "1", "12", "a"]],
      80,
      right = {1, 2},
      together = {1},
    )
    check ls[0] == "name │ L   U │ what"
    check ls[1] == "─────┼───────┼─────"
    check ls[2] == "x    │ 1  12 │ a"

suite "ruled tables: cells in styles":
  test "a styled cell in a table: the text is that of the plain table, the style kept":
    let lines =
      ruled(@["a", "b"], @[@[plain("x"), @[span("go "), span("ff", "cmd")]]], 80)
    check lines.mapIt(it.text) ==
      @["a │ b", "──┼──────", "x │ go ff"]
    check span("ff", "cmd") in lines[2]

suite "ruled tables: the only tables":
  test "no other code lines up columns (with align or alignLeft): every table is ruled":
    # (the exceptions: the two that make the tables, the log file's own format, a developer's timings, and the diagram of
    # the layers; and padding a number with zeros, `align($m, 2, '0')`, which is not a column)
    const allowed = [
      "core/ruled.nim", "util/args/usage.nim", "core/logfile.nim",
      "profiling/profiling.nim", "core/inventory.nim",
    ]
    var found: seq[string]
    let top = currentSourcePath().parentDir.parentDir.parentDir / "src"
    for path in walkDirRec(top):
      if not path.endsWith(".nim") or allowed.anyIt(path.endsWith(it)):
        continue
      for i, l in readFile(path).splitLines.toSeq:
        if ("alignLeft(" in l or "align(" in l) and ", '0')" notin l:
          found.add path.relativePath(top) & ":" & $(i + 1)
    check found.len == 0
    if found.len > 0:
      echo "columns lined up by hand (use core/ruled.nim): ", found.join(", ")
