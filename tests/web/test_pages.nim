import std/[options, os, sequtils, strutils, unittest]
import nimchoo/packages/util/args/[args, usage]
import nimchoo/core/globals
import nimchoo/packages/cache/cache
import nimchoo/packages/web/pages
import nimchoo/packages/web/request
import nimchoo/packages/web/webopts
import ../support/styles

let dir = getTempDir() / "nch-test-pages"

suite "serve pages: the shared helpers":
  test "text is escaped for a page":
    check htmlEscape("<b>\"a\" & b</b>") == "&lt;b&gt;&quot;a&quot; &amp; b&lt;/b&gt;"
    check htmlEscape("plain") == "plain"

type Holder = object
  web: WebArgs

func `==`(p: Problem, said: string): bool =
  (if p.isSome: p.get.plainText else: "") == said

suite "serve web options: shared by the commands":
  let spec = Spec[Holder](opts: webOptions(Holder, web, "the chart", "the CSV file"))
  test "each option is taken, with its value":
    var h = Holder(web: WebArgs())
    check parseOptions(@["--start", "--port", "0", "--new-token"], spec, h) == ""
    check h.web.start and h.web.newToken and h.web.port == some(0)
    check parseOptions(@["--file", "--worker"], spec, h) == ""
    check h.web.file and h.web.worker
    check parseOptions(@["--web"], spec, h) == "unexpected option `--web`"
      # (it is the default now)
    check parseOptions(@["--other"], spec, h) == "unexpected option `--other`"
      # (not ours)
  test "bad ports":
    for bad in [@["--port"], @["--port", "x"], @["--port", "-1"], @["--port", "65536"]]:
      var h = Holder(web: WebArgs())
      check parseOptions(bad, spec, h).isSome
  test "what the options ask for, or what is wrong with the combination":
    check webMode(WebArgs()).params.kind == wkServe # (the page is the default)
    var w = WebArgs()
    w.file = true
    check webMode(w).params.kind == wkFile
    w.worker = true
    check webMode(w).problem.contains("cannot be used together")
    w = WebArgs()
    w.worker = true
    check webMode(w).params.kind == wkWorker
    for setting in [0, 1, 2]:
      w = WebArgs()
      w.file = true
      case setting
      of 0:
        w.start = true
      of 1:
        w.newToken = true
      else:
        w.port = some(0)
      check webMode(w).problem.contains("for serving the page")
    w = WebArgs()
    w.start = true
    w.port = some(0)
    let m = webMode(w).params
    check m.kind == wkServe and m.start and m.port == 0 and not m.newToken
  test "--port is refused with --file whatever the number: not given is not the default port":
    for port in [$defaultPort, "62466", "0"]:
      var h = Holder(web: WebArgs())
      check parseOptions(@["--file", "--port", port], spec, h) == ""
      check webMode(h.web).problem.contains("for serving the page")
    check webMode(WebArgs(file: true)).kind == pkOk
    check webMode(WebArgs()).params.port == defaultPort
  test "the options describe themselves":
    let docs = spec.docs
    for o in ["--file", "--worker", "--port", "--start", "--new-token"]:
      check docs.anyIt(it.names == @[o] and it.help.len > 0)
    let text = optionLines(docs, 100).plainText.splitWhitespace.join(" ")
    for o in ["the chart", "CSV file", $defaultPort]:
      check o in text

suite "serve pages: the failures every page command says the same way":
  test "no cache directory is one message, naming every variable that is read":
    for name in ["NCH_CACHE", "XDG_CACHE_HOME", "HOME"]:
      check name in noCacheDir
  test "a page that cannot be made or written is a failure of the command":
    let g = Globals(offline: true)
    check templateFailure(g, "nch map", "no value for x (line 3)") == exitFailure
    check cannotWrite(g, "nch ff", "/nowhere") == exitFailure
