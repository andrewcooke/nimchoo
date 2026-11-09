## Which countries are round a place.  The outlines (Natural Earth's) are fetched the first time they are wanted
## (download/), read into the `country` table by SpatiaLite, and kept; after that this works offline.  The question
## is asked of a cell of the map (a quarter of a degree square): which countries' outlines touch it?  The answer is
## worked out once by SpatiaLite and kept in `country_cell`, so asking again is a lookup.  A cell of open sea has none.
##
## `Names` is the handle the module's functions share: the store, the directory the downloads go in,
## the network and disk (a made-up one in tests) and where events are told.

import std/[math, options, os, strutils]
import ../db/[statement, store]
import ../download/[fetch, sources]
import ../core/errors
import ../packages/util/zip/zipbytes
import ./countryinfo

{.push raises: [].}

type Names* = object
  st*: Store
  dataDir*: string
  env*: Env
  sink*: Sink
  offline*: bool ## `--offline`: no names are had; every question is answered "nothing"
  lastFailure: ref string
    ## what the last failed download said (for the error that is raised)

func newNames*(st: Store, dataDir: string, env: Env, sink: Sink): Names =
  ## The handle.  A failed download is told to `sink` and also kept, to be the message of the DownloadError.
  let last = new(string)
  let told = proc(ev: DownloadEvent) {.closure, raises: [].} =
    if ev.kind == deFailed:
      last[] = describe(ev)
    sink(ev)
  Names(st: st, dataDir: dataDir, env: env, sink: told, lastFailure: last)

proc couldNot*(n: Names, what: string): ref DownloadError =
  ## The error for something that could not be had: what was wanted, and why (the last failure told).
  (ref DownloadError)(
    msg:
      "cannot get " & what &
      (if n.lastFailure[].len > 0: ": " & n.lastFailure[] else: "")
  )

proc refuse(n: Names, src: Source, why: string, path: string) =
  ## A file that came but cannot be read: say so, and delete it so that it is fetched again.
  n.sink(
    DownloadEvent(kind: deFailed, source: src.name, url: urlFor(src), message: why)
  )
  try:
    removeFile(path)
  except OSError:
    discard

const
  cellsPerDegree* = 4 ## a cell is a quarter of a degree square
  neStem = "ne_50m_admin_0_countries"

proc loadOutlines(
    n: Names, zip: string
) {.raises: [StoreError, ZipError, IOError, OSError].} =
  ## Put the shapefile of the zip beside the data (SpatiaLite reads a shapefile from files), make the countries from
  ## it and the list, and remove the files again.
  let work = n.dataDir / "naturalearth" / "work"
  createDir(work)
  defer:
    try:
      removeDir(work)
    except OSError:
      discard
  for ext in [".shp", ".shx", ".dbf"]:
    writeFile(
      work / (neStem & ext),
      readEntry(zip, neStem & ext, 64 * 1024 * 1024, n.env.inflater),
    )
  # (a virtual table's arguments are part of the statement and cannot be bound)
  n.st.db.execute(
    "create virtual table temp.ne_shapes using VirtualShape('" &
      (work / neStem).replace("'", "''") & "', 'UTF-8', 4326)"
  )

proc dropOutlines(n: Names) =
  try:
    n.st.db.execute("drop table if exists temp.ne_shapes")
  except StoreError:
    discard

