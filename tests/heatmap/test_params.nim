import std/[strutils, unittest]
import nimchoo/heatmap/params

suite "heatmap: the command line":
  test "defaults are explicit":
    let p = parseArgs(@[])
    check p.problem == "" and p.check == "" and p.style == "lines" and p.toleranceM == 5.0
  test "the options":
    let p = parseArgs(@["--check", "ab12cd", "--style", "lines", "--tolerance", "2.5"])
    check p.check == "ab12cd" and p.toleranceM == 2.5
  test "--worker":
    check parseArgs(@["--worker"]).web.worker
    check not parseArgs(@[]).web.worker
    check parseArgs(@["--worker", "--check", "ab12", "--tolerance", "10"]).problem == ""
  test "--web and its options":
    let p = parseArgs(@["--web", "--no-open", "--port", "0", "--new-token"])
    check p.problem == "" and p.web.enabled and p.web.noOpen and p.web.newToken and p.web.port == 0
    check parseArgs(@["--web"]).web.port == 62466
    check parseArgs(@["--web", "--port", "8080"]).web.port == 8080
    check not parseArgs(@[]).web.enabled
  test "--web problems":
    check parseArgs(@["--web", "--worker"]).problem.contains("cannot be used together")
    for opt in [@["--no-open"], @["--new-token"], @["--port", "8080"]]:
      check parseArgs(opt).problem.contains("go with --web")
    for bad in ["x", "-1", "65536", "1.5", ""]:
      check parseArgs(@["--web", "--port", bad]).problem.contains("port number")
    check parseArgs(@["--web", "--port"]).problem.contains("needs a value")
  test "zero tolerance means no simplification":
    check parseArgs(@["--tolerance", "0"]).toleranceM == 0.0
  test "problems":
    check parseArgs(@["--check"]).problem.contains("needs a value")
    check parseArgs(@["--check", "a b"]).problem.contains("not a selection hash")
    check parseArgs(@["--style", "cells"]).problem.contains("only style")
    for bad in ["x", "-1", "1001", "", "nan"]:
      check parseArgs(@["--tolerance", bad]).problem.contains("metres")
    check parseArgs(@["--bogus"]).problem.contains("unexpected")
    check parseArgs(@["-h"]).help
  test "metres, for file names":
    check metres(5.0) == "5"
    check metres(2.5) == "2.5"
    check metres(0.0) == "0"
