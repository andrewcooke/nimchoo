## `nch heatmap --web` as a real program: started as a subprocess on a fixture database,
## on any free port, and asked for things over plain HTTP.  Needs a built ./nch-test (the
## `test` task builds it); without one these tests are skipped.

import std/[httpclient, json, os, osproc, streams, strtabs, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/modules
when defined(posix):
  import std/posix

let dir = getTempDir() / "nch-test-web"
let exe = getCurrentDir() / "nch-test"      # (built by the `test` task, like the tests: see nimchoo.nimble)

type Web = object
  process: Process
  url, base, token: string

proc fixture(name: string, selected = true): tuple[db, cache: string] =
  ## A database with two activities that have routes, selected (or not).
  removeDir(dir / name)
  result = (dir / name / "x.db", dir / name / "cache")
  let s = openStore(result.db, allFragments)
  defer: s.close()
  for (tag, route) in [("a", "MULTILINESTRING((-9.14 38.72, -9.10 38.75, -9.00 38.80))"),
                       ("b", "MULTILINESTRING((2.35 48.85, 2.40 48.90))")]:
    s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
              s.userId, tag, tag)
    let f = s.db.getValue(sql"select max(id) from file")
    s.db.exec(sql"insert into activity(file_id, session, start_t, end_t) values (?, 0, 1000, 1100)", f)
    let a = s.db.getValue(sql"select max(id) from activity")
    s.db.exec(sql"insert into route(activity_id, geom) values (?, GeomFromText(?, 4326))", a, route)
    if selected:
      s.db.exec(sql"insert into selection(user_id, activity_id) values (?, ?)", s.userId, a)

proc environment(cache: string): StringTableRef =
  result = newStringTable()
  for k, v in envPairs(): result[k] = v
  result["NCH_CACHE"] = cache
  result["NCH_LOG"] = ""                       # (no log)

proc start(db, cache: string, extra: seq[string] = @[]): tuple[web: Web, output: string] =
  ## Start the server (not opening a browser, on any free port) and read the address it
  ## prints.  If it stops instead, `output` is what it said and `web.process` is finished.
  let p = startProcess(exe, args = @["--db", db, "heatmap", "--web", "--no-open", "--port", "0"] & extra,
                       env = environment(cache), options = {poStdErrToStdOut})
  result.web.process = p
  var line = ""
  while p.outputStream.readLine(line):
    result.output.add line & "\n"
    if line.startsWith("http://"):
      result.web.url = line
      result.web.base = line[0 ..< line.find("/heatmap")]
      result.web.token = line[line.find("token=") + 6 .. ^1]
      return

proc stop(w: Web): int =
  ## Ctrl-C, and the exit status.
  when defined(posix):
    discard posix.kill(Pid(w.process.processID), SIGINT)
  else:
    w.process.terminate()
  result = w.process.waitForExit(10_000)
  w.process.close()

proc client(cookie = "", host = ""): HttpClient =
  result = newHttpClient(maxRedirects = 0, timeout = 10_000)
  if cookie.len > 0: result.headers = newHttpHeaders({"Cookie": "nch=" & cookie})
  if host.len > 0:
    result.headers = newHttpHeaders({"Host": host, "Cookie": "nch=" & cookie})

proc built(): bool = fileExists(exe)

