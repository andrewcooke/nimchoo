import std/[options, sequtils, strutils, unittest]
import nimchoo/packages/map/params
import nimchoo/packages/util/args/args
import nimchoo/packages/web/webopts
import nimchoo/packages/web/request
import ../support/webpages

suite "map: the command line":
  test "no options: the current selection":
    let p = parseArgs(@[])
    check p.problem == "" and p.params.target == tSelection and
      p.params.web.kind == wkNone
  test "--selection and --state":
    let p = parseArgs(@["--selection", "AWAnLmgGhgZI6JjZom", "--state", "c3eef5"])
    check p.problem == "" and p.params.target == tList
    check p.params.selection == "AWAnLmgGhgZI6JjZom" and p.params.state == some(
      "c3eef5"
    )
    check parseArgs(@["--selection", "AWAnLmgGhgZI6JjZom"]).params.state.isNone
      # the check is optional
    check parseArgs(@["--selection", "A--B_"]).problem == ""
      # (two dashes in a row are allowed in a list)
  test "--worker":
    check parseArgs(@["--worker"]).params.web.kind == wkWorker
    check parseArgs(@["--worker", "--selection", "AWAn", "--state", "ab12"]).problem ==
      ""
  test "--web and its options":
    let p = parseArgs(@["--web", "--no-open", "--port", "0", "--new-token"])
    check p.problem == "" and p.params.web.kind == wkServe
    check p.params.web.noOpen and p.params.web.newToken and p.params.web.port == 0
    check parseArgs(@["--web"]).params.web.port == 62466
    check parseArgs(@["--web", "--port", "8080"]).params.web.port == 8080
  test "--web problems":
    check parseArgs(@["--web", "--worker"]).problem.contains("cannot be used together")
    for opt in [@["--no-open"], @["--new-token"], @["--port", "8080"]]:
      check parseArgs(opt).problem.contains("go with --web")
    for bad in ["x", "-1", "65536", "1.5", ""]:
      check parseArgs(@["--web", "--port", bad]).problem.contains("port number")
  test "problems":
    check parseArgs(@["--selection"]).problem.contains("needs a value")
    check parseArgs(@["--selection", "a b"]).problem.contains(
      "not a list of activities"
    )
    check parseArgs(@["--selection", "a+b"]).problem.contains(
      "not a list of activities"
    )
    check parseArgs(@["--selection", "AWAn", "--state", "XYZ"]).problem.contains(
      "not a state of activities"
    )
    check parseArgs(@["--state", "ab12"]).problem.contains("goes with --selection")
    check parseArgs(@["--style", "lines"]).problem.contains("unexpected")
      # (the old options are gone)
    check parseArgs(@["--tolerance", "5"]).problem.contains("unexpected")
    check parseArgs(@["--bogus"]).problem.contains("unexpected")
    check parseArgs(@["-h"]).help

suite "map: the page the server may run":
  test "it is made from the options marked as allowed in an address":
    check mapPage.command == "map" and mapPage.pin == "selection"
    check mapPage.options.mapIt(it.name) == @["selection", "state"]
    check mapPage.flags.len == 0
  test "what it accepts in an address is what the options accept":
    let bits = mapPage.options[0].valid
    check bits("AWAnLmgGhgZI6JjZom") and bits("A--B_") and not bits("") and
      not bits("a b")
    let hex = mapPage.options[1].valid
    check hex("c3eef5") and not hex("XYZ") and not hex("")
