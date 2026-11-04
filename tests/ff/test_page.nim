import std/[options, os, strutils, tables, unittest]
import ../support/env
import nimchoo/bundle/unpack
import nimchoo/serve/libraries
import nimchoo/templating
import nimchoo/ff/[command, page, params]
import nimchoo/serve/request
import nimchoo/cache
import nimchoo/ui/palette

const csv = "ff--key-ab12cd34ef56--model-default--res-day--to-2018-09-05--tz-utc.csv"

let libs = parseLibraries(librariesBundle.data).toTable

suite "ff: the page":
  test "it draws the file, with the libraries from the CDN under their integrity hashes":
    let h = pageHtml(csv, "Fitness and fatigue, model default", false).get
    check h.contains("fetch('/files/" & csv & "')")
    check h.contains("https://unpkg.com/d3@7.9.0/dist/d3.min.js")
    check h.contains("integrity=\"" & libs["d3-js-hash"] & "\"") and h.contains("integrity=\"" & libs["plot-js-hash"] & "\"")
    check h.contains("plot@0.6.17")
    check h.contains("const hourly = false;")
    check pageHtml(csv, "x", true).get.contains("const hourly = true;")
    check "{{" notin h and "}}}" notin h                                 # (every tag was filled in)
  test "the page does nothing the content-security policy forbids":
    # no eval or Function(): d3.csvParse (with a row function) uses Function(), so csvParseRows is used
    let h = pageHtml(csv, "t", false).get
    check "csvParse(" notin h and "csvParseRows(" in h
    check "eval(" notin h and "new Function" notin h and "Function(" notin h.replace("csvParse(", "")
  test "you can drag to zoom and double-click to go back; fitness is green and fatigue red":
    let h = pageHtml(csv, "t", false).get
    for needle in ["pointerdown", "pointermove", "pointerup", "dblclick", "drag to zoom", hex(green), hex(red)]:
      check needle in h
    check h.find("fitness: '" & hex(green) & "'") > 0 and h.find("fatigue: '" & hex(red) & "'") > 0   # (the palette's)
  test "the title is text, not markup":
    let h = pageHtml(csv, "<script>alert(1)</script> & \"x\"", false).get
    check not h.contains("<script>alert") and h.contains("&lt;script&gt;")
  test "only a CSV of the cache can be named":
    for bad in ["../x.csv", "x.geojson", "ff--key-a.html", "a/b.csv", "ff--key-a.csv.exe", ""]:
      check pageHtml(bad, "t", false).isNone
  test "the page loads only from places the server's policy allows":
    let h = pageHtml(csv, "t", false).get
    for line in h.splitLines:
      if line.contains("src=\""):
        check line.contains("https://unpkg.com/")

suite "ff: the template is a file":
  teardown: useTestCache()
  test "the author's template and libraries are used":
    let top = getTempDir() / "nch-test-ff-page"
    removeDir top
    putEnv("NCH_CACHE", top)
    discard pageHtml(csv, "t", false)
    check readFile(systemDir(top) / "templates" / "ff.html") == pageTemplate
    writeFile(systemDir(top) / "templates" / "ff.html",
              "{{title}} {{{hourly}}} {{{green}}} {{{red}}} {{plot-js}} {{#hourly}}by the hour{{/hourly}}{{^hourly}}by the day{{/hourly}}\n")
    check pageHtml(csv, "T", true).get == "T true " & hex(green) & " " & hex(red) & " " & libs["plot-js"] & " by the hour\n"
    check pageHtml(csv, "T", false).get.endsWith("by the day\n")
  test "the pure form":
    check renderPage("{{data}}", @[], csv, "t", false) == some(csv)
    check renderPage("{{data}}", @[], "x.geojson", "t", false).isNone

suite "ff: --worker, --web and the address":
  test "options":
    let p = parseArgs(@["--web", "--no-open", "--port", "0", "--new-token"])
    check p.problem == "" and p.web.enabled and p.web.noOpen and p.web.newToken and p.web.port == 0
    check parseArgs(@["--worker"]).web.worker
    check parseArgs(@["--key", "ab12cd"]).key == "ab12cd"
    check parseArgs(@["--key", "a b"]).problem.contains("not a key")
    check parseArgs(@["--key"]).problem.contains("needs a value")
    check parseArgs(@[]).web.port == defaultPort
  test "problems":
    check parseArgs(@["--web", "--worker"]).problem.contains("cannot be used together")
    check parseArgs(@["--web", "--stdout"]).problem.contains("--stdout")
    check parseArgs(@["--worker", "--stdout"]).problem.contains("--stdout")
    check parseArgs(@["--no-open"]).problem.contains("go with --web")
    check parseArgs(@["--port", "1"]).problem.contains("go with --web")
    check parseArgs(@["--web", "--port", "70000"]).problem.contains("port number")
  test "the address says what was asked for, not the defaults":
    check webQuery(parseArgs(@[])) == ""
    check webQuery(parseArgs(@["--model", "flat", "--hourly", "--utc", "--from", "2018-08-01", "--to", "2018-08-31",
                               "--fitness-scale", "2", "--fatigue-scale", "5.25"])) ==
      "model=flat&from=2018-08-01&to=2018-08-31&hourly=1&utc=1&fitness-scale=2&fatigue-scale=5.25"
  test "every address the command makes is one the server accepts":
    for args in [@["--model", "flat"], @["--hourly", "--utc"], @["--to", "2018-08-31", "--from", "2018-08-01"],
                 @["--fitness-scale", "0.5", "--fatigue-scale", "12"]]:
      let q = webQuery(parseArgs(args))
      let t = parseTarget("/ff?" & q).get
      let r = route(t)
      check r.isSome
      # and the worker, given those options, parses them to the same thing
      check webQuery(parseArgs(r.get.args)) == q
