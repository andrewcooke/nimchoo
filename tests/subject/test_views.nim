import std/[sequtils, strutils, unittest]
import nimchoo/core/line
import nimchoo/packages/util/args/args
import nimchoo/packages/subject/[subjects, views]

type Toy = object ## a frame of no view: what the helpers need, and nothing else
  subject, name, summary: string
  shown: bool

let toys = @[
  Toy(subject: "a", name: "x", summary: "the x", shown: true),
  Toy(subject: "a", name: "y", summary: "the y", shown: false),
  Toy(subject: "b", name: "z", summary: "the z", shown: false),
]

suite "subject: what every view does with its frames":
  test "no frames asked for: those shown, else all of them":
    check chooseFrames(toys, "a", @[], "a toy").params.mapIt(it.name) == @["x"]
    check chooseFrames(toys, "b", @[], "a toy").params.mapIt(it.name) == @["z"]
  test "those asked for, in that order, each once; one that is not there says what are":
    check chooseFrames(toys, "a", @["y", "x", "y"], "a toy").params.mapIt(it.name) ==
      @["y", "x"]
    check chooseFrames(toys, "a", @["z"], "a toy").problem.contains(
      "'z' is not a frame of a (the frames are x, y)"
    )
    check chooseFrames(toys, "c", @[], "a toy").problem.contains(
      "no frame of c can be shown on a toy"
    )
  test "the table: a row a frame under its subject, the shown marked, and what the marks mean":
    let subjects = @[Subject(name: "a", isDefault: true), Subject(name: "b")]
    let t = frameTable(subjects, toys, 80).mapIt(it.text)
    check t.anyIt("x*" in it and "the x" in it) and t.anyIt(
      "y " in it and "the y" in it
    )
    check t[^1].contains("the subject is a when none is given")
