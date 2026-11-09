import nimchoo/packages/db/statement
import std/[math, options, os, sequtils, strutils, unittest]
import ../support/shims
import nimchoo/packages/db/store
import nimchoo/packages/download/fetch
import nimchoo/packages/download/sources
import nimchoo/core/errors
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/names/countries
import ../support/[shapefile, zips]

let shapes = [
  CountryShape(
    iso: "CL", isoEh: "CL", name: "Chile", rects: @[(-76.0, -56.0, -69.5, -17.0)]
  ),
  CountryShape(
    iso: "AR", isoEh: "AR", name: "Argentina", rects: @[(-69.5, -56.0, -53.0, -21.0)]
  ),
  CountryShape(
    iso: "PT",
    isoEh: "PT",
    name: "Portugal",
    rects: @[(-9.5, 37.0, -6.2, 42.1), (-17.3, 32.6, -16.6, 33.1)],
  ),
  CountryShape(
    iso: "-99", isoEh: "FR", name: "France", rects: @[(-5.0, 43.0, 8.0, 51.0)]
  ),
  CountryShape(
    iso: "PT",
    isoEh: "PT",
    name: "Portugal (Azores)",
    rects: @[(-28.0, 38.4, -27.0, 39.0)],
  ), # (a second shape with the same code: a country in two parts)
] # (the code is in the second field)

proc infoLine(iso, name: string, id: int): string =
  var cols = newSeq[string](19)
  cols[0] = iso
  cols[4] = name
  cols[16] = $id
  cols.join("\t")

let countryInfo =
  "# comment\n" & infoLine("CL", "Chile", 3895114) & "\n" &
  infoLine("AR", "Argentina", 3865483) & "\n" & infoLine("PT", "Portugal", 2510769) &
  "\n" & infoLine("CW", "Curacao", 7626836) & "\n" & infoLine("FR", "France", 3017382) &
  "\n"

type Net = ref object
  gets: seq[string]
  broken: bool

proc envOf(net: Net): Env =
  let outlinesUrl = urlFor(naturalEarthCountries)
  let infoUrl = urlFor(geonamesCountryInfo)
  result.fetcher.head = proc(url: string): Option[int64] {.closure, raises: [].} =
    none(int64)
  result.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
    net.gets.add url
    if net.broken:
      return FetchResult(ok: false, message: "cannot reach download.geonames.org")
    if url == outlinesUrl:
      try:
        return FetchResult(ok: true, status: 200, body: naturalEarthZip(shapes))
      except CatchableError:
        return FetchResult(ok: false, message: "cannot make the zip")
    if url == infoUrl:
      return FetchResult(ok: true, status: 200, body: countryInfo)
    FetchResult(ok: false, status: 404, message: "the server said 404")
  result.freeBytes = proc(dir: string): Option[int64] {.closure, raises: [].} =
    none(int64)

proc fresh(name: string): tuple[st: Store, dir: string] =
  let top = getTempDir() / "nch-test-names" / name
  removeDir(top)
  (openStore(top / "x.db", allFragments, access = allAccess), top / "data")

func cellOf(lon, lat: float): (int, int) =
  (int(floor(lon * cellsPerDegree.float)), int(floor(lat * cellsPerDegree.float)))

proc countries(n: Names, lon, lat: float): seq[string] =
  let (cx, cy) = cellOf(lon, lat)
  countriesOfCell(n, cx, cy)

