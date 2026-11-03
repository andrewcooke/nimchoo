import std/[options, strutils, unittest]
import nimchoo/ff/[command, page, params]
import nimchoo/serve/request
import nimchoo/cache

const csv = "ff--key-ab12cd34ef56--model-default--res-day--to-2018-09-05--tz-utc.csv"

suite "ff: the page":
  test "it draws the file, with the libraries from the CDN under their integrity hashes":
    let h = pageHtml(csv, "Fitness and fatigue, model default", false).get
    check h.contains("fetch('/files/" & csv & "')")
    check h.contains("https://unpkg.com/d3@" & d3Version & "/dist/d3.min.js")
    check h.contains("integrity=\"" & d3Hash & "\"") and h.contains("integrity=\"" & plotHash & "\"")
    check h.contains("plot@" & plotVersion)
    check h.contains("const hourly = false;")
    check pageHtml(csv, "x", true).get.contains("const hourly = true;")
    for placeholder in ["@TITLE@", "@D3@", "@D3HASH@", "@PLOT@", "@PLOTHASH@", "@HOURLY@", "@DATA@"]:
      check placeholder notin h                                          # (every placeholder was replaced)
  test "the page does nothing the content-security policy forbids":
    # no eval or Function(): d3.csvParse (with a row function) uses Function(), so csvParseRows is used
    let h = pageHtml(csv, "t", false).get
    check "csvParse(" notin h and "csvParseRows(" in h
    check "eval(" notin h and "new Function" notin h and "Function(" notin h.replace("csvParse(", "")
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

suite "ff: --worker, --web and the address":
  test "options":
    let p = parseArgs(@["--web", "--no-open", "--port", "0", "--new-token"])
    check p.problem == "" and p.web and p.noOpen and p.newToken and p.port == 0
    check parseArgs(@["--worker"]).worker
    check parseArgs(@[]).port == defaultPort
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
