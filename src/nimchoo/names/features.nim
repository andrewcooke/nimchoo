## The names of one country: its GeoNames file is fetched (download/) and the terrain features and populated
## places in it are read into the `feature` table, once; `name_source` records that it was done.
##
## A GeoNames line is 19 tab-separated columns; we read the id (0), name (1), latitude (4), longitude (5), feature
## class (6), feature code (7) and population (14).  Kept: class P, populated places, all of them (villages and
## neighbourhoods too); and from the classes T (terrain), L (areas), H (water) and S (spots) only the codes listed below, the
## points a climb is named by (peaks, passes ...) and the places with an extent that an activity can be named for
## (towns, valleys, ranges, parks, lakes ...).  Springs, bridges, roads, buildings and the rest are not wanted.

import std/[options, os, strutils, times]
import db_connector/db_sqlite
import ../db/[statement, store]
import ../download/[fetch, sources]
import ../errors
import ../zipbytes
import ./countries

{.push raises: [].}

const
  terrainCodes* = ["MT", "MTS", "PK", "PKS", "PASS", "SDL", "HLL", "HLLS", "RDGE", "SPUR", "VAL", "VALS", "CNYN",
                   "PLN", "PLAT", "VLC", "DSRT", "GRGE", "PEN", "ISL", "ISLS"]
    ## class T: mountain(s), peak(s), pass, saddle, hill(s), ridge, spur, valley(s), canyon, plain, plateau, volcano,
    ## desert, gorge, peninsula, island(s)
  areaCodes* = ["PRK", "RES", "RESA", "RESF", "RESH", "RESN", "RESV", "RESW", "AREA", "RGN"]
    ## class L: park, reserves (of several kinds), area, region
  waterCodes* = ["LK", "LKS", "RSV", "BAY", "GULF", "FJD", "GLCR"]
    ## class H: lake(s), reservoir, bay, gulf, fjord, glacier
  spotCodes* = ["FRM", "FRMS", "BDG"]
    ## class S: farm(s), bridge: small named places that riders turn round at (El Toyo is a farm)
  maxCountryFile = 1024 * 1024 * 1024    ## the United States file unzips to about 300 MB

type Feature* = object
  id*: int64
  name*: string
  lon*, lat*: float
  cls*, code*: string
  population*: int

func parseFeature*(line: string): Option[Feature] =
  ## The feature on a line of a GeoNames file, if it is of a kind we keep (and the line is whole).
  # find the tabs up to the 16th column without making a string for each column
  var starts: array[16, int]
  var n = 1
  var i = 0
  while i < line.len and n < 16:
    if line[i] == '\t':
      starts[n] = i + 1
      inc n
    inc i
  if n < 15: return
  proc column(c: int): string =
    let a = starts[c]
    var b = if c + 1 < n: starts[c + 1] - 1 else: line.len
    if b < a: b = a
    line[a ..< b]
  let cls = column(6)
  if cls notin ["T", "P", "L", "H", "S"]: return
  let code = column(7)
  if cls == "T" and code notin terrainCodes: return
  if cls == "L" and code notin areaCodes: return
  if cls == "H" and code notin waterCodes: return
  if cls == "S" and code notin spotCodes: return
  try:
    let name = column(1)
    if name.len == 0: return
    let pop = column(14)
    result = some(Feature(id: parseBiggestInt(column(0)), name: name, lat: parseFloat(column(4)),
                          lon: parseFloat(column(5)), cls: cls, code: code,
                          population: if pop.len > 0: parseInt(pop) else: 0))
  except ValueError:
    discard

proc readNames(n: Names, iso: string, text: string): int {.raises: [StoreError].} =
  ## Put the features of the text into the table (in the caller's transaction); returns how many.
  let insert = prepareStmt(n.st.db, "insert or replace into feature(id, country, name, class, code, " &
    "population, geom) values (?, ?, ?, ?, ?, ?, MakePoint(?, ?, 4326))")
  var at = 0
  while at < text.len:
    var stop = text.find('\n', at)
    if stop < 0: stop = text.len
    let f = parseFeature(text[at ..< stop])
    at = stop + 1
    if f.isNone: continue
    insert.bindInt(1, f.get.id)
    insert.bindText(2, iso)
    insert.bindText(3, f.get.name)
    insert.bindText(4, f.get.cls)
    insert.bindText(5, f.get.code)
    insert.bindInt(6, int64(f.get.population))
    insert.bindReal(7, f.get.lon)
    insert.bindReal(8, f.get.lat)
    insert.run()
    inc result

proc ensureNames*(n: Names, iso: string) {.raises: [StoreError, DownloadError].} =
  ## The names of the country are in the table: if not, fetch its file and read it in.  A DownloadError (and the
  ## reason told to the sink) if that cannot be done.
  guard:
    if n.st.db.getValue(sql"select count(*) from name_source where country = ?", iso) != "0": return
  n.ensureCountries()
  guard:
    if n.st.db.getValue(sql"select count(*) from country where iso = ?", iso) == "0":
      raise n.couldNot("the names of " & iso & " (no such country)")
  let path = fetchSource(n.env, n.sink, n.dataDir, geonamesCountry, iso)
  if path.isNone: raise n.couldNot("the names of " & iso)
  var text: string
  try:
    text = readEntry(readFile(path.get), entryFor(geonamesCountry, iso), maxCountryFile)
  except ZipError, IOError, OSError:
    n.sink(DownloadEvent(kind: deFailed, source: geonamesCountry.name, url: urlFor(geonamesCountry, iso),
                         message: "the file cannot be read (" & getCurrentExceptionMsg() & ")"))
    try: removeFile(path.get)
    except OSError: discard
    raise n.couldNot("the names of " & iso)
  n.st.begin()
  var done = false
  try:
    guard: n.st.db.exec(sql"delete from feature where country = ?", iso)
    let count = readNames(n, iso, text)
    guard: n.st.db.exec(sql"insert or replace into name_source(country, loaded_at, features) values (?, ?, ?)",
                        iso, getTime().toUnix, count)
    n.st.commit()
    done = true
  finally:
    if not done: n.st.rollback()

type NameCounts* = object
  features*, countries*: int

proc countNames*(st: Store): NameCounts {.raises: [StoreError].} =
  ## How many features, and of how many countries, are in the table.
  guard:
    try:
      result.features = parseInt(st.db.getValue(sql"select count(*) from feature"))
      result.countries = parseInt(st.db.getValue(sql"select count(*) from name_source"))
    except ValueError:
      raiseStore("a bad count")

func describe*(c: NameCounts): string =
  ## "16,223 features of 1 country".
  $c.features & (if c.features == 1: " feature" else: " features") & " of " & $c.countries &
    (if c.countries == 1: " country" else: " countries")

proc clearNames*(st: Store) {.raises: [StoreError].} =
  ## Empty the tables of names and countries (the downloaded files stay, so they are read in again when wanted;
  ## the names already given to sectors stay: they are copies).
  st.begin()
  var done = false
  try:
    guard:
      st.db.exec(sql"delete from name_source")
      st.db.exec(sql"delete from feature")
      st.db.exec(sql"delete from country")
    st.commit()
    done = true
  finally:
    if not done: st.rollback()

