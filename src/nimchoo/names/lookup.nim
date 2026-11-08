## The part of naming that does not depend on what is being named: where a position is (its country), that
## the names of that country are in the table (fetched the first time), and the features near a route.  Positions that
## spread too far for a ride (`maxSpanDeg`) get nothing fetched, so one bad fix cannot make a download.
## What a name should be for a climb, an activity, ... is a rule of its own (climb.nim, and the others to come),
## made from these.

import std/[math, strutils]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ./[countries, features]

{.push raises: [].}

const
  defaultMarginM* = 6_000.0 ## metres round the route, for the features looked at
  maxSpanDeg* = 5.0
    ## The most the box round some positions (with its margin) may measure, in degrees of longitude or latitude (about
    ## 550 km), for names to be fetched for it.  A stretch of riding is continuous, so a spread beyond this is a bad fix, and fetching the countries it
    ## would touch (once, every country: ~250 downloads) is the cost of believing it.  The widest stretch of the author's
    ## 1,112 activities is 1.01 degrees.

type
  Readiness* = enum
    rdReady ## the names round the place are in the table
    rdNothing
      ## there is nothing to be had for this place (the sea, a country the list lacks, `--offline`)
    rdTooWide ## the positions spread over more than `maxSpanDeg`: nothing is fetched for them

  Prepared* = object
    status*: Readiness

  Part* = tuple[lons, lats: seq[float]] ## The positions of one stretch of riding, in order.

  Found* = object
    ## A feature of the table, as it is: where it is and what it is called.
    name*, code*: string ## the GeoNames feature code ("PASS", "HLL", "PPL", ...)
    isPlace*: bool ## a populated place (class P)
    lon*, lat*: float

func boxAround*(lons, lats: openArray[float], marginM: float): Box =
  ## The box round the positions, widened by the margin: the margin is metres, so a degree of longitude counts for less
  ## towards the poles (the box then reaches further in degrees of longitude, up to the whole circle).
  var b = (lon0: Inf, lat0: Inf, lon1: -Inf, lat1: -Inf)
  for i in 0 ..< lons.len:
    b = (
      min(b.lon0, lons[i]),
      min(b.lat0, lats[i]),
      max(b.lon1, lons[i]),
      max(b.lat1, lats[i]),
    )
  let dLat = marginM / 111_000.0
  let worst = max(abs(b.lat0), abs(b.lat1)) + dLat
    # the latitude where a degree of longitude is shortest
  let dLon =
    if worst >= 89.0:
      360.0
    else:
      dLat / max(cos(degToRad(worst)), 0.02)
  (
    lon0: b.lon0 - dLon,
    lat0: max(-90.0, b.lat0 - dLat),
    lon1: b.lon1 + dLon,
    lat1: min(90.0, b.lat1 + dLat),
  )

proc countriesIn(
    n: Names, box: Box
): seq[string] {.raises: [StoreError, DownloadError].} =
  ## The countries the box touches: those of the cells it covers (a cell on a border has both countries, so a box over
  ## a border takes both).  The cells are worked out once and kept (see countries.nim).  The box is not wide
  ## (`prepare` refuses a spread over `maxSpanDeg`), so these are few.
  let cx0 = int(floor(box.lon0 * cellsPerDegree.float))
  let cx1 = int(floor(box.lon1 * cellsPerDegree.float))
  let cy0 = max(-90 * cellsPerDegree, int(floor(box.lat0 * cellsPerDegree.float)))
  let cy1 = min(90 * cellsPerDegree - 1, int(floor(box.lat1 * cellsPerDegree.float)))
  for cx in cx0 .. cx1:
    for cy in cy0 .. cy1:
      for iso in n.countriesOfCell(wrapCell(cx), cy):
        if iso notin result:
          result.add iso

proc prepare*(
    n: Names, lons, lats: openArray[float], marginM = defaultMarginM
): Prepared {.raises: [StoreError, DownloadError].} =
  ## Make the names round the positions available (the cells they touch, of the countries they touch), fetching what is
  ## missing.  `--offline`: nothing is had.
  if n.offline or lons.len == 0:
    return Prepared(status: rdNothing)
  let box = boxAround(lons, lats, marginM)
  if box.lon1 - box.lon0 > maxSpanDeg or box.lat1 - box.lat0 > maxSpanDeg:
    return Prepared(status: rdTooWide)
      # (the box, not the positions: a single point with a radius of thousands of km is as wide)
  n.ensureCountries()
  let isos = n.countriesIn(box)
  if isos.len == 0:
    return Prepared(status: rdNothing)
  for iso in isos:
    var known = false
    guard:
      known =
        n.st.db.getValue(sql"select count(*) from country where iso = ?", iso) != "0"
    if known:
      n.ensureCells(iso, box) # (a country the list of countries lacks has nothing)
  Prepared(status: rdReady)

proc featuresNear*(
    n: Names, lons, lats: openArray[float], marginM = defaultMarginM
): seq[Found] {.raises: [StoreError].} =
  ## The features in the box round the positions, widened by the margin (whatever country they are in).
  if lons.len == 0:
    return
  let box = boxAround(lons, lats, marginM)
  guard:
    for r in n.st.db.fastRows(
      sql(
        "select name, code, class = 'P', ST_X(geom), ST_Y(geom) from feature " &
          "where id in (select ROWID from SpatialIndex where f_table_name = 'feature' and " &
          "f_geometry_column = 'geom' and search_frame = BuildMbr(" &
          formatFloat(box.lon0, ffDecimal, 6) & ", " &
          formatFloat(box.lat0, ffDecimal, 6) & ", " &
          formatFloat(box.lon1, ffDecimal, 6) & ", " &
          formatFloat(box.lat1, ffDecimal, 6) & "))"
      )
    ):
      try:
        result.add Found(
          name: r[0],
          code: r[1],
          isPlace: r[2] == "1",
          lon: parseFloat(r[3]),
          lat: parseFloat(r[4]),
        )
      except ValueError:
        discard
