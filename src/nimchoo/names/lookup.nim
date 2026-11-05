## The part of naming that does not depend on what is being named: where a position is (its country), that
## the names of that country are in the table (fetched the first time), and the features near a route.
## What a name should be for a climb, an activity, ... is a rule of its own (climb.nim, and the others to come),
## made from these.

import std/[math, options, strutils]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ./[countries, features]

{.push raises: [].}

const defaultMarginM* = 6_000.0      ## metres round the route, for the features looked at

type
  Readiness* = enum
    rdReady        ## the names round the place are in the table
    rdNothing      ## there is nothing to be had for this place (the sea, a country the list lacks, `--offline`)

  Prepared* = object
    status*: Readiness

  Found* = object
    ## A feature of the table, as it is: where it is and what it is called.
    name*, code*: string        ## the GeoNames feature code ("PASS", "HLL", "PPL", ...)
    isPlace*: bool              ## a populated place (class P)
    lon*, lat*: float

func boxAround*(lons, lats: openArray[float], marginM: float): Box =
  ## The box round the positions, widened by the margin: the margin is metres, so a degree of longitude counts for less
  ## towards the poles (the box then reaches further in degrees of longitude, up to the whole circle).
  var b = (lon0: Inf, lat0: Inf, lon1: -Inf, lat1: -Inf)
  for i in 0 ..< lons.len:
    b = (min(b.lon0, lons[i]), min(b.lat0, lats[i]), max(b.lon1, lons[i]), max(b.lat1, lats[i]))
  let dLat = marginM / 111_000.0
  let worst = max(abs(b.lat0), abs(b.lat1)) + dLat                  # the latitude where a degree of longitude is shortest
  let dLon = if worst >= 89.0: 360.0 else: dLat / max(cos(degToRad(worst)), 0.02)
  (lon0: b.lon0 - dLon, lat0: max(-90.0, b.lat0 - dLat), lon1: b.lon1 + dLon, lat1: min(90.0, b.lat1 + dLat))

proc countriesIn(n: Names, box: Box): seq[string] {.raises: [StoreError, DownloadError].} =
  ## The countries the box touches: the country of its middle, corners and edge middles (so a box over a border
  ## takes both).  Positions are put back into -180 .. 180 first.
  let midLon = (box.lon0 + box.lon1) / 2
  let midLat = (box.lat0 + box.lat1) / 2
  for (lon, lat) in [(midLon, midLat), (box.lon0, box.lat0), (box.lon0, box.lat1), (box.lon1, box.lat0),
                     (box.lon1, box.lat1), (box.lon0, midLat), (box.lon1, midLat), (midLon, box.lat0), (midLon, box.lat1)]:
    var l = lon
    while l >= 180.0: l -= 360.0
    while l < -180.0: l += 360.0
    let iso = n.countryAt(l, max(-90.0, min(90.0, lat)))
    if iso.isSome and iso.get notin result: result.add iso.get

proc prepare*(n: Names, lons, lats: openArray[float], marginM = defaultMarginM): Prepared
    {.raises: [StoreError, DownloadError].} =
  ## Make the names round the positions available (the cells they touch, of the countries they touch), fetching what is
  ## missing.  `--offline`: nothing is had.
  if n.offline or lons.len == 0: return Prepared(status: rdNothing)
  n.ensureCountries()
  let box = boxAround(lons, lats, marginM)
  let isos = n.countriesIn(box)
  if isos.len == 0: return Prepared(status: rdNothing)
  for iso in isos:
    var known = false
    guard:
      known = n.st.db.getValue(sql"select count(*) from country where iso = ?", iso) != "0"
    if known: n.ensureCells(iso, box)         # (a country the list of countries lacks has nothing)
  Prepared(status: rdReady)

proc featuresNear*(n: Names, lons, lats: openArray[float], marginM = defaultMarginM): seq[Found]
    {.raises: [StoreError].} =
  ## The features in the box round the positions, widened by the margin (whatever country they are in).
  if lons.len == 0: return
  let box = boxAround(lons, lats, marginM)
  guard:
    for r in n.st.db.fastRows(sql("select name, code, class = 'P', ST_X(geom), ST_Y(geom) from feature " &
        "where id in (select ROWID from SpatialIndex where f_table_name = 'feature' and " &
        "f_geometry_column = 'geom' and search_frame = BuildMbr(" &
        formatFloat(box.lon0, ffDecimal, 6) & ", " & formatFloat(box.lat0, ffDecimal, 6) & ", " &
        formatFloat(box.lon1, ffDecimal, 6) & ", " & formatFloat(box.lat1, ffDecimal, 6) & "))")):
      try:
        result.add Found(name: r[0], code: r[1], isPlace: r[2] == "1", lon: parseFloat(r[3]), lat: parseFloat(r[4]))
      except ValueError:
        discard
