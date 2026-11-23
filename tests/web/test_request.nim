import std/sequtils
import std/[options, strutils, unittest]
import nimchoo/packages/web/request
import nimchoo/core/extension
import nimchoo/registry

proc target(raw: string): Target =
  parseTarget(raw).get

let pages = registry.extensions.get(webPage)

proc route(t: Target): Option[Route] =
  ## (with the pages the packages offer)
  request.route(t, pages)

suite "serve request: the target":
  test "a path and a decoded query":
    let t = target("/heatmap?check=ab12&style=lines&x=a%20b")
    check t.path == "/heatmap"
    check t.query == @[("check", "ab12"), ("style", "lines"), ("x", "a b")]
    check target("/files/x.geojson").query.len == 0
    check target("/heatmap?flag&check=a").query == @[("flag", ""), ("check", "a")]
  test "percent-encoding in the path is decoded":
    check target("/files/a%2Eb").path == "/files/a.b"
  test "not a plain path":
    for bad in [
      "",
      "heatmap",
      "//evil.example/x",
      "/%2fevil.example/x",
        # (decoded it would be "//evil.example/x": a redirect to it goes to another host)
      "/%2F%2Fevil.example",
      "http://x/y",
      "/a b",
      "/a\tb",
      "/a\nb",
      "/a\\b",
      "/\x7f",
      "/" & "a".repeat(8001),
    ]:
      check parseTarget(bad).isNone
  test "query helpers":
    let t = target("/heatmap?token=T&check=ab&style=lines")
    check t.query.queryValue("check") == some("ab")
    check t.query.queryValue("nope").isNone
    check t.withoutParam("token") == "/heatmap?check=ab&style=lines"
    check target("/heatmap?token=T").withoutParam("token") == "/heatmap"
    check target("/heatmap").withoutParam("token") == "/heatmap"
    check target("/heatmap?check=a%20b").withoutParam("token") == "/heatmap?check=a%20b"

suite "serve request: the address of a redirect":
  test "the path is written encoded, so that it reads back as the same path":
    # (the path was written as decoded: %255E came back as ^, %20 as a space that the parser refuses, %3F as a query)
    for raw in [
      "/files/a%255Eb", "/x=%20c", "/files/a%3Fb?token=T&c=d", "/a%0Ab", "/a%23b"
    ]:
      let t = target(raw)
      let shown = t.withoutParam("token")
      check shown.allIt(it > ' ' and it != '\x7f')
      let again = parseTarget(shown)
      check again.isSome
      check again.get.path == t.path
      check again.get.query == t.query.filterIt(it[0] != "token")
    check target("/files/a%2Eb?token=T").withoutParam("token") == "/files/a.b"
    check target("/files/a%255Eb").withoutParam("token") == "/files/a%255Eb"

suite "serve request: how long an address may be":
  test "the limit is on the address as it is written back, where every byte may be three characters":
    # (found by libFuzzer: 3.3 KB of high bytes was read, and its redirect was 9.9 KB, which the next request refused)
    check parseTarget("/x?k=" & "\xff".repeat(1000)).isSome # 3,000 as %FF
    check parseTarget("/x?k=" & "\xff".repeat(2700)).isNone # 8,100
    let plain = "/x?k=" & "a".repeat(7900)
    check parseTarget(plain).isSome # (and plain text is not made longer)
    let t = parseTarget("/x?k=" & "\xff".repeat(2600)).get # 7,800
    check parseTarget(t.withoutParam("token")).isSome

suite "serve request: who is asking":
  test "the Host header must be this server's own address":
    check hostAllowed("127.0.0.1:62466", 62466)
    check hostAllowed("localhost:62466", 62466)
    check hostAllowed("LocalHost:62466", 62466)
    for bad in [
      "", "127.0.0.1", "127.0.0.1:1", "localhost", "evil.example:62466",
      "127.0.0.1.evil.example:62466", "localhost:62466.evil.example", "[::1]:62466",
      "localhost:62466 ", "0.0.0.0:62466",
    ]:
      check not hostAllowed(bad, 62466)
  test "the cookie":
    check cookieValue("nch=abc", "nch") == "abc"
    check cookieValue("a=1; nch=abc; b=2", "nch") == "abc"
    check cookieValue("a=1; b=2", "nch") == ""
    check cookieValue("", "nch") == ""
    check cookieValue("xnch=abc", "nch") == "" # (a different cookie)
    check cookieValue("nch=", "nch") == ""
  test "tokens are compared whole":
    check sameToken("abc123", "abc123")
    check not sameToken("abc123", "abc124")
    check not sameToken("abc123", "abc12")
    check not sameToken("", "") # (no token never matches)
    check not sameToken("abc", "")

