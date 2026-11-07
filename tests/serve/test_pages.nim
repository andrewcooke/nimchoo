import std/[os, strutils, unittest]
import nimchoo/cli/args
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

type Holder = object
  web: WebArgs

suite "serve web options: shared by the commands":
  let spec = Spec[Holder](opts: webOptions(Holder, web))
  test "each option is taken, with its value":
    var h = Holder(web: initWebArgs())
    check parseOptions(
      @["--web", "--no-open", "--port", "0", "--new-token", "--worker"], spec, h
    ) == ""
    check h.web.enabled and h.web.noOpen and h.web.newToken and h.web.worker and
      h.web.port == 0
    check parseOptions(@["--other"], spec, h) == "unexpected option --other" # (not ours)
  test "bad ports":
    for bad in [@["--port"], @["--port", "x"], @["--port", "-1"], @["--port", "65536"]]:
      var h = Holder(web: initWebArgs())
      check parseOptions(bad, spec, h).len > 0
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
    for o in [
      "--worker",
      "--web",
      "--port N",
      "--no-open",
      "--new-token",
      "the chart",
      "CSV file",
      "localhost",
      $defaultPort,
    ]:
      check o in t
    for l in t.splitLines:
      if l.startsWith("  --"):
        check l[20 - 1] == ' ' and l[20] != ' '
