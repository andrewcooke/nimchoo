import std/[options, strutils, unittest]
import nimchoo/serve/request

proc target(raw: string): Target =
  parseTarget(raw).get

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
    let r = route(target("/files/heatmap--check-ab--style-lines.geojson")).get
    check r.isFile and r.fileName == "heatmap--check-ab--style-lines.geojson"
  test "files: only plain cache names, no query":
    for bad in [
      "/files/", "/files", "/files/x", "/files/x.exe", "/files/../x.geojson",
      "/files/%2e%2e%2fx.geojson", "/files/a%2Fb.geojson", "/files/x.geojson?a=b",
      "/files/a/b.geojson", "/filesx/y.geojson", "/other/x.geojson",
    ]:
      check route(target(bad)).isNone
  test "the command on the list, with its options, each once":
    let r = route(target("/map?bits=AWAnLmgGhgZI6JjZom&check=c3eef5")).get
    check not r.isFile and r.command == "map"
    check r.args == @["--bits", "AWAnLmgGhgZI6JjZom", "--check", "c3eef5"]
    check route(target("/map")).get.args.len == 0
    check route(target("/map?token=T&bits=AB")).get.args ==
      @["--bits", "AB"] # (the token is not an option)
    check route(target("/map?bits=A--B_-")).isSome
      # (a list may have two dashes in a row)
    check route(target("/map?bits=" & "A".repeat(7000))).isSome # (and be long)
  test "ff: options, and flags that are given as 1":
    let r = route(
      target(
        "/ff?check=ab12cd&model=flat&from=2018-08-01&to=2018-08-31&hourly=1&utc=1&fitness-scale=2&fatigue-scale=5"
      )
    ).get
    check r.command == "ff" and r.pin == "check"
    check r.args ==
      @[
        "--check", "ab12cd", "--model", "flat", "--from", "2018-08-01", "--to",
        "2018-08-31", "--hourly", "--utc", "--fitness-scale", "2", "--fatigue-scale",
        "5",
      ]
    check route(target("/ff")).get.args.len == 0
    check route(target("/map")).get.pin == "bits"
  test "ff: no other option or value":
    for bad in [
      "/ff?hourly=0", "/ff?hourly=", "/ff?hourly", "/ff?hourly=1&hourly=1",
      "/ff?stdout=1", "/ff?web=1", "/ff?worker=1", "/ff?port=1", "/ff?to=yesterday",
      "/ff?to=2018-8-1", "/ff?from=2018-08-0x", "/ff?model=a%20b", "/ff?model=",
      "/ff?fitness-scale=x", "/ff?fatigue-scale=-1", "/ff?fitness-scale=1e3",
      "/ff?style=lines", "/ff/x", "/FF",
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
      "/map/x",
      "/Map",
      "/map?worker=1",
      "/map?save",
      "/map?bits=a&bits=b",
      "/map?bits=a%20b",
      "/map?bits=a;b",
      "/map?bits=a+b",
      "/map?bits=../x",
      "/map?bits=",
      "/map?check=zz",
      "/map?style=lines",
      "/map?tolerance=5",
      "/map?db=/etc/x",
      "/map?bits=" & "+".repeat(10),
    ]:
      check route(target(bad)).isNone
