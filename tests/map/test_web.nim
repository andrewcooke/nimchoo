## `nch map` (which serves the page) as a real program: started as a subprocess on a fixture database,
## on any free port, and asked for things over plain HTTP.  Needs a built ./build/nch-test (the
## `test` task builds it); without one these tests are skipped.

import nimchoo/packages/db/statement
import std/[httpclient, json, net, os, osproc, streams, strtabs, strutils, unittest]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess
when defined(posix):
  import std/posix

let dir = getTempDir() / "nch-test-web"
let exe = getCurrentDir() / "build" / "nch-test"
  # (built by the `test` task, like the tests: see nimchoo.nimble)

type Web = object
  process: Process
  url, base, token: string

proc fixture(name: string, selected = true): tuple[db, cache: string] =
  ## A database with two activities that have routes, selected (or not).
  removeDir(dir / name)
  result = (dir / name / "x.db", dir / name / "cache")
  let s = openSession(result.db, allFragments, access = allAccess)
  defer:
    s.close()
  for (tag, route) in [
    ("a", "MULTILINESTRING((-9.14 38.72, -9.10 38.75, -9.00 38.80))"),
    ("b", "MULTILINESTRING((2.35 48.85, 2.40 48.90))"),
  ]:
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_epoch) values (:userId, :name, :sha256, 0)",
      userId = s.userId,
      name = tag,
      sha256 = tag,
    )
    let f = s.db.scalar(int64, "select max(id) from file")
    s.db.execute(
      "insert into activity(file_id, session, start_epoch, end_epoch) values (:fileId, 0, 1000, 1100)",
      fileId = f,
    )
    let a = s.db.scalar(int64, "select max(id) from activity")
    s.db.execute(
      "insert into route(activity_id, geom) values (:activityId, GeomFromText(:wkt, 4326))",
      activityId = a,
      wkt = route,
    )
    if selected:
      s.db.execute(
        "insert into activity_selection(user_id, activity_id) values (:userId, :activityId)",
        userId = s.userId,
        activityId = a,
      )

proc environment(cache: string): StringTableRef =
  result = newStringTable()
  for k, v in envPairs():
    result[k] = v
  result["NCH_CACHE"] = cache
  result["NCH_LOG"] = "" # (no log)

proc start(
    db, cache: string, extra: seq[string] = @[]
): tuple[web: Web, output: string] =
  ## Start the server (not opening a browser, on any free port) and read the address it
  ## prints.  If it stops instead, `output` is what it said and `web.process` is finished.
  let p = startProcess(
    exe,
    args = @["--db", db, "map", "--start", "--port", "0"] & extra,
    env = environment(cache),
    options = {poStdErrToStdOut},
  )
  result.web.process = p
  var line = ""
  while p.outputStream.readLine(line):
    result.output.add line & "\n"
    if line.startsWith("http://"):
      result.web.url = line
      result.web.base = line[0 ..< line.find("/map")]
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
  if cookie.len > 0:
    result.headers = newHttpHeaders({"Cookie": "nch=" & cookie})
  if host.len > 0:
    result.headers = newHttpHeaders({"Host": host, "Cookie": "nch=" & cookie})

proc built(): bool =
  fileExists(exe)

when defined(posix):
  proc resetAfterSending(w: Web, path: string) =
    ## Ask for `path` and, before the reply, drop the connection with a reset (SO_LINGER 0): the browser that closed its tab.
    let port = parseInt(w.base.split(':')[^1])
    let s = newSocket()
    s.connect("localhost", Port(port))
    s.send(
      "GET " & path & " HTTP/1.1\r\nHost: localhost:" & $port & "\r\nCookie: nch=" &
        w.token & "\r\nConnection: close\r\n\r\n"
    )
    var l = Tlinger(l_onoff: 1, l_linger: 0)
    discard setsockopt(s.getFd, SOL_SOCKET, SO_LINGER, addr l, SockLen(sizeof(l)))
    s.close()

