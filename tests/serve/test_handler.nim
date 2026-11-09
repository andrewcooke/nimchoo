import std/[os, strutils, unittest]
import nimchoo/serve/handler
import nimchoo/serve/request
import nimchoo/core/logfile

const
  token = "0123456789abcdef0123456789abcdef"
  port = 62466
  stem = "map-lusab-babad-fuzoh"

let dir = getTempDir() / "nch-test-serve-handler"

type Fake = ref object
  calls: seq[seq[string]]
  result: WorkerResult

proc runner(f: Fake): WorkerRunner =
  result = proc(args: seq[string]): WorkerResult {.closure, raises: [].} =
    f.calls.add args
    f.result

proc setup(
    name: string, withLog = false
): tuple[cfg: ServerConfig, fake: Fake, cache: string] =
  let cache = dir / name / "cache"
  removeDir(dir / name)
  createDir(cache)
  writeFile(cache / (stem & ".html"), "<html>the page</html>")
  writeFile(
    cache / (stem & ".geojson"), "{\"type\":\"FeatureCollection\",\"features\":[]}"
  )
  let fake = Fake(
    result: WorkerResult(
      stdout:
        cache / (stem & ".html") & "\n" & cache / (stem & ".geojson") & "\n" &
        "bits=AB&check=ab12cd\n"
    )
  )
  var cfg = ServerConfig(
    token: token, cacheDir: cache, baseArgs: @["--db", "/x/y.db"], logCommand: "map"
  )
  if withLog:
    cfg.log = openLog(dir / name / "nch.log")
  (cfg, fake, cache)

proc handle(
    s: tuple[cfg: ServerConfig, fake: Fake, cache: string], port: int, req: Incoming
): Reply =
  ## (the fake worker runs where the server would run a real one)
  handle(s.cfg, port, req, runner(s.fake))

func get(
    target: string, cookie = "nch=" & token, host = "127.0.0.1:" & $port
): Incoming =
  Incoming(meth: "GET", target: target, host: host, cookie: cookie)

func header(r: Reply, name: string): string =
  for (k, v) in r.headers:
    if k == name:
      return v

suite "serve handler: who may ask":
  test "no token, no cookie: forbidden, and it says what to do":
    let s = setup("none")
    let r = handle(s, port, get("/map", cookie = ""))
    check r.code == 403
    check r.body.contains("nch map --web")
    check s.fake.calls.len == 0 # (nothing was run)
  test "a wrong cookie is as good as none":
    let s = setup("wrongcookie")
    check handle(s, port, get("/map", cookie = "nch=" & "f".repeat(32))).code == 403
    check handle(s, port, get("/map", cookie = "other=" & token)).code == 403
    check s.fake.calls.len == 0
  test "the Host header must be ours, even with the right token":
    let s = setup("host")
    for host in [
      "", "evil.example", "127.0.0.1", "127.0.0.1:1234", "evil.example:62466"
    ]:
      check handle(s, port, get("/map", host = host)).code == 403
    check s.fake.calls.len == 0
  test "only GET":
    let s = setup("method")
    for m in ["POST", "PUT", "DELETE", "HEAD", "OPTIONS", "get"]:
      var req = get("/map")
      req.meth = m
      check handle(s, port, req).code == 405
    check s.fake.calls.len == 0
  test "an unreadable address is a bad request":
    let s = setup("bad")
    check handle(s, port, get("/a b")).code == 400
    check handle(s, port, get("//evil.example/x")).code == 400
  test "the token in the address: the cookie is set and the browser goes on without it":
    let s = setup("token")
    let r =
      handle(s, port, get("/map?token=" & token & "&bits=AB&check=ab12cd", cookie = ""))
    check r.code == 302
    check r.header("Location") == "/map?bits=AB&check=ab12cd"
    let c = r.header("Set-Cookie")
    check c ==
      "nch=" & token & "; HttpOnly; SameSite=Strict; Path=/; Max-Age=" & $cookieMaxAge
    check s.fake.calls.len == 0 # (nothing run until the cookie is back)
    check r.body == ""
  test "the token alone":
    let s = setup("tokenonly")
    check handle(s, port, get("/map?token=" & token, cookie = "")).header("Location") ==
      "/map"
  test "a wrong token in the address: forbidden, no cookie":
    let s = setup("wrongtoken")
    let r = handle(s, port, get("/map?token=" & "0".repeat(32), cookie = ""))
    check r.code == 403 and r.header("Set-Cookie") == ""
    check handle(s, port, get("/map?token=", cookie = "")).code == 403

