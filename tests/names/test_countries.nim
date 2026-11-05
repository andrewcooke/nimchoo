import std/[options, os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/download/[fetch, sources]
import nimchoo/errors
import nimchoo/modules
import nimchoo/names/countries
import ../support/zips

const outlines = """{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"geoNameId":"3895114"},"geometry":{"type":"Polygon",
   "coordinates":[[[-76.0,-56.0],[-69.5,-56.0],[-69.5,-17.0],[-76.0,-17.0],[-76.0,-56.0]]]}},
 {"type":"Feature","properties":{"geoNameId":"3865483"},"geometry":{"type":"Polygon",
   "coordinates":[[[-69.5,-56.0],[-53.0,-56.0],[-53.0,-21.0],[-69.5,-21.0],[-69.5,-56.0]]]}},
 {"type":"Feature","properties":{"geoNameId":"2510769"},"geometry":{"type":"Polygon",
   "coordinates":[[[-9.5,37.0],[-6.2,42.1],[-6.2,37.0],[-9.5,42.1],[-9.5,37.0]]]}}]}"""   # (a bow tie: invalid)

proc infoLine(iso, name: string, id: int): string =
  var cols = newSeq[string](19)
  cols[0] = iso
  cols[4] = name
  cols[16] = $id
  cols.join("\t")

let countryInfo = "# comment\n" & infoLine("CL", "Chile", 3895114) & "\n" & infoLine("AR", "Argentina", 3865483) &
  "\n" & infoLine("PT", "Portugal", 2510769) & "\n" & infoLine("CW", "Curacao", 7626836) & "\n"

type Net = ref object
  gets: seq[string]
  broken: bool

proc envOf(net: Net): Env =
  let outlinesUrl = urlFor(geonamesOutlines)
  let infoUrl = urlFor(geonamesCountryInfo)
  result.fetcher.head = proc(url: string): Option[int64] {.closure, raises: [].} = none(int64)
  result.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
    net.gets.add url
    if net.broken: return FetchResult(ok: false, message: "cannot reach download.geonames.org")
    if url == outlinesUrl:
      try:
        return FetchResult(ok: true, status: 200,
                           body: makeZip([("shapes_simplified_low.json", outlines)]))
      except CatchableError:
        return FetchResult(ok: false, message: "cannot make the zip")
    if url == infoUrl:
      return FetchResult(ok: true, status: 200, body: countryInfo)
    FetchResult(ok: false, status: 404, message: "the server said 404")
  result.freeBytes = proc(dir: string): Option[int64] {.closure, raises: [].} = none(int64)

proc fresh(name: string): tuple[st: Store, dir: string] =
  let top = getTempDir() / "nch-test-names" / name
  removeDir(top)
  (openStore(top / "x.db", allFragments), top / "data")

suite "names: which country":
  test "the outlines are fetched the first time, kept in the table, and used":
    let net = Net()
    let (st, dir) = fresh("outlines")
    defer: st.close()
    var events: seq[DownloadEvent]
    let names = newNames(st, dir, envOf(net), proc(ev: DownloadEvent) {.closure, raises: [].} = events.add ev)
    check st.db.getValue(sql"select count(*) from country") == "0"
    check countryAt(names, -70.65, -33.45) == some("CL")             # Santiago
    check net.gets.len == 2 and events.len == 4                       # the outlines, and the list: each said, then done
    check st.db.getValue(sql"select count(*) from country") == "4"
    check st.db.getValue(sql"select name from country where iso = 'AR'") == "Argentina"
    check st.db.getValue(sql"select count(*) from country where geom is null") == "1"       # Curacao: no outline
    check countryAt(names, -68.83, -32.89) == some("AR")              # Mendoza
    check countryAt(names, -69.6, -40.0) == some("CL")                # either side of the border (at -69.5)
    check countryAt(names, -69.4, -40.0) == some("AR")
    check net.gets.len == 2                                           # no more fetching

  test "a position inside no outline takes the country of the nearest place carried in the program":
    let net = Net()
    let (st, dir) = fresh("fallback")
    defer: st.close()
    let names = newNames(st, dir, envOf(net), silent())
    check countryAt(names, -9.14, 38.72) == some("PT")               # Lisbon
    check countryAt(names, -71.9, -33.1) == some("CL")               # in the sea off Valparaiso
    check countryAt(names, -120.0, -30.0).isNone                      # the middle of the Pacific: nowhere
    check countryAt(names, -70.65, -33.45) == some("CL")

  test "without the network it is an error that says why, and nothing is marked as done":
    let net = Net(broken: true)
    let (st, dir) = fresh("offline")
    defer: st.close()
    var events: seq[DownloadEvent]
    let names = newNames(st, dir, envOf(net), proc(ev: DownloadEvent) {.closure, raises: [].} = events.add ev)
    try:
      discard countryAt(names, -70.65, -33.45)
      check false
    except DownloadError as e:
      check "cannot get the countries" in e.msg and "cannot reach" in e.msg
    check st.db.getValue(sql"select count(*) from country") == "0"
    check events.len >= 2 and events[0].kind == deStarting and events[1].kind == deFailed and "cannot reach" in events[1].message
    # ... and when the network is back, the next call fills the table
    net.broken = false
    check countryAt(names, -68.83, -32.89) == some("AR")
    check st.db.getValue(sql"select count(*) from country") == "4"

  test "files that cannot be read are said, deleted, and fetched again next time":
    let net = Net()
    let (st, dir) = fresh("unreadable")
    defer: st.close()
    createDir(dir / "geonames")
    writeFile(dir / "geonames" / "shapes_simplified_low.json.zip",
              makeZip([("shapes_simplified_low.json", "not json")]))
    var events: seq[DownloadEvent]
    let names = newNames(st, dir, envOf(net), proc(ev: DownloadEvent) {.closure, raises: [].} = events.add ev)
    expect DownloadError:
      ensureCountries(names)
    check events.len >= 1 and events[^1].kind == deFailed and "cannot be read" in events[^1].message
    check not fileExists(dir / "geonames" / "shapes_simplified_low.json.zip")
    ensureCountries(names)                                            # the good file is fetched