suite "serve request: what is asked for":
  test "a file of the cache":
    let r = route(target("/files/map-routes-climbs.geojson")).get
    check r.isFile and r.fileName == "map-routes-climbs.geojson"
  test "files: only plain cache names, no query":
    for bad in [
      "/files/", "/files", "/files/x", "/files/x.exe", "/files/../x.geojson",
      "/files/%2e%2e%2fx.geojson", "/files/a%2Fb.geojson", "/files/x.geojson?a=b",
      "/files/a/b.geojson", "/filesx/y.geojson", "/other/x.geojson",
    ]:
      check route(target(bad)).isNone
  test "the command on the list, with its options, each once":
    let r = route(target("/map?frame=heat")).get
    check not r.isFile and r.command == "map"
    check r.args == @["--frame", "heat"]
    check route(target("/map")).get.args.len == 0
    check route(target("/map?token=T&frame=heat")).get.args ==
      @["--frame", "heat"] # (the token is not an option)
  test "a command that takes a word has it after a slash, once, if it passes the check":
    let r = route(target("/map/climbs?frame=heat")).get
    check r.command == "map" and r.args == @["climbs", "--frame", "heat"]
    check route(target("/map/climbs")).get.args == @["climbs"]
    for bad in [
      "/map/", "/map/Climbs", "/map/a-b", "/map/a/b", "/map/..", "/map/%2e%2e",
      "/map/a%2Fb", "/ff/default", "/ff/", "/files",
    ]:
      check route(target(bad)).isNone
  test "a list is never in an address: the frames of a map are chosen on its page":
    for bad in ["/map?frames=heat", "/map?frames=routes,heat", "/map?frame=heat,routes"]:
      check route(target(bad)).isNone
  test "plot: the subject, the period and the frame":
    let r = route(target("/plot/ff?after=2018-08-01&before=2018-09-01&frame=form")).get
    check r.command == "plot"
    check r.args ==
      @["ff", "--after", "2018-08-01", "--before", "2018-09-01", "--frame", "form"]
    check route(target("/plot")).get.args.len == 0
  test "plot: no other option or value":
    for bad in [
      "/plot?file=1", "/plot?worker=1", "/plot?port=1", "/plot?frames=form",
      "/plot?before=yesterday", "/plot?before=2018-8-1", "/plot?after=2018-08-0x",
      "/plot?model=x", "/plot/FF", "/plot/ff/x", "/plot?frame=a,b", "/ff", "/Plot",
    ]:
      check route(target(bad)).isNone
  test "no other command, option or value":
    for bad in [
      "/",
      "/import?x=1",
      "/destroy",
      "/list?save=1",
      "/log",
      "/heatmap",
      "/heatmap?check=ab12",
      "/map/",
      "/map/x/y",
      "/Map",
      "/map?worker=1",
      "/map?save",
      "/map?frame=heat&frame=heat",
      "/map?frame=a%20b",
      "/map?frame=a;b",
      "/map?frame=../x",
      "/map?selection=AB",
      "/map?state=zz",
      "/map?file=1",
      "/map?style=lines",
      "/map?tolerance=5",
      "/map?db=/etc/x",
      "/map?frame=" & "+".repeat(10),
    ]:
      check route(target(bad)).isNone

suite "web: the commands it may run":
  test "are commands the registry has":
    let names = registry.commands.mapIt(it.name)
    check pages.len == 2
    for page in pages:
      check page.command in names
  test "no two pages have one command name":
    check pages.mapIt(it.command).deduplicate.len == pages.len
