## The landmarks: places the author has named, each a position and a radius (see 001-schema.sql).  Pure database
## code, used by the naming (a landmark comes before every other name) and by `nch landmarks`.

import std/[options, strutils]
import ../db/[statement, store]
import ../errors
import ../geo

{.push raises: [].}

const
  defaultRadiusM* = 1000.0
  minRadiusM* = 100.0
  maxRadiusM* = 20000.0

type Landmark* = object
  id*: int64
  name*: string
  lon*, lat*: float
  radiusM*: float

proc listLandmarks*(st: Store): seq[Landmark] {.raises: [StoreError].} =
  ## All of them, by name.
  st.db.query(
    Landmark, "select id, name, lon, lat, radius_m from landmark order by fold(name)"
  )

func problem*(name: string, lon, lat, radiusM: float): string =
  ## "" if these can be a landmark, else what is wrong.
  let t = name.strip
  if t.len == 0:
    return "a landmark needs a name"
  if t.len > 60:
    return "a name has at most 60 characters"
  for c in t:
    if c < ' ' or c == '\x7f':
      return "a name cannot hold control characters"
  if lon < -180.0 or lon > 180.0:
    return "longitude is from -180 to 180"
  if lat < -90.0 or lat > 90.0:
    return "latitude is from -90 to 90"
  if radiusM < minRadiusM or radiusM > maxRadiusM:
    return
      "the radius is from " & $int(minRadiusM) & " to " & $int(maxRadiusM) & " metres"
  ""

proc addLandmark*(
    st: Store, name: string, lon, lat, radiusM: float
) {.raises: [StoreError].} =
  ## Make a landmark; the name must not be used already (without regard to case or accents).
  let why = problem(name, lon, lat, radiusM)
  if why.len > 0:
    raiseStore(why)
  if st.db.scalar(
    int, "select count(*) from landmark where fold(name) = fold(?)", name.strip
  ) != 0:
    raiseStore("there is a landmark called '" & name.strip & "' already")
  st.db.execute(
    "insert into landmark(name, lon, lat, radius_m) values (?, ?, ?, ?)", name.strip,
    lon, lat, radiusM,
  )

proc removeLandmark*(st: Store, name: string): bool {.raises: [StoreError].} =
  ## Delete the landmark called `name` (without regard to case or accents); whether there was one.
  if st.db.scalar(
    int, "select count(*) from landmark where fold(name) = fold(?)", name.strip
  ) == 0:
    return false
  st.db.execute("delete from landmark where fold(name) = fold(?)", name.strip)
  true

proc landmarkAt*(
    st: Store, lon, lat: float
): Option[tuple[landmark: Landmark, distanceM: float]] {.raises: [StoreError].} =
  ## The landmark whose circle holds the position; if several do, the one whose centre is nearest.
  for l in st.listLandmarks():
    let d = haversine(lon, lat, l.lon, l.lat)
    if d <= l.radiusM and (result.isNone or d < result.get.distanceM):
      result = some((l, d))
