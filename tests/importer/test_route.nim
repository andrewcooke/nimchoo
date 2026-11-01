import std/[options, os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/importer/[extract, route]
import nimchoo/modules

func coord(t: int64, lon, lat: float): Coord =
  Coord(t: t, lon: lon, lat: lat)

suite "route: the geometry text":
  test "a part for each segment, in order":
    let a = ActivityData(
      coords: @[coord(1, 1.5, 2.5), coord(2, 1.6, 2.6), coord(10, 3.0, 4.0), coord(11, 3.1, 4.1)],
      segments: @[Segment(startT: 1, endT: 2), Segment(startT: 10, endT: 11)])
    check routeWkt(a) == some("MULTILINESTRING((1.5000000 2.5000000, 1.6000000 2.6000000), " &
                              "(3.0000000 4.0000000, 3.1000000 4.1000000))")

  test "a segment with fewer than two points leaves no part":
    let a = ActivityData(
      coords: @[coord(1, 1.0, 2.0), coord(5, 3.0, 4.0), coord(6, 3.5, 4.5)],
      segments: @[Segment(startT: 1, endT: 1), Segment(startT: 5, endT: 6)])
    check routeWkt(a) == some("MULTILINESTRING((3.0000000 4.0000000, 3.5000000 4.5000000))")

  test "no part at all, no route":
    check routeWkt(ActivityData()).isNone
    check routeWkt(ActivityData(coords: @[coord(1, 1.0, 2.0)],
                                segments: @[Segment(startT: 1, endT: 1)])).isNone

  test "negative coordinates":
    let a = ActivityData(coords: @[coord(1, -9.14, 38.72), coord(2, -9.1, 38.75)],
                         segments: @[Segment(startT: 1, endT: 2)])
    check routeWkt(a).get.contains("(-9.1400000 38.7200000, -9.1000000 38.7500000)")

suite "route: in the database":
  let dir = getTempDir() / "nch-test-route"

  proc store(name: string): Store =
    removeDir(dir / name)
    openStore(dir / name / "x.db", allFragments)

  test "SpatiaLite is there: a route can be stored and asked how far it is":
    let s = store("sp")
    defer: s.close()
    s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (1, 'f', 'x', 0)")
    s.db.exec(sql"insert into activity(file_id, session, start_t, end_t) values (1, 0, 0, 10)")
    s.db.exec(sql"""insert into route(activity_id, geom) values (1,
      GeomFromText('MULTILINESTRING((-9.14 38.72, -9.10 38.75, -9.00 38.80))', 4326))""")
    let metres = parseFloat(s.db.getValue(sql"""select ST_Distance(geom,
      MakePoint(-9.13, 38.73, 4326), 1) from route"""))
    check metres > 150 and metres < 250          # (206 m)

  test "deleting the user takes the route and its index entry too":
    let s = store("cascade")
    defer: s.close()
    s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (1, 'f', 'x', 0)")
    s.db.exec(sql"insert into activity(file_id, session, start_t, end_t) values (1, 0, 0, 10)")
    s.db.exec(sql"""insert into route(activity_id, geom) values (1,
      GeomFromText('MULTILINESTRING((-9.14 38.72, -9.10 38.75))', 4326))""")
    check s.db.getValue(sql"select count(*) from idx_route_geom") == "1"
    s.db.exec(sql"delete from user where id = 1")
    check s.db.getValue(sql"select count(*) from route") == "0"
    check s.db.getValue(sql"select count(*) from idx_route_geom") == "0"
