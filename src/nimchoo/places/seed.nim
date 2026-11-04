## Putting the places into the database when it is made (a fragment's seed: see
## db/fragment.nim), and finding the nearest to a point.

import std/[math, options, strutils]
import db_connector/db_sqlite
import ../db/[statement, store]
import ../errors
import ./data

{.push raises: [].}

type Nearest* = object
  id*: int64
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
  let list = placesList()
  if list.rows.len == 0:
    raiseStore(if list.path.len > 0: "the list of places " & list.path & " cannot be read (it is " &
                 "tab-separated lines: name, country, latitude, longitude, population; gzipped or not)"
               else: "the list of places the program carries cannot be read")
  loadPlaces(db, list.rows)

func degrees(x: float): string = formatFloat(x, ffDecimal, 6)

proc nearestInBox(db: DbConn, lon, lat, minX, minY, maxX, maxY: float): Option[Nearest]
    {.raises: [StoreError].} =
  ## The nearest place to a point among those in a box (degrees).
  guard:
    let r = db.getRow(sql("select name, country, id, ST_Distance(geom, MakePoint(" & degrees(lon) &
      ", " & degrees(lat) & ", 4326), 1) as d from place where rowid in (select rowid from " &
      "SpatialIndex where f_table_name = 'place' and f_geometry_column = 'geom' and " &
      "search_frame = BuildMbr(" & degrees(minX) & ", " & degrees(minY) & ", " & degrees(maxX) &
      ", " & degrees(maxY) & ")) order by d limit 1"))
    if r[0].len == 0: return none(Nearest)
    try:
      result = some(Nearest(name: r[0], country: r[1], id: parseBiggestInt(r[2]),
                            distanceM: parseFloat(r[3])))
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

proc reloadPlaces*(db: DbConn) {.raises: [StoreError].} =
  ## Replace the places with the list now in use (see `placesList`), and point each activity at the
  ## nearest place of the new list.  Called inside a transaction when the database was made from
  ## another list; nothing else in the database is touched.
  let list = placesList()
  if list.rows.len == 0:
    raiseStore(if list.path.len > 0: "the list of places " & list.path & " cannot be read (it is " &
                 "tab-separated lines: name, country, latitude, longitude, population; gzipped or not)"
               else: "the list of places the program carries cannot be read")
  guard:
    db.exec(sql"select DisableSpatialIndex('place', 'geom')")
    db.exec(sql"drop table if exists idx_place_geom")
    db.exec(sql"delete from place")                      # (the activities' places become null)
  loadPlaces(db, list.rows)
  var starts: seq[(string, float, float)]               # (activity id, lon, lat)
  guard:
    for r in db.fastRows(sql"select id, ST_X(start), ST_Y(start) from activity where start is not null"):
      try: starts.add (r[0], parseFloat(r[1]), parseFloat(r[2]))
      except ValueError: raiseStore("bad start in the database")
  for (id, lon, lat) in starts:
    let near = nearestPlace(db, lon, lat)
    if near.isSome:
      guard: db.exec(sql"update activity set place_id = ? where id = ?", near.get.id, id)
