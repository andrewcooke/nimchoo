## Suggestions for a landmark: the features of GeoNames that are loaded (the `feature` table), of every kind, found by
## part of the name or by nearness to a position.  Only places whose cells have been read can be found.

import std/[algorithm, math, strutils]
import ../packages/db/statement
import ../packages/db/store
import ../core/errors
import ../packages/text/fold/fold
import ../packages/geo/geo

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

const featuresAroundSql* =
  columns & "where " & inBox("id", "feature", "geom", cornerMarks)

proc searchByName*(st: Store, text: string): seq[Suggestion] {.raises: [StoreError].} =
  ## Features whose name holds `text` (without regard to case or accents), the biggest places first.
  for r in st.db.query(
    Row,
    columns &
      "where instr(fold(name), :text) > 0 order by population desc, name, id limit :limit",
    text = foldText(text.strip),
    limit = maxSuggestions,
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
    featuresAroundSql,
    west = lon - dLon,
    south = lat - dLat,
    east = lon + dLon,
    north = lat + dLat,
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