suite "serve handler: pages":
  test "the worker is asked, with the base options, and the page it makes is sent":
    let s = setup("page")
    let r = handle(s, port, get("/map?bits=AB&check=ab12cd"))
    check r.code == 200
    check r.body == "<html>the page</html>"
    check r.header("Content-Type") == "text/html; charset=utf-8"
    check s.fake.calls ==
      @[@["--db", "/x/y.db", "map", "--worker", "--bits", "AB", "--check", "ab12cd"]]
  test "no list of activities: the current selection is pinned in the address, as the worker says":
    let s = setup("pin")
    let r = handle(s, port, get("/map"))
    check r.code == 302
    check r.header("Location") == "/map?bits=AB&check=ab12cd"
    check s.fake.calls == @[@["--db", "/x/y.db", "map", "--worker"]]
  test "the worker failing: its message, as text, not markup":
    let s = setup("fails")
    s.fake.result = WorkerResult(
      code: 1, stderr: "nch map: the selection is empty <script>x</script>\n"
    )
    let r = handle(s, port, get("/map?bits=AB&check=ab12cd"))
    check r.code == 500
    check r.body.contains("the selection is empty &lt;script&gt;x&lt;/script&gt;")
    check not r.body.contains("<script>")
    s.fake.result = WorkerResult(code: 1)
    check handle(s, port, get("/map?bits=AB&check=ab12cd")).body.contains(
      "nch map failed"
    )
  test "a worker that names something else than a page of the cache is not believed":
    let s = setup("liar")
    for named in [
      "",
      "\n",
      "/etc/passwd\n",
      s.cache / "x.geojson\n",
      "/tmp/" & stem & ".html\n",
      s.cache / ".." / stem & ".html\n",
    ]:
      s.fake.result = WorkerResult(stdout: named)
      check handle(s, port, get("/map?bits=AB&check=ab12cd")).code == 500
  test "a page that is not there is not found":
    let s = setup("gone")
    removeFile(s.cache / (stem & ".html"))
    check handle(s, port, get("/map?bits=AB&check=ab12cd")).code == 404
  test "no other command is run, and no other option":
    let s = setup("allow")
    for bad in [
      "/", "/import", "/destroy?x=1", "/list?save=1", "/map?worker=1", "/map?db=/etc/x",
      "/map?bits=a;b", "/map?style=cells", "/map/x", "/Map", "/heatmap", "/log",
    ]:
      check handle(s, port, get(bad)).code == 404
    check s.fake.calls.len == 0