suite "nch map: a real server":
  test "the address, the cookie, the page, the data":
    if not built():
      skip()
    let f = fixture("flow")
    let (w, output) = start(f.db, f.cache)
    check w.url.len > 0
    check output.contains("http://localhost:")
    check w.url.contains("/map/activities?token=")
    check w.token.len == 32
    # the printed address: the token is traded for a cookie
    let c = client()
    let r1 = c.request(w.url)
    check r1.code == Http302
    check ($r1.headers["Set-Cookie"]).startsWith(
      "nch=" & w.token & "; HttpOnly; SameSite=Strict; Path=/; Max-Age="
    )
    let pinned = $r1.headers["Location"]
    check pinned == "/map/activities" # (the subject, not the data nor the frames)
    # with the cookie: the page, which lists the frames and fetches the data of each it shows
    let withCookie = client(w.token)
    let page = withCookie.request(w.base & pinned)
    check page.code == Http200
    let html = page.body
    check html.contains("leaflet@1.9.4")
    check html.contains("\"name\":\"routes\"") and html.contains("\"name\":\"heat\"")
    let data = withCookie.request(w.base & "/map/activities?frame=routes")
    check data.code == Http200
    check $data.headers["Content-Type"] == "application/geo+json"
    check parseJson(data.body)["features"].len == 2
    check withCookie.request(w.base & "/map/activities?frame=nonesuch").code == Http500
      # (the worker says it is not a frame of the subject)
    # an address without a subject is the default one
    check withCookie.request(w.base & "/map").code == Http200
    check dirExists(f.cache / "user") and dirExists(f.cache / "system")
    check fileExists(f.cache / "server-token")
      # (the token is at the top, not in what is served)
    check withCookie.request(w.base & "/files/server-token").code == Http404
    check w.stop() == 130

  test "a connection reset before the reply (a closed tab) does not stop the server":
    if not built():
      skip()
    when defined(posix):
      let f = fixture("reset")
      let (w, _) = start(f.db, f.cache)
      check w.url.len > 0
      for k in 1 .. 3:
        # (a frame needs a worker, so the reply is made after the connection has gone)
        w.resetAfterSending("/map/activities?frame=routes")
      sleep(1500)
      check w.process.running
      let c = client(w.token)
      check c.request(w.base & "/map/activities?frame=routes").code == Http200
      check c.request(w.base & "/map").code == Http200
      check w.stop() == 130
    else:
      skip()
  test "without the token or with the wrong Host: forbidden":
    if not built():
      skip()
    let f = fixture("forbidden")
    let (w, _) = start(f.db, f.cache)
    check w.url.len > 0
    check client().request(w.base & "/map").code == Http403
    check client("0".repeat(32)).request(w.base & "/map").code == Http403
    check client().request(w.base & "/map?token=" & "0".repeat(32)).code == Http403
    check client(w.token, host = "evil.example:" & w.base.split(':')[^1])
      .request(w.base & "/map").code == Http403
    check client(w.token, host = "127.0.0.1:1").request(w.base & "/map").code == Http403
    check w.stop() == 130

  test "nothing else is served":
    if not built():
      skip()
    let f = fixture("nothing")
    let (w, _) = start(f.db, f.cache)
    check w.url.len > 0
    let c = client(w.token)
    for path in [
      "/", "/destroy", "/import?x=1", "/list?save=1", "/map?worker=1",
      "/map?db=/etc/passwd", "/map?selection=AB", "/map?state=ab12cd",
      "/map?layers=heat", "/map/a/b", "/map/Activities", "/map/activities?frames=Heat",
      "/files/server-token", "/files/..%2fx.geojson", "/files/%2e%2e%2fserver-token",
      "/files/nope.geojson",
    ]:
      check c.request(w.base & path).code == Http404
    check c.request(w.base & "/map", httpMethod = HttpPost, body = "x").code in
      [Http405, Http411]
    check w.stop() == 130

  test "the token is kept in a file only you can read, and kept between runs":
    if not built():
      skip()
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
    if not built():
      skip()
    let f = fixture("renew")
    let (w1, _) = start(f.db, f.cache)
    check client(w1.token).request(w1.base & "/map").code == Http200
    check w1.stop() == 130
    let (w2, _) = start(f.db, f.cache, @["--new-token"])
    check client(w1.token).request(w2.base & "/map").code == Http403
    check client(w2.token).request(w2.base & "/map").code == Http200
    check w2.stop() == 130

  test "nothing to show: it says so in the terminal and does not start, which is no failure":
    if not built():
      skip()
    let f = fixture("empty", selected = false)
    let (w, output) = start(f.db, f.cache)
    check w.url == ""
    check w.process.waitForExit(10_000) == 0
    check output.contains("the selection of activities is empty")
    w.process.close()

  test "a second command on the server's port opens its page there and returns: one server for every page":
    if not built():
      skip()
    let f = fixture("second")
    let (w, _) = start(f.db, f.cache)
    check w.url.len > 0
    let port = w.base.split(':')[^1]
    let p = startProcess(
      exe,
      args = @["--db", f.db, "map", "--start", "--port", port],
      env = environment(f.cache),
      options = {poStdErrToStdOut},
    )
    let said = p.outputStream.readAll()
    check p.waitForExit(10_000) == 0
    p.close()
    check said.contains(w.base & "/map/activities?token=")
    check said.contains("already running")
    check client(w.token).request(w.base & "/map/activities?frame=heat").code == Http200
      # (the first server makes the data the page asks for)
    check w.stop() == 130

  test "--stop stops the server, from another command; with none running it says so":
    if not built():
      skip()
    let f = fixture("stop")
    let (w, _) = start(f.db, f.cache)
    let port = w.base.split(':')[^1]
    proc stopCommand(): tuple[said: string, code: int] =
      let p = startProcess(
        exe,
        args = @["--db", f.db, "map", "--stop", "--port", port],
        env = environment(f.cache),
        options = {poStdErrToStdOut},
      )
      result.said = p.outputStream.readAll()
      result.code = p.waitForExit(10_000)
      p.close()

    let first = stopCommand()
    check first.code == 0 and first.said.contains("stopped the server on port " & port)
    check w.process.waitForExit(10_000) == 0 # (asked to stop: not interrupted)
    w.process.close()
    let again = stopCommand()
    check again.code == 0 and again.said.contains(
      "no server is running on port " & port
    )

  test "a page cannot ask the server what it is or stop it: those need the token in a header of their own":
    if not built():
      skip()
    let f = fixture("control")
    let (w, _) = start(f.db, f.cache)
    check client(w.token).request(w.base & "/stop").code == Http403
      # (the cookie is not enough)
    check client(w.token).request(w.base & "/status").code == Http403
    var c = newHttpClient(maxRedirects = 0, timeout = 10_000)
    c.headers = newHttpHeaders({"X-Nch-Token": w.token})
    let r = c.request(w.base & "/status")
    check r.code == Http200 and r.body.contains("nch ") and r.body.contains(f.db)
    check w.stop() == 130

  test "a port held by another program: it says so and does not start":
    if not built():
      skip()
    let f = fixture("taken")
    let other = newSocket()
    other.setSockOpt(OptReuseAddr, true)
    other.bindAddr(Port(0), "127.0.0.1")
    other.listen()
    let port = $int(other.getLocalAddr()[1])
    let p = startProcess(
      exe,
      args = @["--db", f.db, "map", "--start", "--port", port],
      env = environment(f.cache),
      options = {poStdErrToStdOut},
    )
    let said = p.outputStream.readAll()
    check p.waitForExit(20_000) == 1
    p.close()
    other.close()
    check said.contains("cannot listen on 127.0.0.1:" & port)
