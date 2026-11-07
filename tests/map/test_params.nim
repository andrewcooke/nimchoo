import std/[strutils, unittest]
import nimchoo/map/params

suite "map: the command line":
  test "no options: the current selection":
    let p = parseArgs(@[])
    check p.problem == "" and p.bits == "" and p.check == "" and not p.web.enabled and
      not p.web.worker
  test "--bits and --check":
    let p = parseArgs(@["--bits", "AWAnLmgGhgZI6JjZom", "--check", "c3eef5"])
    check p.problem == "" and p.bits == "AWAnLmgGhgZI6JjZom" and p.check == "c3eef5"
    check parseArgs(@["--bits", "AWAnLmgGhgZI6JjZom"]).problem == ""
      # the check is optional
    check parseArgs(@["--bits", "A--B_"]).problem == ""
      # (two dashes in a row are allowed in a list)
  test "--worker":
    check parseArgs(@["--worker"]).web.worker
    check parseArgs(@["--worker", "--bits", "AWAn", "--check", "ab12"]).problem == ""
  test "--web and its options":
    let p = parseArgs(@["--web", "--no-open", "--port", "0", "--new-token"])
    check p.problem == "" and p.web.enabled and p.web.noOpen and p.web.newToken and
      p.web.port == 0
    check parseArgs(@["--web"]).web.port == 62466
    check parseArgs(@["--web", "--port", "8080"]).web.port == 8080
  test "--web problems":
    check parseArgs(@["--web", "--worker"]).problem.contains("cannot be used together")
    for opt in [@["--no-open"], @["--new-token"], @["--port", "8080"]]:
      check parseArgs(opt).problem.contains("go with --web")
    for bad in ["x", "-1", "65536", "1.5", ""]:
      check parseArgs(@["--web", "--port", bad]).problem.contains("port number")
  test "problems":
    check parseArgs(@["--bits"]).problem.contains("needs a value")
    check parseArgs(@["--bits", "a b"]).problem.contains("not a list of activities")
    check parseArgs(@["--bits", "a+b"]).problem.contains("not a list of activities")
    check parseArgs(@["--bits", "AWAn", "--check", "XYZ"]).problem.contains(
      "not a check"
    )
    check parseArgs(@["--check", "ab12"]).problem.contains("goes with --bits")
    check parseArgs(@["--style", "lines"]).problem.contains("unexpected")
      # (the old options are gone)
    check parseArgs(@["--tolerance", "5"]).problem.contains("unexpected")
    check parseArgs(@["--bogus"]).problem.contains("unexpected")
    check parseArgs(@["-h"]).help
