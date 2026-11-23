import std/[options, strutils, unittest]
import nimchoo/packages/model/[calc, params]
import nimchoo/packages/editable/editable
import nimchoo/packages/subject/[steps, subjects]
import nimchoo/packages/util/args/args
import nimchoo/packages/tags/tag

proc action(args: varargs[string]): Action[Model] =
  let p = parseArgs(@args)
  doAssert p.kind == pkOk, p.problem
  p.params.action

suite "model: the command line":
  test "no arguments: the selection; --names and --all are the criteria, with the steps":
    check action().kind == akList and action().names.len == 0
    let p = parseArgs(@["--names", "cycling:*", "run", "--within", "--select"]).params
    check p.action.kind == akList and p.action.names == @["cycling:*", "run"] and
      p.steps.select and p.steps.among == amSelection
    check parseArgs(@["--all", "--select"]).params.steps.all
  test "--add with the values given, on default or a base":
    let a = action("--add", "flat")
    check a.kind == akAdd and a.name == "flat" and a.base.isNone and a.given.len == 0
    let q = action(
      "--add", "x", "--base", "flat", "--gamma", "1.5", "--zero", "1", "--one", "5",
      "--max-gap", "30s", "--zones", "60,70,80,90,100", "--fitness-decay", "50d",
      "--fatigue-decay", "9d", "--fitness-scale", "2", "--fatigue-scale", "4", "--tags",
      "sport:cycling*", "bike:*",
    )
    check q.base == some("flat")
    var base = defaultModel()
    base.gamma = 7
    base.fitnessScale = 3
    let m = made(modelKind(), q, base)
    check m.name == "x" and m.gamma == 1.5 and m.one == 5 and m.maxSecs == 30 and
      m.zones == [60.0, 70, 80, 90, 100] and m.fitnessDays == 50 and m.fatigueDays == 9 and
      m.fitnessScale == 2 and m.fatigueScale == 4 and m.patterns.len == 2
    let r = made(modelKind(), action("--add", "y", "--zero", "2"), base)
    check r.gamma == 7 and r.fitnessScale == 3 and r.zero == 2 # (the rest from the base)
  test "--edit changes only what is given; --tags alone clears the patterns":
    var old = defaultModel()
    old.name = "mine"
    old.patterns = @[parsePattern("x").pattern.get]
    let m = edited(modelKind(), action("--edit", "mine", "--gamma", "3", "--tags"), old)
    check m.gamma == 3 and m.zero == old.zero and m.patterns.len == 0 and
      m.name == "mine"
    check edited(modelKind(), action("--edit", "mine", "--rename", "new"), old).name ==
      "new"
  test "durations have their units: 2m is 120 seconds, 36h is 1.5 days":
    let m = made(
      modelKind(),
      action("--add", "x", "--max-gap", "2m", "--fitness-decay", "36h"),
      defaultModel(),
    )
    check m.maxSecs == 120 and m.fitnessDays == 1.5
  test "a duration with no unit is the question, the default unit added":
    let q = parseArgs(
      @["--add", "x", "--max-gap", "30", "--fitness-decay", "50", "--fatigue-decay=9"]
    )
    check q.kind == pkUnit
    check q.fix.args ==
      @[
        "--add", "x", "--max-gap", "30s", "--fitness-decay", "50d", "--fatigue-decay=9d"
      ]
  test "a name is written as a tag is":
    check parseArgs(@["--add", "cycling:hard"]).problem == ""
    check parseArgs(@["--add", "a b"]).problem.contains("holds only")
    check parseArgs(@["--add", "x", "--names", "a"]).problem.contains(
      "`--names` chooses"
    )
    check parseArgs(@["--names", "a b"]).problem.contains("holds only")
  test "the values only with --add or --edit; one action at a time":
    check parseArgs(@["--gamma", "3"]).problem.contains("--add NAME` or changed with")
    check parseArgs(@["--add", "x", "--edit", "y"]).problem.contains("one at a time")
    check parseArgs(@["--base", "x"]).problem.contains("goes with `--add NAME`")
    check parseArgs(@["--rename", "x"]).problem.contains("goes with `--edit NAME`")
    check parseArgs(@["--edit", "x"]).problem.contains("none were given")
    check parseArgs(@["--edit", "x", "--gamma", "2", "--within"]).problem.contains(
      "not with `--add` or `--edit`"
    )
    check parseArgs(@["--select"]).problem.contains("needs criteria or `--all`")
    check parseArgs(@["--names", "x", "--delete", "--also"]).problem.contains(
      "`--delete` shows nothing"
    )
  test "problems":
    check parseArgs(@["--add"]).problem.contains("needs a value")
    check parseArgs(@["--add", "x", "--gamma", "a"]).problem.contains("is a number")
    check parseArgs(@["--add", "x", "--gamma", "nan"]).problem.contains("is a number")
    for bad in ["1.5s", "0s", "nans", "-1s", "2mi"]:
      check parseArgs(@["--add", "x", "--max-gap", bad]).problem.contains(
        "whole seconds"
      )
    check parseArgs(@["--add", "x", "--fitness-decay", "9x"]).problem.contains(
      "a duration with its unit"
    )
    check parseArgs(@["--add", "x", "--zones", "1,2,3"]).problem.contains(
      "five percentages"
    )
    check parseArgs(@["--add", "x", "--zones", "1,2,3,4,x"]).problem.contains(
      "five percentages"
    )
    check parseArgs(@["--add", "x", "--tags", "a b"]).problem.contains("holds only")
    check parseArgs(@["bob"]).problem.contains("`--add bob`")
    check parseArgs(@["-x"]).problem.contains("unexpected option")
  test "what is checked of the whole model, once it is made":
    check problem(
      made(modelKind(), action("--add", "x", "--zero", "7"), defaultModel())
    ).get
      .contains("zero must be less")
    check problem(
      made(
        modelKind(),
        action("--add", "x", "--zones", "90,80,100,110,120"),
        defaultModel(),
      )
    ).get
      .contains("increase")
  test "help":
    check parseArgs(@["-h"]).help
    check parseArgs(@["--add", "x", "--gamma", "q", "-h"]).problem != ""
      # (the first problem stops it)
