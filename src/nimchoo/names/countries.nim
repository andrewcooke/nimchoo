## Which country a position is in.  The outlines are fetched the first time they are wanted
## (download/), read into the `country` table, and kept; after that this works offline.  A position
## inside no outline (the sea, a small island the simplified outlines leave out) is in no country.
##
## `Names` is the handle the module's functions share: the store, the directory the downloads go in,
## the network and disk (a made-up one in tests) and where events are told.

import std/[options, os, strutils, tables]
import db_connector/db_sqlite
import ../db/[statement, store]
import ../download/[fetch, sources]
import ../errors
import ../zipbytes
import ./outlines

{.push raises: [].}


type Names* = object
  st*: Store
  dataDir*: string
  env*: Env
  sink*: Sink
  offline*: bool                       ## `--offline`: no names are had; every question is answered "nothing"
  shapes: ref Table[string, Shape]     ## the outlines read from the table, by country: kept
  lastFailure: ref string              ## what the last failed download said (for the error that is raised)

func newNames*(st: Store, dataDir: string, env: Env, sink: Sink): Names =
  ## The handle.  A failed download is told to `sink` and also kept, to be the message of the DownloadError.
  let last = new(string)
  let told = proc(ev: DownloadEvent) {.closure, raises: [].} =
    if ev.kind == deFailed: last[] = describe(ev)
    sink(ev)
  Names(st: st, dataDir: dataDir, env: env, sink: told, shapes: new(Table[string, Shape]), lastFailure: last)

proc couldNot*(n: Names, what: string): ref DownloadError =
  ## The error for something that could not be had: what was wanted, and why (the last failure told).
  (ref DownloadError)(msg: "cannot get " & what & (if n.lastFailure[].len > 0: ": " & n.lastFailure[] else: ""))

proc refuse(n: Names, src: Source, why: string, path: string) =
  ## A file that came but cannot be read: say so, and delete it so that it is fetched again.
  n.sink(DownloadEvent(kind: deFailed, source: src.name, url: urlFor(src), message: why))
  try: removeFile(path)
  except OSError: discard

proc ensureCountries*(n: Names) {.raises: [StoreError, DownloadError].} =
  ## The `country` table is filled: if it is not, fetch the outlines and the list of countries and fill it.
  ## A DownloadError (and the reason told to the sink) if that cannot be done.
  guard:
    if n.st.db.getValue(sql"select count(*) from country") != "0": return
  let outlinesPath = fetchSource(n.env, n.sink, n.dataDir, geonamesOutlines)
  let infoPath = fetchSource(n.env, n.sink, n.dataDir, geonamesCountryInfo)
  if outlinesPath.isNone or infoPath.isNone: raise n.couldNot("the countries")
  n.sink(DownloadEvent(kind: deReading, source: geonamesCountryInfo.name, url: urlFor(geonamesCountryInfo),
                       label: labelFor(geonamesCountryInfo)))
  defer: n.sink(DownloadEvent(kind: deFinished, source: geonamesCountryInfo.name))
  var countries: seq[CountryInfo]
  var shapes: Table[int64, string]
  try:
    countries = parseCountryInfo(readFile(infoPath.get))
    for o in parseOutlines(readEntry(readFile(outlinesPath.get), geonamesOutlines.zipEntry)):
      shapes[o.geonameId] = o.wkt
  except ValueError, ZipError, IOError, OSError:
    n.refuse(geonamesOutlines, "the outlines cannot be read (" & getCurrentExceptionMsg() & ")", outlinesPath.get)
    raise n.couldNot("the countries")
  if countries.len == 0:
    n.refuse(geonamesCountryInfo, "no countries in the list", infoPath.get)
    raise n.couldNot("the countries")
  n.st.begin()
  var done = false
  try:
    let insert = prepareStmt(n.st.db, "insert or replace into country(iso, name, geoname_id, geom) " &
      "values (?, ?, ?, GeomFromText(nullif(?, ''), 4326))")
    for c in countries:
      insert.bindText(1, c.iso)
      insert.bindText(2, c.name)
      insert.bindInt(3, c.geonameId)
      insert.bindText(4, shapes.getOrDefault(c.geonameId))
      insert.run()
    n.st.commit()
    done = true
  finally:
    if not done: n.st.rollback()

func degrees(x: float): string = formatFloat(x, ffDecimal, 7)

proc countryAt*(n: Names, lon, lat: float): Option[string] {.raises: [StoreError, DownloadError].} =
  ## The ISO code of the country that holds the position: by the outlines; none for the sea.
  n.ensureCountries()
  # the countries whose boxes hold the point (the index), then the outlines decide: they are tested here
  # and not by SpatiaLite, whose geometry library refuses many of these simplified outlines as invalid
  var candidates: seq[string]
  guard:
    for r in n.st.db.fastRows(sql("select iso from country where rowid in (select ROWID from " &
        "SpatialIndex where f_table_name = 'country' and f_geometry_column = 'geom' and search_frame = " &
        "BuildMbr(" & degrees(lon) & ", " & degrees(lat) & ", " & degrees(lon) & ", " & degrees(lat) &
        ")) order by iso")):
      candidates.add r[0]
  for iso in candidates:
    if iso notin n.shapes[]:
      guard:
        n.shapes[][iso] = parseShape(n.st.db.getValue(sql"select AsText(geom) from country where iso = ?", iso))
    if n.shapes[].getOrDefault(iso).contains(lon, lat): return some(iso)
  none(string)
