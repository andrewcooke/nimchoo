## Putting the places into the database when it is made (a fragment's seed: see
## db/fragment.nim), and finding the nearest to a point.

import std/[math, options, strutils]
import db_connector/db_sqlite
import ../db/[statement, store]
import ../errors
import ./data

{.push raises: [].}

type Nearest* = object
  name*, country*: string
  distanceM*: float

proc loadPlaces*(db: DbConn, rows: seq[PlaceRow], source = "geonames")
    {.raises: [StoreError].} =
  ## Insert places, and make the spatial index (after the rows: that is much faster).
  ## Called inside the transaction that makes the table.
  let st = prepareStmt(db, "insert into place(name, country, population, source, geom) " &
    "values (?, ?, ?, ?, MakePoint(?, ?, 4326))")
  try:
    for r in rows:
      st.bindText(1, r.name)
      st.bindText(2, r.country)
      st.bindInt(3, int64(r.population))
      st.bindText(4, source)
      st.bindReal(5, r.lon)
      st.bindReal(6, r.lat)
      st.run()
  finally:
    finalize(st)
  guard:
    db.exec(sql"select CreateSpatialIndex('place', 'geom')")

proc seedPlaces*(db: DbConn) {.raises: [StoreError].} =
  ## The seed of the places fragment: the list the program carries.
  let rows = carriedPlaces()
  if rows.len == 0: raiseStore("the list of places the program carries cannot be read")
  loadPlaces(db, rows)

func degrees(x: float): string = formatFloat(x, ffDecimal, 6)

proc nearestInBox(db: DbConn, lon, lat, minX, minY, maxX, maxY: float): Option[Nearest]
    {.raises: [StoreError].} =
  ## The nearest place to a point among those in a box (degrees).
  guard:
    let r = db.getRow(sql("select name, country, ST_Distance(geom, MakePoint(" & degrees(lon) &
      ", " & degrees(lat) & ", 4326), 1) as d from place where rowid in (select rowid from " &
      "SpatialIndex where f_table_name = 'place' and f_geometry_column = 'geom' and " &
      "search_frame = BuildMbr(" & degrees(minX) & ", " & degrees(minY) & ", " & degrees(maxX) &
      ", " & degrees(maxY) & ")) order by d limit 1"))
    if r[0].len == 0: return none(Nearest)
    try:
      result = some(Nearest(name: r[0], country: r[1], distanceM: parseFloat(r[2])))
    except ValueError:
      raiseStore("bad number from the database")

proc nearestIn(db: DbConn, lon, lat, half: float): Option[Nearest] {.raises: [StoreError].} =
  ## The nearest place among those in the box of `half` degrees round the point.  A box that
  ## goes past the date line (longitude 180 / -180) also takes in the part on the other side.
  let minY = max(-90.0, lat - half)
  let maxY = min(90.0, lat + half)
  var spans = @[(max(-180.0, lon - half), min(180.0, lon + half))]
  if lon - half < -180.0: spans.add (lon - half + 360.0, 180.0)
  if lon + half > 180.0: spans.add (-180.0, lon + half - 360.0)
  for (minX, maxX) in spans:
    let found = nearestInBox(db, lon, lat, minX, minY, maxX, maxY)
    if found.isSome and (result.isNone or found.get.distanceM < result.get.distanceM):
      result = found

proc nearestPlace*(db: DbConn, lon, lat: float): Option[Nearest] {.raises: [StoreError].} =
  ## The place nearest to a point, by distance on the ground.  Looks in a small box first
  ## and widens it step by step; once something is found, one more look in a box that
  ## certainly holds everything as near (a box narrower than the distance found could miss
  ## a nearer place just outside it).  None only if there are no places at all.
  for half in [1.0, 5.0, 20.0, 90.0, 360.0]:
    let found = nearestIn(db, lon, lat, half)
    if found.isNone: continue
    # degrees of longitude are shorter away from the equator
    let across = 111_000.0 * max(cos(degToRad(lat)), 0.05)
    let safe = found.get.distanceM / across + 0.5
    if safe <= half: return found
    return nearestIn(db, lon, lat, min(safe, 360.0))
  none(Nearest)
