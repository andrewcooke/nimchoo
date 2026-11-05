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

const defaultMarginDeg* = 0.06      ## degrees (about 6 km) round the route, for the features looked at

type
  Readiness* = enum
    rdReady        ## the country is known and its names are in the table
    rdNothing      ## there is nothing to be had for this place (the sea, a country the list lacks, `--offline`)

  Prepared* = object
    status*: Readiness
    iso*: string                ## when ready

  Found* = object
    ## A feature of the table, as it is: where it is and what it is called.
    name*, code*: string        ## the GeoNames feature code ("PASS", "HLL", "PPL", ...)
    isPlace*: bool              ## a populated place (class P)
    lon*, lat*: float

proc prepare*(n: Names, lon, lat: float): Prepared {.raises: [StoreError, DownloadError].} =
  ## Make the names of the country of (lon, lat) available, fetching what is missing.  `--offline`: nothing is had.
  if n.offline: return Prepared(status: rdNothing)
  n.ensureCountries()
  let iso = n.countryAt(lon, lat)
  if iso.isNone: return Prepared(status: rdNothing)
  var known = false
  guard:
    known = n.st.db.getValue(sql"select count(*) from country where iso = ?", iso.get) != "0"
  if not known: return Prepared(status: rdNothing)          # (a country the list of countries lacks)
  n.ensureNames(iso.get)
  Prepared(status: rdReady, iso: iso.get)

proc featuresNear*(n: Names, iso: string, lons, lats: openArray[float],
                   marginDeg = defaultMarginDeg): seq[Found] {.raises: [StoreError].} =
  ## The features of the country in the box round the positions, widened by the margin.
  if lons.len == 0: return
  var box = (lon0: Inf, lat0: Inf, lon1: -Inf, lat1: -Inf)
  for i in 0 ..< lons.len:
    box = (min(box.lon0, lons[i]), min(box.lat0, lats[i]), max(box.lon1, lons[i]), max(box.lat1, lats[i]))
  guard:
    for r in n.st.db.fastRows(sql("select name, code, class = 'P', ST_X(geom), ST_Y(geom) from feature " &
        "where country = ? and id in (select ROWID from SpatialIndex where f_table_name = 'feature' and " &
        "f_geometry_column = 'geom' and search_frame = BuildMbr(" &
        formatFloat(box.lon0 - marginDeg, ffDecimal, 6) & ", " & formatFloat(box.lat0 - marginDeg, ffDecimal, 6) & ", " &
        formatFloat(box.lon1 + marginDeg, ffDecimal, 6) & ", " & formatFloat(box.lat1 + marginDeg, ffDecimal, 6) & "))"), iso):
      try:
        result.add Found(name: r[0], code: r[1], isPlace: r[2] == "1", lon: parseFloat(r[3]), lat: parseFloat(r[4]))
      except ValueError:
        discard
