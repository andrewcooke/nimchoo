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
  let spec = Spec[Holder](opts: webOptions(Holder, web, "the chart", "CSV"))
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
      check parseOptions(bad, spec, h).isSome
  test "what the options ask for, or what is wrong with the combination":
    check webMode(initWebArgs()).params.kind == wkNone
    var w = initWebArgs()
    w.enabled = true
    w.worker = true
    check webMode(w).problem.contains("cannot be used together")
    w = initWebArgs()
    w.worker = true
    check webMode(w).params.kind == wkWorker
    w = initWebArgs()
    w.noOpen = true
    check webMode(w).problem.contains("go with --web")
    w = initWebArgs()
    w.enabled = true
    w.noOpen = true
    w.port = 0
    let m = webMode(w).params
    check m.kind == wkServe and m.noOpen and m.port == 0 and not m.newToken
  test "the options describe themselves; the ones that go with --web are under it":
    let docs = spec.docs
    for o in ["--worker", "--web", "--port", "--no-open", "--new-token"]:
      check docs.anyIt(it.names == @[o] and it.help.len > 0)
    check docs.filterIt(it.names[0] in ["--port", "--no-open", "--new-token"]).allIt(
      it.level == 1
    )
    let text = optionLines(docs, 100).join("\n").splitWhitespace.join(" ")
    for o in ["the chart", "CSV file", "localhost", $defaultPort]:
      check o in text
