import std/[os, strutils, unittest]
import nimchoo/serve/[pages, request, webopts]

let dir = getTempDir() / "nch-test-pages"

suite "serve pages: the shared helpers":
  test "text is escaped for a page":
    check htmlEscape("<b>\"a\" & b</b>") == "&lt;b&gt;&quot;a&quot; &amp; b&lt;/b&gt;"
    check htmlEscape("plain") == "plain"
  test "a file is written whole, with its directory made, and no part file is left":
    removeDir(dir)
    let path = dir / "a" / "b.txt"
    writeAtomic(path, "one")
    check readFile(path) == "one"
    writeAtomic(path, "two")
    check readFile(path) == "two"
    check not fileExists(path & ".part")

suite "serve web options: shared by the commands":
  test "each option is taken, with its value":
    var w = initWebArgs()
    var i = 0
    var problem = ""
    let args = @["--web", "--no-open", "--port", "0", "--new-token", "--worker", "--other"]
    var taken: seq[string]
    while i < args.len:
      if takeWebOption(args, i, w, problem): taken.add args[i]
      inc i
    check taken == @["--web", "--no-open", "0", "--new-token", "--worker"]
    check w.enabled and w.noOpen and w.newToken and w.worker and w.port == 0 and problem == ""
    var j = 6
    check not takeWebOption(args, j, w, problem)                       # (not ours: left alone)
  test "bad ports":
    for bad in [@["--port"], @["--port", "x"], @["--port", "-1"], @["--port", "65536"]]:
      var w = initWebArgs()
      var i = 0
      var problem = ""
      check takeWebOption(bad, i, w, problem)
      check problem.len > 0
  test "combinations":
    check webProblem(initWebArgs()) == ""
    var w = initWebArgs()
    w.enabled = true
    w.worker = true
    check webProblem(w).contains("cannot be used together")
    w = initWebArgs()
    w.noOpen = true
    check webProblem(w).contains("go with --web")
    w = initWebArgs()
    w.enabled = true
    w.noOpen = true
    w.port = 0
    check webProblem(w) == ""
  test "the help text names every option, in the columns asked for":
    let t = webUsage("the chart", "CSV", 20)
    for o in ["--worker", "--web", "--port N", "--no-open", "--new-token", "the chart", "CSV file", "localhost", $defaultPort]:
      check o in t
    for l in t.splitLines:
      if l.startsWith("  --"): check l[20 - 1] == ' ' and l[20] != ' '