suite "nch heatmap --web: a real server":
  test "the address, the cookie, the pinned page, the data":
    if not built(): skip()
    let f = fixture("flow")
    let (w, output) = start(f.db, f.cache)
    check w.url.len > 0
    check output.contains("http://localhost:")
    check w.url.contains("/heatmap?key=") and w.url.contains("&style=lines&tolerance=5&token=")
    check w.token.len == 32
    # the printed address: the token is traded for a cookie
    let c = client()
    let r1 = c.request(w.url)
    check r1.code == Http302
    check r1.headers["Set-Cookie"].contains("nch=" & w.token & "; HttpOnly; SameSite=Strict; Path=/")
    let pinned = $r1.headers["Location"]
    check pinned.startsWith("/heatmap?key=") and not pinned.contains("token")
    # with the cookie: the page, which asks for the data
    let withCookie = client(w.token)
    let page = withCookie.request(w.base & pinned)
    check page.code == Http200
    let html = page.body
    check html.contains("leaflet@1.9.4")
    let dataName = html[html.find("/files/") .. html.find(".geojson'") + 7]
    let data = withCookie.request(w.base & dataName)
    check data.code == Http200
    check $data.headers["Content-Type"] == "application/geo+json"
    check parseJson(data.body)["features"].len == 2
    # no address with only the selection key: pinned again
    let again = withCookie.request(w.base & "/heatmap")
    check again.code == Http302
    check pinned.startsWith($again.headers["Location"])          # (the key; the defaults are not repeated)
    check w.stop() == 130

  test "without the token or with the wrong Host: forbidden":
    if not built(): skip()
    let f = fixture("forbidden")
    let (w, _) = start(f.db, f.cache)
    check w.url.len > 0
    check client().request(w.base & "/heatmap").code == Http403
    check client("0".repeat(32)).request(w.base & "/heatmap").code == Http403
    check client().request(w.base & "/heatmap?token=" & "0".repeat(32)).code == Http403
    check client(w.token, host = "evil.example:" & w.base.split(':')[^1]).request(w.base & "/heatmap").code == Http403
    check client(w.token, host = "127.0.0.1:1").request(w.base & "/heatmap").code == Http403
    check w.stop() == 130

  test "nothing else is served":
    if not built(): skip()
    let f = fixture("nothing")
    let (w, _) = start(f.db, f.cache)
    check w.url.len > 0
    let c = client(w.token)
    for path in ["/", "/destroy", "/import?x=1", "/list?save=1", "/heatmap?worker=1", "/heatmap?db=/etc/passwd",
                 "/files/server-token", "/files/..%2fx.geojson", "/files/%2e%2e%2fserver-token", "/files/nope.geojson"]:
      check c.request(w.base & path).code == Http404
    check c.request(w.base & "/heatmap", httpMethod = HttpPost, body = "x").code in [Http405, Http411]
    check w.stop() == 130

  test "the token is kept in a file only you can read, and kept between runs":
    if not built(): skip()
    let f = fixture("token")
    let (w1, _) = start(f.db, f.cache)
    check w1.stop() == 130
    when defined(posix):
      check getFilePermissions(f.cache / "server-token") == {fpUserRead, fpUserWrite}
    check readFile(f.cache / "server-token").strip == w1.token
    let (w2, _) = start(f.db, f.cache)
    check w2.token == w1.token
    check w2.stop() == 130
    let (w3, _) = start(f.db, f.cache, @["--new-token"])
    check w3.token.len == 32 and w3.token != w1.token
    check readFile(f.cache / "server-token").strip == w3.token
    check w3.stop() == 130

  test "an old cookie stops working after --new-token":
    if not built(): skip()
    let f = fixture("renew")
    let (w1, _) = start(f.db, f.cache)
    check client(w1.token).request(w1.base & "/heatmap").code == Http302
    check w1.stop() == 130
    let (w2, _) = start(f.db, f.cache, @["--new-token"])
    check client(w1.token).request(w2.base & "/heatmap").code == Http403
    check client(w2.token).request(w2.base & "/heatmap").code == Http302
    check w2.stop() == 130

  test "nothing to show: it says so in the terminal and does not start":
    if not built(): skip()
    let f = fixture("empty", selected = false)
    let (w, output) = start(f.db, f.cache)
    check w.url == ""
    check w.process.waitForExit(10_000) == 1
    check output.contains("the selection is empty")
    w.process.close()

  test "a port that is taken: it says so and does not start":
    if not built(): skip()
    let f = fixture("taken")
    let (w, _) = start(f.db, f.cache)
    check w.url.len > 0
    let port = w.base.split(':')[^1]
    let p = startProcess(exe, args = @["--db", f.db, "heatmap", "--web", "--no-open", "--port", port],
                         env = environment(f.cache), options = {poStdErrToStdOut})
    let said = p.outputStream.readAll()
    check p.waitForExit(10_000) == 1
    p.close()
    check said.contains("cannot listen on 127.0.0.1:" & port)
    check w.stop() == 130
