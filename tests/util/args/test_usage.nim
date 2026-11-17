import std/[sequtils, strutils, unittest]
import nimchoo/packages/util/args/[args, usage]

func doc(names: openArray[string], metavar, help: string): OptDoc =
  OptDoc(names: @names, metavar: metavar, help: help)

suite "usage: wrapping":
  test "lines are broken at spaces, not beyond the width":
    check wrap("one two three four", 9) == @["one two", "three", "four"]
    check wrap("a b", 80) == @["a b"]
  test "a word longer than the width has a line of its own":
    check wrap("a verylongword b", 5) == @["a", "verylongword", "b"]
  test "a newline starts a new line":
    check wrap("one\ntwo three", 80) == @["one", "two three"]
  test "two spaces after a full stop stay, unless the line ends there":
    check wrap("end.  Next one", 80) == @["end.  Next one"]
    check wrap("end.  Next one", 5) == @["end.", "Next", "one"]

suite "usage: the option list":
  test "a value that may be left out is in brackets":
    check optionLines(
      @[OptDoc(names: @["--shell"], metavar: "SHELL", help: "which", arity: aOptional)],
      80,
    ) == @["  --shell [SHELL]  which"]
  test "names, the value, and the help in a column":
    check optionLines(
      @[
        doc(["--all"], "", "every activity"),
        doc(["-n", "--newest"], "N", "only the N newest"),
      ],
      80,
    ) == @["  --all           every activity", "  -n, --newest N  only the N newest"]
  test "long help is wrapped under its own column":
    let lines = optionLines(
      @[doc(["--sport"], "A B", "one two three four five six seven eight")], 36
    )
    check lines ==
      @["  --sport A B  one two three four five six", "               seven eight"]
  test "a label that is too long leaves the help for the next line":
    let lines = optionLines(
      @[
        doc(["--a-very-long-option-name"], "SOMETHING", "text"),
        doc(["-x"], "", "short"),
      ],
      80,
    )
    check lines ==
      @["  --a-very-long-option-name SOMETHING", "      text", "  -x  short"]
  test "an option with no help is still listed":
    check optionLines(@[doc(["--odd"], "", "")], 80) == @["  --odd"]
  test "the width of the help has a floor, so a narrow terminal does not make a line a word long":
    let lines = optionLines(
      @[doc(["--x"], "", "aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll")], 10
    )
    check lines.len < 12
    for l in lines:
      check l.len <= 40

suite "usage: from a spec":
  test "every option of a spec is in the usage, with its value and its help":
    type P = object
      yes: bool
      n: int

    let spec = Spec[P](
      opts: @[
        flag(P, ["-y", "--yes"], yes, "say yes"),
        whole(P, ["-n"], n, 1, 9, "a digit", "N", "a number"),
        flag(P, ["--deep"], yes, "goes with the one before", level = 1),
      ]
    )
    let shown = optionLines(spec.docs, 80).join("\n")
    check "-y, --yes" in shown and "-n N" in shown and "say yes" in shown
    check "\n    --deep" in shown # (indented under the one before it)
    check spec.docs[1].arity == aOne and spec.docs[0].arity == aFlag

suite "usage: prose":
  test "paragraphs are wrapped, a line break inside one is a space, a blank line separates them":
    check prose("one two\nthree four\n\nfive six", 9) ==
      "one two\nthree\nfour\n\nfive six"
  test "nothing is left over at the ends":
    check prose("\none two\n", 80) == "one two"

suite "wrap: documentation":
  test "paragraphs and lists keep their shape":
    check rst(
      "one two three\nfour\n\n* item one is long\n  and goes on\n* item two", 14
    ) == "one two three\nfour\n\n* item one is\n  long and\n  goes on\n* item two"

suite "usage: tables":
  test "the columns line up, the last is wrapped to the width and its lines start under it":
    let ls = tableLines(
      @["subject", "frame", "what it is"],
      @[
        @["activities", "routes*", "the route of each activity"],
        @[
          "activities", "heat",
          "how often each place was visited, in cells of about 100 m",
        ],
      ],
      60,
    )
    check ls[0] == "  subject     frame    what it is"
    check ls[1] == "  activities  routes*  the route of each activity"
    check ls[2].startsWith("  activities  heat     how often each place")
    check ls.len == 4 and ls[3].startsWith(" ".repeat(23)) and not ls[3][23].isSpaceAscii
    check ls.allIt(it.len <= 60)
  test "a narrow width still leaves the last column room":
    let ls =
      tableLines(@["a", "b"], @[@["x", "one two three four five six seven eight"]], 10)
    check ls.allIt(it.len <= 2 + 1 + 2 + 30)
