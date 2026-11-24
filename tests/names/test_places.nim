## A place by its name (names/places.nim): the author's landmarks first, then the features loaded, populated places first and
## the biggest first; case and accents do not matter; a whole name, then a word of a name, then a part of one; the first a
## search finds something near.

import std/[os, sequtils, strutils, unittest]
import nimchoo/core/errors
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
    let found = placesMatching(s, "PROVIDENCIA", mWhole)
    check found.mapIt(it.lon) == @[-70.6, -71.0, -70.0]
    check found[0].what == "a populated place (PPLA3, CL)" and
      found[2].what == "a feature (HLL, CL)"
    check placesMatching(s, "nunoa", mWhole).len == 1
    check placesMatching(s, "nowhere", mWhole).len == 0

  test "a landmark of the author's comes before every feature of the name":
    let s = fresh("landmark")
    defer:
      s.close()
    s.feature(1, "Home", "P", "PPL", -71.0, -34.0, 1000)
    addLandmark(s, "home", -70.61, -33.43, 500.0)
    let found = placesMatching(s, "Home", mWhole)
    check found.len == 2 and found[0].what == "your landmark" and found[0].lat == -33.43

  test "a whole name, then a word of one, then a part of one; each kind without the closer ones":
    let s = fresh("kinds")
    defer:
      s.close()
    s.feature(1, "El Toyo", "S", "FRM", -70.35, -33.68)
    s.feature(2, "Toyota", "P", "PPL", -71.0, -34.0, 9000)
    s.feature(3, "Toyo", "T", "HLL", -2.0, 53.0)
    check placesMatching(s, "toyo", mWhole).mapIt(it.name) == @["Toyo"]
    check placesMatching(s, "toyo", mWord).mapIt(it.name) == @["El Toyo"]
    check placesMatching(s, "toyo", mPart).mapIt(it.name) == @["Toyota"]
    check placesMatching(s, "el toyo", mWhole).mapIt(it.name) == @["El Toyo"]
    check placesMatching(s, "toy", mPart).mapIt(it.name) ==
      @["Toyota", "El Toyo", "Toyo"]
    check placesMatching(s, "  ", mPart).len == 0
    check placesMatching(s, "%", mPart).len == 0 # (a value, not a pattern)

  test "for a search: the first, in that order, near which it finds something; else the first, said":
    let s = fresh("choose")
    defer:
      s.close()
    s.feature(1, "El Toyo", "S", "FRM", -70.35, -33.68)
    s.feature(2, "Toyo", "T", "HLL", -2.0, 53.0)
    let nearChile = proc(lat, lon: float): bool {.closure, raises: [StoreError].} =
      lat < 0
    let p = placeNamed(s, "toyo", nearChile)
    check p.lat == -33.68
      # (El Toyo, a word, after Toyo in England, which the search finds nothing near)
    check "this has it as a word of its name" in p.said
    let nowhere = proc(lat, lon: float): bool {.closure, raises: [StoreError].} =
      false
    let q = placeNamed(s, "toyo", nowhere)
    check q.lat == 53.0 and "your search finds nothing near it" in q.said
    check placeNamed(s, "toyo").lat == 53.0 # (no search: the first)
    expect StoreError:
      discard placeNamed(s, "zzqq")

  test "what is said names the others, three at most, and counts the rest":
    let s = fresh("others")
    defer:
      s.close()
    for i in 1 .. 6:
      s.feature(i, "San Juan", "P", "PPL", -70.0 - i.float, -33.0, 1000 - i)
    let p = placeNamed(s, "san juan")
    check p.said.count("San Juan,") == 4 # the one taken, and three others
    check p.said.endsWith("; and 2 more")
