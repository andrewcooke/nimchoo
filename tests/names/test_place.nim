import std/[options, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/modules
import nimchoo/names/place
import nimchoo/places/seed

suite "names: which place is this position near":
  test "the place is the nearest of the list in the program, with its distance and its row":
    let s = openStore(":memory:", allFragments)
    defer: s.close()
    let p = placeAt(s, -70.65, -33.45)                    # Santiago
    check p.isSome
    check p.get.name == "Santiago" and p.get.country == "CL"
    check p.get.distanceM < 5_000.0
    check s.db.getValue(sql"select name from place where id = ?", p.get.id) == "Santiago"
  test "it is the same as the list's own answer":
    let s = openStore(":memory:", allFragments)
    defer: s.close()
    for (lon, lat) in [(0.0, 0.0), (151.2, -33.9), (-179.5, -36.0)]:
      let a = placeAt(s, lon, lat).get
      let b = nearestPlace(s.db, lon, lat).get
      check a.name == b.name and a.id == b.id and a.distanceM == b.distanceM
  test "no places at all: none":
    let s = openStore(":memory:", @[])
    defer: s.close()
    s.db.exec(sql"""create table place (id integer primary key, name text not null, country text not null,
      population integer not null default 0, source text not null)""")
    s.db.exec(sql"select AddGeometryColumn('place', 'geom', 4326, 'POINT', 'XY')")
    loadPlaces(s.db, @[])
    check placeAt(s, 0.0, 0.0).isNone
