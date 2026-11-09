## `nch ff --web` and `--worker` as a real program, on a fixture database (see
## heatmap/test_web.nim for the general checks of the server: this is that it serves the chart).
## Needs a built ./nch-test (the `test` task builds it); without one these tests are skipped.

import nimchoo/db/statement
import std/[httpclient, os, osproc, sequtils, streams, strtabs, strutils, unittest]
import nimchoo/db/store
import nimchoo/modules
when defined(posix):
  import std/posix

let dir = getTempDir() / "nch-test-ff-web"
let exe = getCurrentDir() / "nch-test"

proc fixture(name: string): tuple[db, cache: string] =
  ## A user with an FTHR and one activity with ten minutes of hard heart rate.
  removeDir(dir / name)
  result = (dir / name / "x.db", dir / name / "cache")
  let s = openStore(result.db, allFragments)
  defer:
    s.close()
  s.db.execute(
    "insert into user_profile(user_id, fthr) values (:userId, 154)", userId = s.userId
  )
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, 'a', 'aa', 0)",
    userId = s.userId,
  )
  let f = s.db.scalar(int64, "select max(id) from file")
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t) values (:fileId, 0, 1535373814, 1535374414)",
    fileId = f,
  )
  let a = s.db.scalar(int64, "select max(id) from activity")
  s.db.execute("begin")
  for k in 0 ..< 600:
    s.db.execute(
      "insert into heartrate(activity_id, t, bpm) values (:activityId, :t, 160)",
      activityId = a,
      t = 1535373814 + k,
    )
  s.db.execute("commit")

proc environment(cache: string): StringTableRef =
  result = newStringTable()
  for k, v in envPairs():
    result[k] = v
  result["NCH_CACHE"] = cache
  result["NCH_LOG"] = ""

proc built(): bool =
  fileExists(exe)

proc keyOf(url: string): string =
  ## The key in an address ("/ff?check=KEY&...").
  let start = url.find("check=") + 6
  url[start ..< url.find('&', start)]

proc worker(db, cache: string, extra: seq[string]): tuple[output: string, code: int] =
  let p = startProcess(
    exe,
    args = @["--db", db, "ff", "--worker", "--utc", "--to", "2018-09-05"] & extra,
    env = environment(cache),
    options = {poStdErrToStdOut},
  )
  result.output = p.outputStream.readAll()
  result.code = p.waitForExit(30_000)
  p.close()

suite "nch ff --worker":
  test "the page, then the CSV, in the cache; nothing else printed":
    if not built():
      skip()
    let f = fixture("worker")
    let (output, code) = worker(f.db, f.cache, @[])
    check code == 0
    let lines = output.strip.splitLines
    check lines.len == 2
    check lines[0].startsWith(f.cache) and lines[0].endsWith(".html")
    check lines[1].startsWith(f.cache) and lines[1].endsWith(".csv")
    check lines[0].startsWith(f.cache / "user" / "ff--") and
      lines[1].startsWith(f.cache / "user" / "ff--")
    check dirExists(f.cache / "system") # (the other part is made too)
    check readFile(lines[0]).contains("plot.umd.min.js")
    let csv = readFile(lines[1]).splitLines
    check csv[0] == "time,fitness,fatigue"
    check csv[1].startsWith("2018-08-27,") # (the ride, 14:03 UTC)
    check csv.len == 1 + 10 + 1 # (to 2018-09-05, and the closing newline)
  test "no FTHR: an error, no files":
    if not built():
      skip()
    let f = fixture("nofthr")
    let s = openStore(f.db, allFragments)
    s.db.execute("delete from user_profile")
    s.close()
    let (output, code) = worker(f.db, f.cache, @[])
    check code == 1 and output.contains("no FTHR")
    check not dirExists(f.cache / "user") or
      toSeq(walkFiles(f.cache / "user" / "*")).len == 0
      # (nothing made; the cache has only what was unpacked)

suite "nch ff --web: a real server":
  test "the address, the cookie, the page and the data":
    if not built():
      skip()
    let f = fixture("web")
    let p = startProcess(
      exe,
      args = @[
        "--db", f.db, "ff", "--web", "--no-open", "--port", "0", "--utc", "--to",
        "2018-09-05",
      ],
      env = environment(f.cache),
      options = {poStdErrToStdOut},
    )
    var url = ""
    var line = ""
    while p.outputStream.readLine(line):
      if line.startsWith("http://"):
        url = line
        break
    check url.len > 0
    check url.contains("/ff?check=") and url.contains("&to=2018-09-05&utc=1&token=")
    let base = url[0 ..< url.find("/ff")]
    let token = url[url.find("token=") + 6 .. ^1]
    let c = newHttpClient(maxRedirects = 0, timeout = 20_000)
    let r1 = c.request(url)
    check r1.code == Http302
    let withCookie = newHttpClient(maxRedirects = 0, timeout = 20_000)
    withCookie.headers = newHttpHeaders({"Cookie": "nch=" & token})
    let page = withCookie.request(base & $r1.headers["Location"])
    check page.code == Http200
    check page.body.contains("Fitness and fatigue, model default")
    let dataName = page.body[page.body.find("/files/") .. page.body.find(".csv'") + 3]
    let data = withCookie.request(base & dataName)
    check data.code == Http200
    check $data.headers["Content-Type"] == "text/csv; charset=utf-8"
    check data.body.startsWith("time,fitness,fatigue\n2018-08-27,")
    # the hourly chart is another file
    let unpinned = withCookie.request(base & "/ff?to=2018-09-05&utc=1&hourly=1")
    check unpinned.code == Http302 and
      $unpinned.headers["Location"] ==
      "/ff?check=" & keyOf(url) & "&to=2018-09-05&utc=1&hourly=1"
    let hourly = withCookie.request(base & $unpinned.headers["Location"])
    check hourly.code == Http200 and hourly.body.contains("const hourly = true;")
    check withCookie.request(base & "/ff?to=2018-09-05&bogus=1").code == Http404
    check newHttpClient(maxRedirects = 0).request(base & "/ff").code == Http403
    when defined(posix):
      discard posix.kill(Pid(p.processID), SIGINT)
    else:
      p.terminate()
    check p.waitForExit(10_000) == 130
    p.close()
