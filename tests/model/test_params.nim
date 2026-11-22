import std/[strutils, unittest]
import nimchoo/packages/model/params
import nimchoo/packages/util/args/args

suite "model: the command line":
  test "no arguments: the list":
    check parseArgs(@[]).params.action == maList
  test "--add with the defaults, and with variables":
    let p = parseArgs(@["--add", "flat"])
    check p.problem == "" and p.params.action == maAdd and p.params.model.name == "flat" and
      p.params.model.gamma == 2
    let q = parseArgs(
      @[
        "--add", "x", "--gamma", "1.5", "--zero", "1", "--one", "5", "--max-gap", "30s",
        "--zones", "60,70,80,90,100", "--fitness-decay", "50d", "--fatigue-decay", "9d",
      ]
    )
    let m = q.params.model
    check q.problem == "" and m.gamma == 1.5 and m.one == 5 and m.maxSecs == 30 and
      m.zones == [60.0, 70, 80, 90, 100] and m.fitnessDays == 50 and m.fatigueDays == 9
  test "durations have their units: 2m is 120 seconds, 36h is 1.5 days":
    let m = parseArgs(@["--add", "x", "--max-gap", "2m", "--fitness-decay", "36h"]).params.model
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
  test "a name with -- is refused (it is a part of the file names of ff)":
    check parseArgs(@["--add", "a--b"]).problem.contains("not a name")
    check parseArgs(@["--add", "a-b"]).problem == ""
  test "the variables only with --add":
    check parseArgs(@["--gamma", "3"]).problem.contains("only with `--add NAME`")
  test "problems":
    check parseArgs(@["--add"]).problem.contains("needs a value")
    check parseArgs(@["--add", "bad name"]).problem.contains("not a name for a model")
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
    check parseArgs(@["--add", "x", "--zero", "7"]).problem.contains(
      "zero must be less"
    )
    check parseArgs(@["--add", "x", "--zones", "90,80,100,110,120"]).problem.contains(
      "increase"
    )
    check parseArgs(@["bob"]).problem.contains("`--add bob`")
    check parseArgs(@["-x"]).problem.contains("unexpected option")
  test "help":
    check parseArgs(@["-h"]).help
    check parseArgs(@["--add", "x", "--gamma", "q", "-h"]).problem != ""
      # (the first problem stops it)