suite "names: which countries":
  test "the outlines are fetched the first time, kept in the table, and used":
    let net = Net()
    let (st, dir) = fresh("outlines")
    defer:
      st.close()
    var events: seq[DownloadEvent]
    let names = newNames(
      st,
      dir,
      envOf(net),
      proc(ev: DownloadEvent) {.closure, raises: [].} =
        events.add ev
      ,
    )
    check st.db.scalar(int, "select count(*) from country") == 0
    check names.countries(-70.65, -33.45) == @["CL"] # Santiago
    check net.gets.len == 2 and
      events.filterIt(it.kind notin {deReading, deFinished}).len == 4
      # the outlines, and the list: each said, then done
    check st.db.scalar(int, "select count(*) from country") == 5
    check st.db.scalar(string, "select name from country where iso = 'AR'") ==
      "Argentina"
    check st.db.scalar(int, "select count(*) from country where geom is null") == 1
      # Curacao: no outline
    check st.db.scalar(
      int, "select count(*) from country where iso = 'FR' and geom is not null"
    ) == 1 # (found by the second code)
    check names.countries(-68.83, -32.89) == @["AR"] # Mendoza
    check names.countries(-9.14, 38.72) == @["PT"] # Lisbon
    check names.countries(2.35, 48.85) == @["FR"] # Paris
    check net.gets.len == 2 # no more fetching
    check not fileExists(dir / "naturalearth" / "work" / "ne_50m_admin_0_countries.shp")
      # (the unpacked files are removed)

  test "a country in several shapes has all of them":
    let (st, dir) = fresh("parts")
    defer:
      st.close()
    let names = newNames(st, dir, envOf(Net()), silent())
    check names.countries(-9.14, 38.72) == @["PT"] # the first shape
    check names.countries(-27.5, 38.7) == @["PT"] # the second

  test "a cell on a border has both countries; a cell of open sea has none; the answers are kept":
    let net = Net()
    let (st, dir) = fresh("cells")
    defer:
      st.close()
    let names = newNames(st, dir, envOf(net), silent())
    check names.countries(-69.6, -40.0) ==
      @["AR", "CL"] # the cell holding the border at -69.5
    check names.countries(-69.9, -40.0) == @["CL"] # a cell away from it
    check names.countries(-69.1, -40.0) == @["AR"]
    check names.countries(-120.0, -30.0).len == 0 # the Pacific
    check st.db.scalar(int, "select count(*) from country_cell_done") == 4
    check st.db.scalar(int, "select count(*) from country_cell") == 4
      # (two for the border cell, none for the sea)
    check names.countries(-120.0, -30.0).len == 0 and
      names.countries(-69.6, -40.0) == @["AR", "CL"]
    check st.db.scalar(int, "select count(*) from country_cell_done") == 4
  test "a database with the old outlines forgotten (geom null) reads the new ones and keeps what hangs on a country":
    let net = Net()
    let (st, dir) = fresh("migrate")
    defer:
      st.close()
    st.db.execute(
      "insert into country(iso, name, geoname_id) values ('CL', 'Chile', 3895114)"
    )
    st.db.execute(
      "insert into coverage(country, cell_lon, cell_lat, loaded_at, features) values ('CL', -71, -34, 1, 1)"
    )
    st.db.execute(
      "insert into feature(id, country, name, class, code, geom) values (1, 'CL', 'Cerro', 'T', 'HLL', MakePoint(-70.6, -33.4, 4326))"
    )
    let names = newNames(st, dir, envOf(net), silent())
    check names.countries(-70.65, -33.45) == @["CL"]
    check st.db.scalar(int, "select count(*) from country") == 5
    check st.db.scalar(int, "select count(*) from coverage") == 1 and
      st.db.scalar(int, "select count(*) from feature") == 1
  test "cells wrap round the antimeridian":
    check wrapCell(-720) == -720 and wrapCell(719) == 719
    check wrapCell(720) == -720 and wrapCell(-721) == 719 and wrapCell(1440) == 0

  test "without the network it is an error that says why, and nothing is marked as done":
    let net = Net(broken: true)
    let (st, dir) = fresh("offline")
    defer:
      st.close()
    var events: seq[DownloadEvent]
    let names = newNames(
      st,
      dir,
      envOf(net),
      proc(ev: DownloadEvent) {.closure, raises: [].} =
        events.add ev
      ,
    )
    try:
      discard names.countries(-70.65, -33.45)
      check false
    except DownloadError as e:
      check "cannot get the countries" in e.msg and "cannot reach" in e.msg
    check st.db.scalar(int, "select count(*) from country") == 0
    check events.len >= 2 and events[0].kind == deStarting and events[1].kind == deFailed and
      "cannot reach" in events[1].message
    # ... and when the network is back, the next call fills the table
    net.broken = false
    check names.countries(-68.83, -32.89) == @["AR"]
    check st.db.scalar(int, "select count(*) from country") == 5

  test "files that cannot be read are said, deleted, and fetched again next time":
    let net = Net()
    let (st, dir) = fresh("unreadable")
    defer:
      st.close()
    createDir(dir / "naturalearth")
    writeFile(
      dir / "naturalearth" / "ne_50m_admin_0_countries.zip",
      makeZip([("ne_50m_admin_0_countries.shp", "not a shapefile")]),
    )
    var events: seq[DownloadEvent]
    let names = newNames(
      st,
      dir,
      envOf(net),
      proc(ev: DownloadEvent) {.closure, raises: [].} =
        events.add ev
      ,
    )
    expect DownloadError:
      ensureCountries(names)
    let said = events.filterIt(it.kind notin {deReading, deFinished})
    check said.len >= 1 and said[^1].kind == deFailed and
      "cannot be read" in said[^1].message
    check not fileExists(dir / "naturalearth" / "ne_50m_admin_0_countries.zip")
    ensureCountries(names) # the good file is fetched
    check st.db.scalar(int, "select count(*) from country") == 5
