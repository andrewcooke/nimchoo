import std/[strutils, unittest]
import nimchoo/heatmap/params

suite "heatmap: the command line":
  test "defaults are explicit":
    let p = parseArgs(@[])
    check p.problem == "" and p.sel == "" and p.style == "lines" and p.toleranceM == 5.0
  test "the options":
    let p = parseArgs(@["--sel", "ab12cd", "--style", "lines", "--tolerance", "2.5"])
    check p.sel == "ab12cd" and p.toleranceM == 2.5
  test "zero tolerance means no simplification":
    check parseArgs(@["--tolerance", "0"]).toleranceM == 0.0
  test "problems":
    check parseArgs(@["--sel"]).problem.contains("needs a value")
    check parseArgs(@["--sel", "a b"]).problem.contains("not a selection key")
    check parseArgs(@["--style", "cells"]).problem.contains("only style")
    for bad in ["x", "-1", "1001", "", "nan"]:
      check parseArgs(@["--tolerance", bad]).problem.contains("metres")
    check parseArgs(@["--bogus"]).problem.contains("unexpected")
    check parseArgs(@["-h"]).help
  test "metres, for file names":
    check metres(5.0) == "5"
    check metres(2.5) == "2.5"
    check metres(0.0) == "0"
