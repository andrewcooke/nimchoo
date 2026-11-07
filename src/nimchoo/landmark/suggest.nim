## Suggestions for a landmark: the features of GeoNames that are loaded (the `feature` table), of every kind, found by
## part of the name or by nearness to a position.  Only places whose cells have been read can be found.

import std/[algorithm, math, strutils]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ../geo

{.push raises: [].}

const maxSuggestions* = 30

type Suggestion* = object
  name*, cls*, code*: string
  lon*, lat*: float
  population*: int
  distanceM*: float ## from the position asked about (0 for a search by name)

proc fromRow(r: seq[string]): Suggestion {.raises: [ValueError].} =
  Suggestion(
    name: r[0],
    cls: r[1],
    code: r[2],
    lon: parseFloat(r[3]),
    lat: parseFloat(r[4]),
    population: parseInt(r[5]),
  )

proc searchByName*(st: Store, text: string): seq[Suggestion] {.raises: [StoreError].} =
  ## Features whose name holds `text` (without regard to case), the biggest places first.
  let like =
    "%" &
    text.strip.toLower.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") &
    "%"
  guard:
    for r in st.db.fastRows(
      sql(
        "select name, class, code, ST_X(geom), ST_Y(geom), coalesce(population, 0) from feature " &
          "where lower(name) like ? escape '\\' order by population desc, name, id limit " &
          $maxSuggestions
      ),
      like,
    ):
      try:
        result.add fromRow(r)
      except ValueError:
        raiseStore("a bad number in the features")

proc featuresAround*(
    st: Store, lon, lat: float, radiusM = 2000.0
): seq[Suggestion] {.raises: [StoreError].} =
  ## Features within the radius of the position, nearest first.
  let dLat = radiusM / 111_000.0
  let dLon = dLat / max(cos(degToRad(min(89.0, abs(lat) + dLat))), 0.02)
  guard:
    for r in st.db.fastRows(
      sql(
        "select name, class, code, ST_X(geom), ST_Y(geom), coalesce(population, 0) from feature " &
          "where id in (select ROWID from SpatialIndex where f_table_name = 'feature' and f_geometry_column = 'geom' and " &
          "search_frame = BuildMbr(" & formatFloat(lon - dLon, ffDecimal, 6) & ", " &
          formatFloat(lat - dLat, ffDecimal, 6) & ", " &
          formatFloat(lon + dLon, ffDecimal, 6) & ", " &
          formatFloat(lat + dLat, ffDecimal, 6) & "))"
      )
    ):
      try:
        var s = fromRow(r)
        s.distanceM = haversine(lon, lat, s.lon, s.lat)
        if s.distanceM <= radiusM:
          result.add s
      except ValueError:
        raiseStore("a bad number in the features")
  result.sort(
    proc(a, b: Suggestion): int =
      cmp(a.distanceM, b.distanceM)
  )
  if result.len > maxSuggestions:
    result.setLen maxSuggestions
