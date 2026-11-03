import std/[options, strutils, unittest]
import nimchoo/serve/request

proc target(raw: string): Target = parseTarget(raw).get

suite "serve request: the target":
  test "a path and a decoded query":
    let t = target("/heatmap?sel=ab12&style=lines&x=a%20b")
    check t.path == "/heatmap"
    check t.query == @[("sel", "ab12"), ("style", "lines"), ("x", "a b")]
    check target("/files/x.geojson").query.len == 0
    check target("/heatmap?flag&sel=a").query == @[("flag", ""), ("sel", "a")]
  test "percent-encoding in the path is decoded":
    check target("/files/a%2Eb").path == "/files/a.b"
  test "not a plain path":
    for bad in ["", "heatmap", "//evil.example/x", "http://x/y", "/a b", "/a\tb", "/a\nb",
                "/a\\b", "/\x7f", "/" & "a".repeat(2001)]:
      check parseTarget(bad).isNone
  test "query helpers":
    let t = target("/heatmap?token=T&sel=ab&style=lines")
    check t.query.queryValue("sel") == some("ab")
    check t.query.queryValue("nope").isNone
    check t.withoutParam("token") == "/heatmap?sel=ab&style=lines"
    check target("/heatmap?token=T").withoutParam("token") == "/heatmap"
    check target("/heatmap").withoutParam("token") == "/heatmap"
    check target("/heatmap?sel=a%20b").withoutParam("token") == "/heatmap?sel=a%20b"

suite "serve request: who is asking":
  test "the Host header must be this server's own address":
    check hostAllowed("127.0.0.1:62466", 62466)
    check hostAllowed("localhost:62466", 62466)
    check hostAllowed("LocalHost:62466", 62466)
    for bad in ["", "127.0.0.1", "127.0.0.1:1", "localhost", "evil.example:62466",
                "127.0.0.1.evil.example:62466", "localhost:62466.evil.example", "[::1]:62466",
                "localhost:62466 ", "0.0.0.0:62466"]:
      check not hostAllowed(bad, 62466)
  test "the cookie":
    check cookieValue("nch=abc", "nch") == "abc"
    check cookieValue("a=1; nch=abc; b=2", "nch") == "abc"
    check cookieValue("a=1; b=2", "nch") == ""
    check cookieValue("", "nch") == ""
    check cookieValue("xnch=abc", "nch") == ""             # (a different cookie)
    check cookieValue("nch=", "nch") == ""
  test "tokens are compared whole":
    check sameToken("abc123", "abc123")
    check not sameToken("abc123", "abc124")
    check not sameToken("abc123", "abc12")
    check not sameToken("", "")                            # (no token never matches)
    check not sameToken("abc", "")

suite "serve request: what is asked for":
  test "a file of the cache":
    let r = route(target("/files/heatmap--sel-ab--style-lines.geojson")).get
    check r.isFile and r.fileName == "heatmap--sel-ab--style-lines.geojson"
  test "files: only plain cache names, no query":
    for bad in ["/files/", "/files", "/files/x", "/files/x.exe", "/files/../x.geojson",
                "/files/%2e%2e%2fx.geojson", "/files/a%2Fb.geojson", "/files/x.geojson?a=b",
                "/files/a/b.geojson", "/filesx/y.geojson", "/other/x.geojson"]:
      check route(target(bad)).isNone
  test "the command on the list, with its options, each once":
    let r = route(target("/heatmap?sel=ab12&style=lines&tolerance=5")).get
    check not r.isFile and r.command == "heatmap"
    check r.args == @["--sel", "ab12", "--style", "lines", "--tolerance", "5"]
    check route(target("/heatmap")).get.args.len == 0
    check route(target("/heatmap?token=T&sel=ab")).get.args == @["--sel", "ab"]  # (the token is not an option)
    check route(target("/heatmap?tolerance=2.5")).get.args == @["--tolerance", "2.5"]
  test "no other command, option or value":
    for bad in ["/", "/import?x=1", "/destroy", "/list?save=1", "/log", "/heatmap/", "/heatmap/x",
                "/Heatmap", "/heatmap?worker=1", "/heatmap?save", "/heatmap?sel=a&sel=b",
                "/heatmap?sel=a%20b", "/heatmap?sel=a;b", "/heatmap?sel=../x", "/heatmap?sel=",
                "/heatmap?style=cells", "/heatmap?tolerance=x", "/heatmap?tolerance=-1",
                "/heatmap?tolerance=1e3", "/heatmap?tolerance=.5", "/heatmap?tolerance=5.",
                "/heatmap?tolerance=1.2.3", "/heatmap?tolerance=123456789", "/heatmap?db=/etc/x"]:
      check route(target(bad)).isNone
