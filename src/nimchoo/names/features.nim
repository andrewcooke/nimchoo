## The names of places, read from GeoNames files into the `feature` table by CELLS: a cell is one degree of longitude by
## one of latitude (about 100 km), and a cell is read when a name is wanted in it, from its country's file (fetched by
## download/, kept in the cache), and recorded in `coverage` so that it is read once.  Every feature of the file that falls
## in the cell is kept, of every class and code: what counts as a name for a climb or an activity is decided by the rules
## that use them, so changing the rules never means reading anything again.  A rider in the United States takes the cells
## they ride in, not the whole file.
##
## A GeoNames line is 19 tab-separated columns; we read the id (0), name (1), latitude (4), longitude (5), feature
## class (6), feature code (7) and population (14).

import std/[math, options, os, strutils, tables, times]
import ../db/[statement, store]
import ../download/[fetch, sources]
import ../errors
import ../zipbytes
import ./countries

{.push raises: [].}

const maxCountryFile = 1024 * 1024 * 1024
  ## the United States file unzips to about 300 MB

type
  Feature* = object
    id*: int64
    name*: string
    lon*, lat*: float
    cls*, code*: string
    population*: int

  Box* = tuple[lon0, lat0, lon1, lat1: float] ## degrees

  Cell* = tuple[lon, lat: int] ## the whole degrees at its south-west corner

func parseFeature*(line: string): Option[Feature] =
  ## The feature on a line of a GeoNames file (none if the line is not whole, or has no name).
  # find the tabs up to the 16th column without making a string for each column
  var starts: array[16, int]
  var n = 1
  var i = 0
  while i < line.len and n < 16:
    if line[i] == '\t':
      starts[n] = i + 1
      inc n
    inc i
  if n < 15:
    return
  proc column(c: int): string =
    let a = starts[c]
    var b =
      if c + 1 < n:
        starts[c + 1] - 1
      else:
        line.len
    if b < a:
      b = a
    line[a ..< b]

  try:
    let name = column(1)
    let cls = column(6)
    if name.len == 0 or cls.len == 0:
      return
    let pop = column(14)
    result = some(
      Feature(
        id: parseBiggestInt(column(0)),
        name: name,
        lat: parseFloat(column(4)),
        lon: parseFloat(column(5)),
        cls: cls,
        code: column(7),
        population:
          if pop.len > 0:
            parseInt(pop)
          else:
            0,
      )
    )
  except ValueError:
    discard

func wrapLon(lon: int): int =
  ## A whole-degree longitude brought into -180 .. 179 (180 is -180; 185 is -175; -181 is 179).
  ((lon + 180) mod 360 + 360) mod 360 - 180

func cellOf*(lon, lat: float): Cell =
  ## The cell of a position.  `floor`, not truncation, so that -70.12 is in -71 and -0.5 in -1; longitude wraps at the date
  ## line (180 is in cell -180) and latitude 90 (the pole itself) is in the top row, 89.
  (wrapLon(int(floor(lon))), max(-90, min(89, int(floor(lat)))))

func cellsOf*(box: Box): seq[Cell] =
  ## The cells the box touches (a box that crosses the date line has longitudes past 180 or below -180: the cells wrap).
  for lon in int(floor(box.lon0)) .. int(floor(box.lon1)):
    for lat in max(-90, int(floor(box.lat0))) .. min(89, int(floor(box.lat1))):
      let c = (wrapLon(lon), lat)
      if c notin result:
        result.add c

proc missingCells(n: Names, iso: string, box: Box): seq[Cell] {.raises: [StoreError].} =
  ## The cells of the box that are not yet read for the country.
  for c in cellsOf(box):
    if n.st.db.scalar(
      int,
      "select count(*) from coverage where country = :country and cell_lon = :cellLon and cell_lat = :cellLat",
      country = iso,
      cellLon = c.lon,
      cellLat = c.lat,
    ) == 0:
      result.add c

proc readCells(
    n: Names, iso: string, text: string, missing: seq[Cell]
) {.raises: [StoreError].} =
  ## Put the features of the text that fall in the missing cells into the table, and record the cells
  ## (in the caller's transaction).
  let insert = prepareStmt(
    n.st.db,
    "insert or replace into feature(id, country, name, class, code, " &
      "population, geom) values (?, ?, ?, ?, ?, ?, MakePoint(?, ?, 4326))",
  )
  var counts = initTable[Cell, int]()
  for c in missing:
    counts[c] = 0
  var at = 0
  while at < text.len:
    var stop = text.find('\n', at)
    if stop < 0:
      stop = text.len
    let f = parseFeature(text[at ..< stop])
    at = stop + 1
    if f.isNone:
      continue
    let cell = cellOf(f.get.lon, f.get.lat)
    if cell notin counts:
      continue
    insert.bindInt(1, f.get.id)
    insert.bindText(2, iso)
    insert.bindText(3, f.get.name)
    insert.bindText(4, f.get.cls)
    insert.bindText(5, f.get.code)
    insert.bindInt(6, int64(f.get.population))
    insert.bindReal(7, f.get.lon)
    insert.bindReal(8, f.get.lat)
    insert.run()
    counts.mgetOrPut(cell, 0) += 1
  let now = getTime().toUnix
  for c, k in counts:
    n.st.db.execute(
      "insert or replace into coverage(country, cell_lon, cell_lat, loaded_at, features) values (:country, :cellLon, :cellLat, :loadedAt, :features)",
      country = iso,
      cellLon = c.lon,
      cellLat = c.lat,
      loadedAt = now,
      features = k,
    )

proc ensureCells*(
    n: Names, iso: string, box: Box
) {.raises: [StoreError, DownloadError].} =
  ## The features of the country in the box are in the table: the cells not read yet are read from the country's file,
  ## fetched if need be.  A DownloadError (and the reason told to the sink) if that cannot be done.
  let missing = n.missingCells(iso, box)
  if missing.len == 0:
    return
  n.ensureCountries()
  if n.st.db.scalar(int, "select count(*) from country where iso = :iso", iso = iso) == 0:
    raise n.couldNot("the names of " & iso & " (no such country)")
  let path = fetchSource(n.env, n.sink, n.dataDir, geonamesCountry, iso)
  if path.isNone:
    raise n.couldNot("the names of " & iso)
  # reading the file takes a while (unzipping, parsing, storing): the screen says so, and when it is done
  n.sink(
    DownloadEvent(
      kind: deReading,
      source: geonamesCountry.name,
      url: urlFor(geonamesCountry, iso),
      label: labelFor(geonamesCountry, iso),
    )
  )
  defer:
    n.sink(DownloadEvent(kind: deFinished, source: geonamesCountry.name))
  var text: string
  try:
    text = readEntry(
      readFile(path.get), entryFor(geonamesCountry, iso), maxCountryFile, n.env.inflater
    )
  except ZipError, IOError, OSError:
    n.sink(
      DownloadEvent(
        kind: deFailed,
        source: geonamesCountry.name,
        url: urlFor(geonamesCountry, iso),
        message: "the file cannot be read (" & getCurrentExceptionMsg() & ")",
      )
    )
    try:
      removeFile(path.get)
    except OSError:
      discard
    raise n.couldNot("the names of " & iso)
  n.st.begin()
  var done = false
  try:
    n.readCells(iso, text, missing)
    n.st.commit()
    done = true
  finally:
    if not done:
      n.st.rollback()
