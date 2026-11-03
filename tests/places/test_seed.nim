import std/[math, options, os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/modules
import checksums/sha2
import nimchoo/places/[data, seed]

proc near(s: Store, lon, lat: float): Nearest =
  nearestPlace(s.db, lon, lat).get

suite "places: made with the database":
  test "a new database has the places (the short list in tests), as geonames, with an index":
    let s = openStore(":memory:", allFragments)
    defer: s.close()
    check s.db.getValue(sql"select count(*) from place where source = 'geonames'") ==
      $carriedPlaces().len
    check s.db.getValue(sql"select count(*) from idx_place_geom") == $carriedPlaces().len
  test "the place table is not any user's":
    let s = openStore(":memory:", allFragments)
    defer: s.close()
    s.db.exec(sql"insert into user(name) values ('bob')")
    s.db.exec(sql"delete from user where name = 'bob'")
    check s.db.getValue(sql"select count(*) from place") == $carriedPlaces().len

suite "places: the nearest":
  let s = openStore(":memory:", allFragments)

  test "close to a city: that city, a short way off":
    let n = s.near(-70.65, -33.45)            # Santiago
    check n.name == "Santiago" and n.country == "CL"
    check n.distanceM < 2_000
  test "it says which place, by its id":
    let n = s.near(-70.65, -33.45)
    check s.db.getValue(sql"select name from place where id = ?", n.id) == "Santiago"
  test "accented names come out as they are":
    check s.near(-71.62, -33.05).name == "Valparaíso"
    check s.near(8.55, 47.37).name == "Zürich"
  test "the nearest of two places of one name is the one near":
    check s.near(-95.5, 33.7).country == "US"       # Paris, Texas
    check s.near(2.35, 48.85).country == "FR"        # Paris, France
  test "far from everything: still the nearest, with how far":
    let n = s.near(-72.0, -46.0)                     # near Coyhaique
    check n.name == "Coyhaique" and n.distanceM > 30_000 and n.distanceM < 100_000
    let sea = s.near(-30.0, 0.0)                     # the middle of the Atlantic
    check sea.distanceM > 1_000_000
  test "any place on earth has a nearest, edges and poles too":
    for (lon, lat) in [(0.0, 90.0), (0.0, -90.0), (180.0, 0.0), (-180.0, 0.0), (179.9, -17.0),
                       (-179.9, 65.0), (0.0, 0.0)]:
      check nearestPlace(s.db, lon, lat).isSome
  test "across the date line":
    let n = s.near(-179.5, -36.0)                     # east of Auckland, over the line
    check n.name == "Auckland" and n.distanceM < 700_000
    let other = s.near(179.9, 65.0)                   # the other way: west of the line, Anchorage is across it
    check other.name == "Anchorage"
  test "the distance is on the ground":
    let n = s.near(-70.65, -32.45)                    # a degree of latitude (111 km) north of Santiago
    check n.name == "Santiago" and abs(n.distanceM - 111_000) < 3_000

suite "places: the box is wide enough":
  test "a nearer place just outside the first box is found (degrees of longitude are short up north)":
    let s = openStore(":memory:", @[])
    defer: s.close()
    s.db.exec(sql"""create table place (id integer primary key, name text not null, country text not null,
      population integer not null default 0, source text not null)""")
    s.db.exec(sql"select AddGeometryColumn('place', 'geom', 4326, 'POINT', 'XY')")
    loadPlaces(s.db, @[PlaceRow(name: "C", country: "NO", lat: 71.0, lon: 2.3),
                       PlaceRow(name: "D", country: "NO", lat: 70.0, lon: 3.0)])
    # from (1.4, 70.0): C is 1 degree north and 0.9 east (about 116 km) and inside the first
    # one-degree box; D is 1.6 degrees east (about 61 km) and outside it.  D is nearer.
    let n = nearestPlace(s.db, 1.4, 70.0).get
    check n.name == "D"
    check n.distanceM < 70_000
  test "an empty table has no nearest":
    let s = openStore(":memory:", @[])
    defer: s.close()
    s.db.exec(sql"""create table place (id integer primary key, name text not null, country text not null,
      population integer not null default 0, source text not null)""")
    s.db.exec(sql"select AddGeometryColumn('place', 'geom', 4326, 'POINT', 'XY')")
    loadPlaces(s.db, @[])
    check nearestPlace(s.db, 0.0, 0.0).isNone

suite "places: the real list":
  test "sections of a populated place (suburbs, districts) are not in it, the cities are":
    let real = parsePlaces(unpack(readFile("src/nimchoo/places/cities.tsv.gz"), true))
    var names: seq[string]
    for r in real: names.add r.name & "," & r.country
    check "Santiago,CL" in names and "London,GB" in names and "Sydney,AU" in names
    check "Ñuñoa,CL" notin names and "Whitechapel,GB" notin names
  test "the version file is the hash of the list (the tool writes both)":
    var expected = ""
    for c in secureHash(Sha_256, readFile("src/nimchoo/places/cities.tsv.gz")):
      expected.add toLowerAscii(toHex(ord(c), 2))
    check readFile("src/nimchoo/places/cities.version").strip == expected
  test "about sixty-five thousand places, among them the ones you would expect":
    let real = parsePlaces(unpack(readFile("src/nimchoo/places/cities.tsv.gz"), true))
    check real.len > 60_000 and real.len < 68_000
    var found: seq[string]
    for r in real:
      if (r.name, r.country) in [("Santiago", "CL"), ("Lisbon", "PT"), ("Tokyo", "JP"),
                                 ("Zürich", "CH"), ("Valparaíso", "CL")]:
        found.add r.name & "," & r.country
    check found.len >= 5
  test "loaded into a database, the nearest to a ride in Chile is Santiago":
    let real = parsePlaces(unpack(readFile("src/nimchoo/places/cities.tsv.gz"), true))
    let s = openStore(":memory:", @[])
    defer: s.close()
    s.db.exec(sql"""create table place (id integer primary key, name text not null, country text not null,
      population integer not null default 0, source text not null)""")
    s.db.exec(sql"select AddGeometryColumn('place', 'geom', 4326, 'POINT', 'XY')")
    loadPlaces(s.db, real)
    # Providencia, where most of the author's rides start: GeoNames has it only as an
    # administrative area, and Nunoa only as a section of a populated place, which the list
    # leaves out; so the nearest is the city
    let n = nearestPlace(s.db, -70.61, -33.43).get
    check n.name == "Santiago" and n.country == "CL"
    check n.distanceM < 8_000
