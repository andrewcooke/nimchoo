import std/[options, os, strutils, tables, unittest]
import nimchoo/download/[fetch, sinks, sources]
import nimchoo/ui/logfile
import ../support/zips

type Net = ref object
  ## A made-up network and disk: what the server has, and what was asked of it.
  bodies: Table[string, string]
  sizes: Table[string, int64]          ## what a HEAD request says (when the server says)
  failures: Table[string, string]      ## urls that fail, and why
  heads, gets: seq[string]
  free: Option[int64]
  events: seq[DownloadEvent]

proc envOf(net: Net): Env =
  result.fetcher.head = proc(url: string): Option[int64] {.closure, raises: [].} =
    net.heads.add url
    if url in net.sizes: some(net.sizes.getOrDefault(url)) else: none(int64)
  result.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
    net.gets.add url
    if url in net.failures: return FetchResult(ok: false, message: net.failures.getOrDefault(url))
    if url notin net.bodies: return FetchResult(ok: false, status: 404, message: "the server said 404 Not Found")
    FetchResult(ok: true, status: 200, body: net.bodies.getOrDefault(url))
  result.freeBytes = proc(dir: string): Option[int64] {.closure, raises: [].} = net.free

proc failed(net: Net): seq[DownloadEvent] =
  ## The failed events (every fetch starts with a "starting" event that says why it is wanted).
  for e in net.events:
    if e.kind == deFailed: result.add e

proc sinkOf(net: Net): Sink =
  result = proc(ev: DownloadEvent) {.closure, raises: [].} = net.events.add ev

