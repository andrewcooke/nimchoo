import std/[options, sequtils, strutils, unittest]
import nimchoo/packages/map/params
import nimchoo/packages/util/args/args
import nimchoo/packages/web/webopts
import nimchoo/packages/web/request
import ../support/webpages

suite "map: the command line":
  test "no options: the page is served, of the default subject, with the frames that are shown":
    let p = parseArgs(@[])
    check p.problem == "" and p.params.web.kind == wkServe
    check p.params.web.port == defaultPort and not p.params.web.start
    check p.params.subject.isNone and p.params.frames.len == 0
  test "the subject is the one word that is not an option":
    check parseArgs(@["climbs"]).params.subject == some("climbs")
    check parseArgs(@["--file", "activities"]).params.subject == some("activities")
    check parseArgs(@["a", "b"]).problem.contains("at most one SUBJECT")
    check parseArgs(@["Activities"]).problem.contains("not a name of a subject")
    check parseArgs(@["a-b"]).problem.contains("not a name of a subject")
  test "--frames, with --file: words, separated by spaces, in the order given":
    check parseArgs(@["--file", "--frames", "heat"]).params.frames == @["heat"]
    check parseArgs(@["--file", "--frames", "heat", "routes"]).params.frames ==
      @["heat", "routes"]
    check parseArgs(@["--file", "--frames=heat"]).params.frames == @["heat"]
    check parseArgs(@["climbs", "--file", "--frames", "gates", "efforts"]).params.frames ==
      @["gates", "efforts"]
  test "--frames problems: a name that is not a word, or none; without --file (the page has its boxes)":
    for bad in ["", "Heat", "routes,", "heat,routes", "a-b"]:
      check parseArgs(@["--file", "--frames", bad]).problem.contains(
        "not a name of a frame"
      )
    check parseArgs(@["--file", "--frames"]).problem.contains(
      "needs at least one frame"
    )
    check parseArgs(@["--frames", "heat"]).problem.contains("tick the frames")
    check parseArgs(@["--worker", "--frames", "heat"]).problem.contains(
      "tick the frames"
    )
  test "--frame, for the page: one frame, with --worker only":
    check parseArgs(@["--worker", "--frame", "heat"]).params.frame == some("heat")
    check parseArgs(@["--frame", "heat"]).problem.contains("goes with --worker")
    # (its value is checked in an address; on the command line the command says whether it is a frame)
  test "the pinning options and --layers are gone: the map is of the selection":
    for old in [
      @["--selection", "AWAnLmgGhgZI6JjZom"],
      @["--state", "c3eef5"],
      @["--web"],
      @["--layers", "heat"],
    ]:
      check parseArgs(old).problem.contains("unexpected")
  test "--file and --worker":
    check parseArgs(@["--file"]).params.web.kind == wkFile
    check parseArgs(@["--worker"]).params.web.kind == wkWorker
    check parseArgs(@["--file", "--worker"]).problem.contains("cannot be used together")
  test "serving and its options":
    let p = parseArgs(@["--start", "--port", "0", "--new-token"])
    check p.problem == "" and p.params.web.kind == wkServe
    check p.params.web.start and p.params.web.newToken and p.params.web.port == 0
    check parseArgs(@["--port", "8080"]).params.web.port == 8080
  test "serving problems":
    for opt in [@["--start"], @["--new-token"], @["--port", "8080"]]:
      for mode in ["--file", "--worker"]:
        check parseArgs(@[mode] & opt).problem.contains("for serving the page")
    for bad in ["x", "-1", "65536", "1.5", ""]:
      check parseArgs(@["--port", bad]).problem.contains("port number")
  test "problems":
    check parseArgs(@["--style", "lines"]).problem.contains("unexpected")
    check parseArgs(@["--tolerance", "5"]).problem.contains("unexpected")
    check parseArgs(@["--bogus"]).problem.contains("unexpected")
    check parseArgs(@["-h"]).help

suite "map: the page the server may run":
  test "it is made from the options marked as allowed in an address, and takes the subject":
    check mapPage.command == "map"
    check mapPage.options.mapIt(it.name) == @["frame"]
    check mapPage.flags.len == 0
    check mapPage.word != nil
  test "what it accepts in an address is what the options accept":
    let frame = mapPage.options[0].valid
    check frame("routes") and frame("heat") and not frame("") and not frame("Routes") and
      not frame("heat,routes")
    check mapPage.word("climbs") and not mapPage.word("") and not mapPage.word("A") and
      not mapPage.word("a/b")
