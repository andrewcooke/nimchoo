import std/[options, os, sequtils, strutils, unittest]
import nimchoo/packages/util/args/[args, usage]
import nimchoo/packages/web/pages
import nimchoo/packages/web/request
import nimchoo/packages/web/webopts

let dir = getTempDir() / "nch-test-pages"

suite "serve pages: the shared helpers":
  test "text is escaped for a page":
    check htmlEscape("<b>\"a\" & b</b>") == "&lt;b&gt;&quot;a&quot; &amp; b&lt;/b&gt;"
    check htmlEscape("plain") == "plain"

type Holder = object
  web: WebArgs

func `==`(p: Problem, said: string): bool =
  p.get("") == said

suite "serve web options: shared by the commands":
  let spec = Spec[Holder](opts: webOptions(Holder, web, "the chart", "the CSV file"))
  test "each option is taken, with its value":
    var h = Holder(web: initWebArgs())
    check parseOptions(@["--start", "--port", "0", "--new-token"], spec, h) == ""
    check h.web.start and h.web.newToken and h.web.port == 0
    check parseOptions(@["--file", "--worker"], spec, h) == ""
    check h.web.file and h.web.worker
    check parseOptions(@["--web"], spec, h) == "unexpected option `--web`"
      # (it is the default now)
    check parseOptions(@["--other"], spec, h) == "unexpected option `--other`"
      # (not ours)
  test "bad ports":
    for bad in [@["--port"], @["--port", "x"], @["--port", "-1"], @["--port", "65536"]]:
      var h = Holder(web: initWebArgs())
      check parseOptions(bad, spec, h).isSome
  test "what the options ask for, or what is wrong with the combination":
    check webMode(initWebArgs()).params.kind == wkServe # (the page is the default)
    var w = initWebArgs()
    w.file = true
    check webMode(w).params.kind == wkFile
    w.worker = true
    check webMode(w).problem.contains("cannot be used together")
    w = initWebArgs()
    w.worker = true
    check webMode(w).params.kind == wkWorker
    for setting in [0, 1, 2]:
      w = initWebArgs()
      w.file = true
      case setting
      of 0:
        w.start = true
      of 1:
        w.newToken = true
      else:
        w.port = 0
      check webMode(w).problem.contains("for serving the page")
    w = initWebArgs()
    w.start = true
    w.port = 0
    let m = webMode(w).params
    check m.kind == wkServe and m.start and m.port == 0 and not m.newToken
  test "the options describe themselves":
    let docs = spec.docs
    for o in ["--file", "--worker", "--port", "--start", "--new-token"]:
      check docs.anyIt(it.names == @[o] and it.help.len > 0)
    let text = optionLines(docs, 100).join("\n").splitWhitespace.join(" ")
    for o in ["the chart", "CSV file", $defaultPort]:
      check o in text