proc ensureCountries*(n: Names) {.raises: [StoreError, DownloadError].} =
  ## The `country` table is filled: if it is not, fetch the outlines and the list of countries and fill it.
  ## A DownloadError (and the reason told to the sink) if that cannot be done.
  if n.st.db.scalar(int, "select count(*) from country where geom is not null") != 0:
    return
  let outlinesPath = fetchSource(n.env, n.sink, n.dataDir, naturalEarthCountries)
  let infoPath = fetchSource(n.env, n.sink, n.dataDir, geonamesCountryInfo)
  if outlinesPath.isNone or infoPath.isNone:
    raise n.couldNot("the countries")
  n.sink(
    DownloadEvent(
      kind: deReading,
      source: geonamesCountryInfo.name,
      url: urlFor(geonamesCountryInfo),
      label: labelFor(geonamesCountryInfo),
    )
  )
  defer:
    n.sink(DownloadEvent(kind: deFinished, source: geonamesCountryInfo.name))
  var countries: seq[CountryInfo]
  try:
    countries = parseCountryInfo(readFile(infoPath.get))
  except IOError, OSError:
    n.refuse(
      geonamesCountryInfo,
      "the list of countries cannot be read (" & getCurrentExceptionMsg() & ")",
      infoPath.get,
    )
    raise n.couldNot("the countries")
  if countries.len == 0:
    n.refuse(geonamesCountryInfo, "no countries in the list", infoPath.get)
    raise n.couldNot("the countries")
  var loaded = false
  try:
    n.loadOutlines(readFile(outlinesPath.get))
    loaded = true
  except ZipError, IOError, OSError:
    n.refuse(
      naturalEarthCountries,
      "the outlines cannot be read (" & getCurrentExceptionMsg() & ")",
      outlinesPath.get,
    )
  except StoreError:
    n.refuse(
      naturalEarthCountries,
      "the outlines cannot be read (" & getCurrentExceptionMsg() & ")",
      outlinesPath.get,
    )
  if not loaded:
    raise n.couldNot("the countries")
  defer:
    n.dropOutlines()
  n.st.begin()
  var done = false
  try:
    # a country is matched by its ISO code: Natural Earth's main field is -99 for a few (France, Norway), the real
    # one is in the second field
    # (all the shapes with the code, joined: a country in several parts has a row for each)
    # (an upsert and not a replace: a replace would delete the row, and with it the places and cells read for the country)
    let insert = prepareStmt(
      n.st.db,
      "insert into country(iso, name, geoname_id, geom) " &
        "values (?, ?, ?, (select CastToMultiPolygon(GUnion(Geometry)) from temp.ne_shapes " &
        "where coalesce(nullif(ISO_A2_EH, '-99'), nullif(ISO_A2, '-99')) = ?)) " &
        "on conflict(iso) do update set name = excluded.name, geoname_id = excluded.geoname_id, geom = excluded.geom",
    )
    for c in countries:
      insert.bindText(1, c.iso)
      insert.bindText(2, c.name)
      insert.bindInt(3, c.geonameId)
      insert.bindText(4, c.iso)
      insert.run()
    n.st.commit()
    done = true
  finally:
    if not done:
      n.st.rollback()

func wrapCell*(cx: int): int =
  ## A cell's longitude put back into -180 .. 180 degrees (in cells).
  let width = 360 * cellsPerDegree
  ((cx + width div 2) mod width + width) mod width - width div 2

const countriesInCellSql* =
  "select iso from country where geom is not null and " &
  inBox("rowid", "country", "geom", cornerMarks) &
  " and Intersects(geom, BuildMbr(:west, :south, :east, :north, 4326)) = 1 order by iso"
  ## (the index finds the outlines whose boxes meet the cell; the exact test is then made on those only)

proc countriesOfCell*(
    n: Names, cx, cy: int
): seq[string] {.raises: [StoreError, DownloadError].} =
  ## The countries whose outlines touch the cell (cx, cy in quarter degrees from the south-west corner): looked up in
  ## `country_cell`, or worked out by SpatiaLite the first time and kept.  None for open sea.
  n.ensureCountries()
  let x0 = cx.float / cellsPerDegree.float
  let y0 = cy.float / cellsPerDegree.float
  let x1 = x0 + 1.0 / cellsPerDegree.float
  let y1 = y0 + 1.0 / cellsPerDegree.float
  if n.st.db.scalar(
    int,
    "select count(*) from country_cell_done where cell_lon = :cellLon and cell_lat = :cellLat",
    cellLon = cx,
    cellLat = cy,
  ) == 0:
    for iso in n.st.db.query(
      string, countriesInCellSql, west = x0, south = y0, east = x1, north = y1
    ):
      n.st.db.execute(
        "insert or ignore into country_cell(cell_lon, cell_lat, country) values (:cellLon, :cellLat, :country)",
        cellLon = cx,
        cellLat = cy,
        country = iso,
      )
    n.st.db.execute(
      "insert or ignore into country_cell_done(cell_lon, cell_lat) values (:cellLon, :cellLat)",
      cellLon = cx,
      cellLat = cy,
    )
  result = n.st.db.query(
    string,
    "select country from country_cell where cell_lon = :cellLon and cell_lat = :cellLat order by country",
    cellLon = cx,
    cellLat = cy,
  )