proc newNet(): Net =
  Net(free: some(100'i64 * 1024 * 1024 * 1024))

const chile = "https://download.geonames.org/export/dump/CL.zip"

proc fresh(name: string): string =
  result = getTempDir() / "nch-test-download" / name
  removeDir(result)

suite "download: the sources":
  test "the patterns take the argument":
    check urlFor(geonamesCountry, "CL") == chile
    check fileFor(geonamesCountry, "CL") == "CL.zip"
    check entryFor(geonamesCountry, "CL") == "CL.txt"
    check urlFor(geonamesOutlines) == "https://download.geonames.org/export/dump/shapes_simplified_low.json.zip"
    check entryFor(geonamesCountryInfo) == ""

suite "download: fetching":
  test "a file is fetched, checked, kept, and said once; the second time it is just there":
    let net = newNet()
    net.bodies[chile] = makeZip([("CL.txt", "1\tSantiago\n"), ("readme.txt", "x")])
    net.sizes[chile] = int64(net.bodies.getOrDefault(chile).len)
    let dir = fresh("ok")
    let got = fetchSource(envOf(net), sinkOf(net), dir, geonamesCountry, "CL")
    check got == some(dir / "geonames" / "CL.zip")
    check readFile(got.get) == net.bodies.getOrDefault(chile)
    check not fileExists(got.get & ".part")
    check net.events.len == 2 and net.events[0].kind == deStarting and net.events[1].kind == deDownloaded
    check net.events[0].message == "names of places and mountains in CL to name climbs and activities"
    check describe(net.events[0]) == "need names of places and mountains in CL to name climbs and activities"
    check net.events[1].url == chile and net.events[1].bytes == int64(net.bodies.getOrDefault(chile).len)
    check net.heads == @[chile] and net.gets == @[chile]
    # again: no request, no event
    check fetchSource(envOf(net), sinkOf(net), dir, geonamesCountry, "CL") == got
    check net.heads.len == 1 and net.gets.len == 1 and net.events.len == 2

  test "a file that is not a zip, a zip without the entry, an empty file: refused, nothing kept":
    let dir = fresh("bad")
    for body in ["this is not a zip", makeZip([("AR.txt", "x")]), ""]:
      let net = newNet()
      net.bodies[chile] = body
      check fetchSource(envOf(net), sinkOf(net), dir, geonamesCountry, "CL").isNone
      check net.failed.len == 1
      check not fileExists(dir / "geonames" / "CL.zip") and not fileExists(dir / "geonames" / "CL.zip.part")
    let net = newNet()
    net.bodies[chile] = makeZip([("CL.txt", "")])
    check fetchSource(envOf(net), sinkOf(net), dir, geonamesCountry, "CL").isNone
    check "empty" in net.failed[0].message

  test "a plain file needs only to have something in it":
    let net = newNet()
    let dir = fresh("plain")
    let url = urlFor(geonamesCountryInfo)
    net.bodies[url] = "AD\tAND\n"
    check fetchSource(envOf(net), sinkOf(net), dir, geonamesCountryInfo).isSome
    check readFile(dir / "geonames" / "countryInfo.txt") == "AD\tAND\n"

  test "the network failing is said, with why":
    let net = newNet()
    net.failures[chile] = "cannot reach download.geonames.org"
    let dir = fresh("net")
    check fetchSource(envOf(net), sinkOf(net), dir, geonamesCountry, "CL").isNone
    check net.failed.len == 1 and "cannot reach" in net.failed[0].message
    check describe(net.failed[0]) == "cannot download " & chile & ": cannot reach download.geonames.org"
    # a country that does not exist
    check fetchSource(envOf(net), sinkOf(net), dir, geonamesCountry, "XX").isNone
    check "404" in net.failed[1].message

  test "a file bigger than the source allows is not fetched":
    let net = newNet()
    net.bodies[chile] = makeZip([("CL.txt", "x")])
    net.sizes[chile] = 300'i64 * 1024 * 1024
    check fetchSource(envOf(net), sinkOf(net), fresh("big"), geonamesCountry, "CL").isNone
    check net.gets.len == 0 and "more than" in net.failed[0].message
    # ... and one that turns out bigger than the server said
    let net2 = newNet()
    let small = Source(name: "t", url: "http://x/{arg}", file: "{arg}", maxBytes: 10)
    net2.bodies["http://x/a"] = repeat("z", 50)
    check fetchSource(envOf(net2), sinkOf(net2), fresh("big2"), small, "a").isNone

  test "the room on the disk is checked before the fetch":
    let net = newNet()
    net.bodies[chile] = makeZip([("CL.txt", "x")])
    net.sizes[chile] = 1_400_000
    net.free = some(400'i64 * 1024 * 1024)                  # less than the 500 MB kept in reserve
    check fetchSource(envOf(net), sinkOf(net), fresh("room"), geonamesCountry, "CL").isNone
    check net.gets.len == 0 and "not enough room" in net.failed[0].message
    check "free" in net.failed[0].message
    net.free = some(2'i64 * 1024 * 1024 * 1024)
    check fetchSource(envOf(net), sinkOf(net), fresh("room"), geonamesCountry, "CL").isSome
    # the size three times over counts: 150 MB wants 450 MB and the reserve
    let net2 = newNet()
    net2.bodies[chile] = makeZip([("CL.txt", "x")])
    net2.sizes[chile] = 150'i64 * 1024 * 1024
    net2.free = some(900'i64 * 1024 * 1024)
    check fetchSource(envOf(net2), sinkOf(net2), fresh("room2"), geonamesCountry, "CL").isNone
    net2.free = some(1000'i64 * 1024 * 1024)
    check fetchSource(envOf(net2), sinkOf(net2), fresh("room2"), geonamesCountry, "CL").isSome

  test "when the server does not say how big, the most the source allows is assumed; when the disk cannot be asked, go on":
    let net = newNet()
    net.bodies[chile] = makeZip([("CL.txt", "x")])
    net.free = some(1'i64 * 1024 * 1024 * 1024)             # 200 MB * 3 + 500 MB needs more than this
    check fetchSource(envOf(net), sinkOf(net), fresh("unknown"), geonamesCountry, "CL").isNone
    net.free = none(int64)
    check fetchSource(envOf(net), sinkOf(net), fresh("unknown"), geonamesCountry, "CL").isSome

  test "what the downloads take, and clearing them":
    let net = newNet()
    net.bodies[chile] = makeZip([("CL.txt", "x")])
    let dir = fresh("usage")
    check dataUsage(dir) == DataUsage()
    discard fetchSource(envOf(net), sinkOf(net), dir, geonamesCountry, "CL")
    check dataUsage(dir).files == 1 and dataUsage(dir).bytes == int64(net.bodies.getOrDefault(chile).len)
    check clearData(dir).files == 1
    check dataUsage(dir) == DataUsage() and not dirExists(dir)
    check humanBytes(1_400_000) == "1.4 MB" and humanBytes(85_000) == "85 kB" and humanBytes(12) == "12 bytes"

suite "download: the same events in the log and on the screen":
  test "downloaded is info, failed is an error; the screen gets a line each":
    let path = getTempDir() / "nch-test-download" / "log" / "nch.log"
    removeDir(parentDir(path))
    let l = openLog(path)
    var said: seq[string]
    let sink = fanOut(@[logSink(l, "climbs"),
                        screenSink(proc(line: string) {.closure, raises: [].} = said.add line)])
    sink(DownloadEvent(kind: deStarting, source: "geonames", url: chile, message: "names of places in CL"))
    sink(DownloadEvent(kind: deDownloaded, source: "geonames", url: chile, path: "/c/CL.zip", bytes: 1_421_434))
    sink(DownloadEvent(kind: deFailed, source: "geonames", url: chile, message: "cannot reach"))
    l.close()
    let text = readFile(path)
    check "INFO  climbs    note       need names of places in CL" in text
    check "INFO  climbs    downloaded" in text and chile in text and "1.4 MB" in text
    check "ERROR climbs    failed" in text and "cannot reach" in text
    check said == @["need names of places in CL", "downloaded " & chile & " (1.4 MB)", "cannot download " & chile & ": cannot reach"]
