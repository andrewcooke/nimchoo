## Suggestions for a landmark: the features of GeoNames that are loaded (the `feature` table), of every kind, found by
## part of the name or by nearness to a position.  Only places whose cells have been read can be found.

import std/[algorithm, math, strutils]
import ../db/[statement, store]
import ../errors
import ../fold
import ../geo

{.push raises: [].}

const maxSuggestions* = 30

type Suggestion* = object
  name*, cls*, code*: string
  lon*, lat*: float
  population*: int
  distanceM*: float ## from the position asked about (0 for a search by name)

type Row = tuple[name, cls, code: string, lon, lat: float, population: int]

const columns =
  "select name, class, code, ST_X(geom), ST_Y(geom), coalesce(population, 0) from feature "

func suggestion(r: Row): Suggestion =
  Suggestion(
    name: r.name,
    cls: r.cls,
    code: r.code,
    lon: r.lon,
    lat: r.lat,
    population: r.population,
  )

proc searchByName*(st: Store, text: string): seq[Suggestion] {.raises: [StoreError].} =
  ## Features whose name holds `text` (without regard to case or accents), the biggest places first.
  for r in st.db.query(
    Row,
    columns & "where instr(fold(name), ?) > 0 order by population desc, name, id limit ?",
    foldText(text.strip),
    maxSuggestions,
  ):
    result.add suggestion(r)

proc featuresAround*(
    st: Store, lon, lat: float, radiusM = 2000.0
): seq[Suggestion] {.raises: [StoreError].} =
  ## Features within the radius of the position, nearest first.
  let dLat = radiusM / 111_000.0
  let dLon = dLat / max(cos(degToRad(min(89.0, abs(lat) + dLat))), 0.02)
  for r in st.db.query(
    Row,
    columns &
      "where id in (select ROWID from SpatialIndex where f_table_name = 'feature' and " &
      "f_geometry_column = 'geom' and search_frame = BuildMbr(?, ?, ?, ?))",
    lon - dLon,
    lat - dLat,
    lon + dLon,
    lat + dLat,
  ):
    var s = suggestion(r)
    s.distanceM = haversine(lon, lat, s.lon, s.lat)
    if s.distanceM <= radiusM:
      result.add s
  result.sort(
    proc(a, b: Suggestion): int =
      cmp(a.distanceM, b.distanceM)
  )
  if result.len > maxSuggestions:
    result.setLen maxSuggestions
