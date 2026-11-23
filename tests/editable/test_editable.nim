import std/[options, sequtils, strutils, unittest]
import nimchoo/core/line
import nimchoo/packages/util/args/args
import nimchoo/packages/editable/editable

type Thing = object ## a toy type: not a model
  name: string
  size: float
  labels: seq[string]

func readSize(name, value: string, x: var float): Problem =
  if not parseFloatIn(value, 0, 100, x):
    return valueIs(name, "a size from 0 to 100", value)
  fine

func showSize(x: float): string =
  $x

func readLabels(name: string, values: seq[string], x: var seq[string]): Problem =
  x = values
  fine

func showLabels(x: seq[string]): Line =
  plain(x.join(" "))

func nameOf(t: Thing): string =
  t.name

func renamed(t: var Thing, name: string) =
  t.name = name

func noSpace(text: string): Option[string] =
  if ' ' in text:
    some("no spaces")
  else:
    none(string)

func small(t: Thing): Option[string] =
  if t.size > 50:
    some("too big")
  else:
    none(string)

func kind(): Kind[Thing] =
  Kind[Thing](
    one: "thing",
    many: "things",
    nameOf: nameOf,
    rename: renamed,
    nameProblem: noSpace,
    patternProblem: noSpace,
    check: small,
    attrs: @[
      valueAttr(
        Thing, "--size", size, "N", plain("its size"), "size", readSize, showSize
      ),
      listAttr(
        Thing,
        "--labels",
        labels,
        "L...",
        plain("its labels"),
        "labels",
        readLabels,
        showLabels,
      ),
    ],
  )

proc finish(raw: Raw[Thing]): Parsed[Action[Thing]] {.nimcall, raises: [].} =
  actionOf(raw)

proc parse(args: varargs[string]): Parsed[Action[Thing]] =
  parseCommand(
    @args,
    Spec[Raw[Thing]](opts: options(kind()) & @[helpFlag(Raw[Thing])]),
    Raw[Thing](kind: kind()),
    finish,
  )

suite "editable: a type declared once":
  test "the options: the names, the actions, then the attributes":
    let names = options(kind()).mapIt(it.names[0])
    check names ==
      @[
        "--names", "--add", "--base", "--edit", "--rename", "--delete", "--size",
        "--labels",
      ]
  test "list, add, edit and delete":
    check parse().params.kind == akList
    check parse("--names", "a*", "b").params.names == @["a*", "b"]
    check parse("--names", "a*", "--delete").params.kind == akDelete
    let a = parse("--add", "x", "--base", "y", "--size", "3").params
    check a.kind == akAdd and a.name == "x" and a.base == some("y") and
      a.given == @["--size"]
  test "what is given is copied, and nothing else; a list may be emptied":
    let base = Thing(name: "y", size: 9, labels: @["p"])
    check made(kind(), parse("--add", "x", "--labels", "q", "r").params, base) ==
      Thing(name: "x", size: 9, labels: @["q", "r"])
    check edited(kind(), parse("--edit", "y", "--labels").params, base) ==
      Thing(name: "y", size: 9, labels: @[])
    check edited(kind(), parse("--edit", "y", "--rename", "z").params, base).name == "z"
  test "the rules, in the type's words":
    check parse("--size", "3").problem.contains("a value for a thing made with")
    check parse("--add", "a b").problem.contains("no spaces")
    check parse("--names", "a b").problem.contains("no spaces")
    check parse("--add", "x", "--delete").problem.contains("one at a time")
    check parse("--edit", "x").problem.contains("none were given")
    check parse("--add", "x", "--size", "200").problem.contains("a size from 0 to 100")
  test "the table: the name and each attribute; the selected in brackets where there is no colour":
    let t = table(
      kind(),
      @[Thing(name: "a", size: 1, labels: @["p"]), Thing(name: "b")],
      @[false, true],
      80,
      true,
    )
    check t.mapIt(it.text) ==
      @[
        " thing │ size │ labels",
        " ──────┼──────┼───────",
        " a     │  1.0 │ p", "[b     │  0.0]",
      ]
