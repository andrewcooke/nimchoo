## A place by its name (names/places.nim): the author's landmarks first, then the features loaded, populated places first and
## the biggest first; case and accents do not matter.

import std/[os, sequtils, unittest]
import nimchoo/packages/db/statement
import nimchoo/packages/names/[landmarks, places]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

proc fresh(name: string): Session =
  let top = getTempDir() / "nch-test-places" / name
  removeDir(top)
  openSession(top / "x.db", allFragments, access = allAccess)

proc feature(s: Session, id: int, name, cls, code: string, lon, lat: float, pop = 0) =
  s.db.execute(
    "insert or ignore into country(iso, name, geoname_id) values ('CL', 'Chile', 1)"
  )
  s.db.execute(
    "insert into feature(id, country, name, class, code, population, geom) values (:id, 'CL', :name, :class, :code, :population, MakePoint(cast(:lon as real), cast(:lat as real), 4326))",
    id = id,
    name = name,
    class = cls,
    code = code,
    population = pop,
    lon = lon,
    lat = lat,
  )

suite "names: a place by its name":
  test "populated places first, the biggest first, then the rest; abandoned places never; case and accents do not matter":
    let s = fresh("order")
    defer:
      s.close()
    s.feature(1, "Providencia", "T", "HLL", -70.0, -33.0, 0)
    s.feature(2, "Providencia", "P", "PPL", -71.0, -34.0, 500)
    s.feature(3, "Providencia", "P", "PPLA3", -70.6, -33.43, 120_000)
    s.feature(4, "Providencia", "P", "PPLQ", -72.0, -35.0, 999_999)
    s.feature(5, "Ñuñoa", "P", "PPLA3", -70.59, -33.45, 200_000)
    let found = placesNamed(s, "PROVIDENCIA")
    check found.mapIt(it.lon) == @[-70.6, -71.0, -70.0]
    check found[0].what == "a populated place (PPLA3)" and
      found[2].what == "a feature (HLL)"
    check placesNamed(s, "nunoa").len == 1
    check placesNamed(s, "nowhere").len == 0

  test "a landmark of the author's comes before every feature of the name":
    let s = fresh("landmark")
    defer:
      s.close()
    s.feature(1, "Home", "P", "PPL", -71.0, -34.0, 1000)
    addLandmark(s, "home", -70.61, -33.43, 500.0)
    let found = placesNamed(s, "Home")
    check found.len == 2 and found[0].what == "your landmark" and found[0].lat == -33.43
