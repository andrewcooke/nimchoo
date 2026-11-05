## Naming a route: the one call that does everything underneath (see TODO.md, task 13).  From a route (its positions,
## in order, the last being the top of the climb) it finds the country of the top, makes sure the names of that
## country are in the table (fetching them the first time), looks at the features near the route and picks a name.
## What is shown to the caller is a result: a name, nothing to name it with, or "later" (the network or the disk
## stopped the names being had: nothing is decided, ask again another time).

import std/[math, options, strutils]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ../geo
import ./[countries, features, pick]

{.push raises: [].}

const
  boxMargin = 0.06             ## degrees (about 6 km) round the route, for the features looked at

type
  NameStatus* = enum nsNamed, nsNothing, nsLater

  NameResult* = object
    status*: NameStatus
    pick*: Pick                ## when named

func middleOf(route: openArray[XY]): XY =
  ## The point half way along the route.
  let half = route.length / 2.0
  var travelled = 0.0
  for i in 0 ..< route.high:
    let step = dist(route[i], route[i + 1])
    if step > 0 and travelled + step >= half:
      let u = (half - travelled) / step
      return XY(x: route[i].x + u * (route[i + 1].x - route[i].x), y: route[i].y + u * (route[i + 1].y - route[i].y))
    travelled += step
  route[^1]

proc candidatesNear*(n: Names, iso: string, lons, lats: openArray[float]): seq[Candidate]
    {.raises: [StoreError].} =
  ## The features of the country near the route, with their distances from its top and from its middle.
  if lons.len == 0: return
  var box = (lon0: Inf, lat0: Inf, lon1: -Inf, lat1: -Inf)
  for i in 0 ..< lons.len:
    box = (min(box.lon0, lons[i]), min(box.lat0, lats[i]), max(box.lon1, lons[i]), max(box.lat1, lats[i]))
  let pr = projection(lons[0], lats[0])
  var route: seq[XY]
  for i in 0 ..< lons.len: route.add pr.project(lons[i], lats[i])
  let top = route[^1]
  let middle = middleOf(route)
  guard:
    for r in n.st.db.fastRows(sql("select name, code, class = 'P', ST_X(geom), ST_Y(geom) from feature " &
        "where country = ? and id in (select ROWID from SpatialIndex where f_table_name = 'feature' and " &
        "f_geometry_column = 'geom' and search_frame = BuildMbr(" &
        formatFloat(box.lon0 - boxMargin, ffDecimal, 6) & ", " & formatFloat(box.lat0 - boxMargin, ffDecimal, 6) & ", " &
        formatFloat(box.lon1 + boxMargin, ffDecimal, 6) & ", " & formatFloat(box.lat1 + boxMargin, ffDecimal, 6) & "))"), iso):
      try:
        let p = pr.project(parseFloat(r[3]), parseFloat(r[4]))
        result.add Candidate(name: r[0], code: r[1], isPlace: r[2] == "1", fromTopM: dist(p, top),
                             fromMiddleM: dist(p, middle))
      except ValueError:
        discard

proc nameRoute*(n: Names, lons, lats: openArray[float]): NameResult {.raises: [StoreError].} =
  ## The name for a route, if the names can be had now.
  if lons.len == 0: return NameResult(status: nsNothing)
  if not n.ensureCountries(): return NameResult(status: nsLater)
  let iso = n.countryAt(lons[^1], lats[^1])
  if iso.isNone: return NameResult(status: nsNothing)
  var known = false
  guard:
    known = n.st.db.getValue(sql"select count(*) from country where iso = ?", iso.get) != "0"
  if not known: return NameResult(status: nsNothing)         # (a country the list of countries lacks)
  if not n.ensureNames(iso.get): return NameResult(status: nsLater)
  let p = pickName(n.candidatesNear(iso.get, lons, lats))
  if p.isSome: NameResult(status: nsNamed, pick: p.get) else: NameResult(status: nsNothing)
