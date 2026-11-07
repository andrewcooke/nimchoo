import std/[strutils, unittest]
import nimchoo/model/params

suite "model: the command line":
  test "no arguments: the list":
    check parseArgs(@[]).list
  test "--add with the defaults, and with variables":
    let p = parseArgs(@["--add", "flat"])
    check p.add and not p.list and p.model.name == "flat" and p.model.gamma == 2 and
      p.problem == ""
    let q = parseArgs(
      @[
        "--add", "x", "--gamma", "1.5", "--zero", "1", "--one", "5", "--max-secs", "30",
        "--zones", "60,70,80,90,100", "--fitness-days", "50", "--fatigue-days", "9",
      ]
    )
    check q.problem == "" and q.model.gamma == 1.5 and q.model.one == 5 and
      q.model.maxSecs == 30 and q.model.zones == [60.0, 70, 80, 90, 100] and
      q.model.fitnessDays == 50 and q.model.fatigueDays == 9
  test "the variables only with --add":
    check parseArgs(@["--gamma", "3"]).problem.contains("only with --add")
  test "problems":
    check parseArgs(@["--add"]).problem.contains("needs a value")
    check parseArgs(@["--add", "bad name"]).problem.contains("not a name for a model")
    check parseArgs(@["--add", "x", "--gamma", "a"]).problem.contains("is a number")
    check parseArgs(@["--add", "x", "--gamma", "nan"]).problem.contains("is a number")
    check parseArgs(@["--add", "x", "--max-secs", "1.5"]).problem.contains(
      "whole number"
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
    check parseArgs(@["bob"]).problem.contains("--add bob")
    check parseArgs(@["-x"]).problem.contains("unexpected option")
  test "help":
    check parseArgs(@["-h"]).help
    check parseArgs(@["--add", "x", "--gamma", "q", "-h"]).problem != ""
      # (the first problem stops it)