suite "serve handler: the second command":
  test "ff: pinned like the heat map, and its CSV is served as text/csv":
    let s = setup("ff")
    let ffStem = "ff--check-ab12cd34ef56--model-default--res-day--to-2018-09-05--tz-utc"
    writeFile(s.cache / (ffStem & ".html"), "<html>the chart</html>")
    writeFile(s.cache / (ffStem & ".csv"), "time,fitness,fatigue\n")
    s.fake.result = WorkerResult(
      stdout: s.cache / (ffStem & ".html") & "\n" & s.cache / (ffStem & ".csv") & "\n"
    )
    # without a key the data are "the current ones": the address is pinned to their key
    let p = handle(s, port, get("/ff?to=2018-09-05&hourly=1"))
    check p.code == 302 and
      p.header("Location") == "/ff?check=ab12cd34ef56&to=2018-09-05&hourly=1"
    let r = handle(s, port, get(p.header("Location")))
    check r.code == 200 and r.body == "<html>the chart</html>"
    check s.fake.calls[^1] ==
      @[
        "--db", "/x/y.db", "ff", "--worker", "--check", "ab12cd34ef56", "--to",
        "2018-09-05", "--hourly",
      ]
    let c = handle(s, port, get("/files/" & ffStem & ".csv"))
    check c.code == 200 and c.header("Content-Type") == "text/csv; charset=utf-8"
    check c.body == "time,fitness,fatigue\n"

suite "serve handler: files":
  test "a file of the cache, with its type":
    let s = setup("files")
    let g = handle(s, port, get("/files/" & stem & ".geojson"))
    check g.code == 200 and g.header("Content-Type") == "application/geo+json"
    check g.body.contains("FeatureCollection")
    let h = handle(s, port, get("/files/" & stem & ".html"))
    check h.code == 200 and h.header("Content-Type") == "text/html; charset=utf-8"
    check s.fake.calls.len == 0
  test "not there, or not a cache name: not found":
    let s = setup("nofile")
    writeFile(s.cache.parentDir / "secret.geojson", "secret")
    for bad in [
      "/files/missing.geojson",
      "/files/../secret.geojson",
      "/files/%2e%2e%2fsecret.geojson",
      "/files/%2e%2e/secret.geojson",
      "/files/x.txt",
      "/files/",
      "/files/a/b.geojson",
      "/files/" & stem & ".geojson?x=1",
    ]:
      let r = handle(s, port, get(bad))
      check r.code == 404
      check not r.body.contains("secret")
  test "the token file is never served":
    let s = setup("tokenfile")
    writeFile(s.cache / "server-token", token)
    check handle(s, port, get("/files/server-token")).code == 404
    check handle(s, port, get("/files/server-token.html")).code == 404

suite "serve handler: every reply":
  test "carries the security headers, whatever it is":
    let s = setup("headers")
    for req in [
      get("/map?bits=AB&check=ab12cd"),
      get("/map", cookie = ""),
      get("/nope"),
      get("/files/" & stem & ".geojson"),
      get("/a b"),
      get("/map", host = "evil"),
    ]:
      let r = handle(s, port, req)
      check r.header("X-Content-Type-Options") == "nosniff"
      check r.header("Cache-Control") == "no-cache"
      let p = r.header("Content-Security-Policy")
      check p.contains("default-src 'none'") and p.contains("connect-src 'self'")
      check p.contains("https://unpkg.com") and
        p.contains("https://tile.openstreetmap.org")
      check p.contains("frame-ancestors 'none'")
  test "nothing in the policy allows other places":
    let p =
      handle(setup("policy"), port, get("/nope")).header("Content-Security-Policy")
    check p.count("http") == 4 # unpkg twice, unpkg for images, the tiles
    check not p.contains("*")

suite "serve handler: the log":
  test "what was served and what was refused, never the token":
    let s = setup("log", withLog = true)
    discard
      handle(s, port, get("/map?token=" & token & "&bits=AB&check=ab12cd", cookie = ""))
    discard handle(s, port, get("/map?bits=AB&check=ab12cd"))
    discard handle(s, port, get("/map", cookie = ""))
    discard handle(s, port, get("/nope"))
    s.cfg.log.close()
    let text = readFile(s.cache.parentDir / "nch.log")
    check text.contains("map       served     GET /map?bits=AB&check=ab12cd 302")
      # the token step
    check text.contains("served     GET /map?bits=AB&check=ab12cd 200")
    check text.contains("WARN  map       denied     GET /map 403")
    check text.contains("served     GET /nope 404")
    check not text.contains(token)
