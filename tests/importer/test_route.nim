import std/[options, os, unittest]
import nimchoo/db/[statement, store]
import nimchoo/packages/fit/time
import nimchoo/importer/[extract, route]
import nimchoo/modules

func coord(t: int64, lon, lat: float): Coord =
  Coord(t: UnixTime(t), lon: lon, lat: lat)

# a reader of the bytes, to check them (the standard form: see route.nim)
proc u32(s: string, pos: int): int =
  for i in 0 ..< 4:
    result = result or (ord(s[pos + i]) shl (8 * i))

proc f64(s: string, pos: int): float =
  var v = 0'u64
  for i in 0 ..< 8:
    v = v or (uint64(ord(s[pos + i])) shl (8 * i))
  cast[float](v)

proc lines(wkb: string): seq[seq[(float, float)]] =
  ## The parts of a MULTILINESTRING in little-endian WKB, as lists of (lon, lat).
  doAssert wkb[0] == '\x01' and u32(wkb, 1) == 5
  var pos = 9
  for _ in 0 ..< u32(wkb, 5):
    doAssert wkb[pos] == '\x01' and u32(wkb, pos + 1) == 2
    let n = u32(wkb, pos + 5)
    pos += 9
    var pts: seq[(float, float)]
    for _ in 0 ..< n:
      pts.add (f64(wkb, pos), f64(wkb, pos + 8))
      pos += 16
    result.add pts
  doAssert pos == wkb.len

suite "route: the geometry bytes":
  test "a part for each segment, in order":
    let a = ActivityData(
      coords: @[
        coord(1, 1.5, 2.5), coord(2, 1.6, 2.6), coord(10, 3.0, 4.0), coord(11, 3.1, 4.1)
      ],
      segments: @[
        Segment(startT: UnixTime(1), endT: UnixTime(2)),
        Segment(startT: UnixTime(10), endT: UnixTime(11)),
      ],
    )
    check routeWkb(a).get.lines ==
      @[@[(1.5, 2.5), (1.6, 2.6)], @[(3.0, 4.0), (3.1, 4.1)]]

  test "the points are read back, parts one after the other; anything else gives none":
    let a = ActivityData(
      coords: @[
        coord(1, 1.5, 2.5), coord(2, 1.6, 2.6), coord(10, 3.0, 4.0), coord(11, 3.1, 4.1)
      ],
      segments: @[
        Segment(startT: UnixTime(1), endT: UnixTime(2)),
        Segment(startT: UnixTime(10), endT: UnixTime(11)),
      ],
    )
    let p = routeParts(routeWkb(a).get)
    check p.len == 2
    check p[0].lons == @[1.5, 1.6] and p[0].lats == @[2.5, 2.6]
    check p[1].lons == @[3.0, 3.1] and p[1].lats == @[4.0, 4.1]
    check routeParts("").len == 0 and routeParts("nonsense bytes").len == 0
    check routeParts(routeWkb(a).get[0 ..< 30]).len < 2 # (cut short: no crash)
  test "the bytes are the standard ones: byte order, type, counts, then longitude and latitude as doubles":
    let a = ActivityData(
      coords: @[coord(1, 1.0, 2.0), coord(2, 3.0, 4.0)],
      segments: @[Segment(startT: UnixTime(1), endT: UnixTime(2))],
    )
    let w = routeWkb(a).get
    check w.len == 9 + 9 + 2 * 16
    check w[0 .. 8] == "\x01\x05\x00\x00\x00\x01\x00\x00\x00"
      # little endian, multilinestring, 1 line
    check w[9 .. 17] == "\x01\x02\x00\x00\x00\x02\x00\x00\x00"
      # little endian, linestring, 2 points
    check w[18 .. 25] == "\x00\x00\x00\x00\x00\x00\xf0\x3f"
      # 1.0 as an IEEE double, least significant byte first
    check w[34 .. 41] == "\x00\x00\x00\x00\x00\x00\x08\x40" # 3.0

  test "a segment with fewer than two points leaves no part":
    let a = ActivityData(
      coords: @[coord(1, 1.0, 2.0), coord(5, 3.0, 4.0), coord(6, 3.5, 4.5)],
      segments: @[
        Segment(startT: UnixTime(1), endT: UnixTime(1)),
        Segment(startT: UnixTime(5), endT: UnixTime(6)),
      ],
    )
    check routeWkb(a).get.lines == @[@[(3.0, 4.0), (3.5, 4.5)]]

  test "no part at all, no route":
    check routeWkb(ActivityData()).isNone
    check routeWkb(
      ActivityData(
        coords: @[coord(1, 1.0, 2.0)],
        segments: @[Segment(startT: UnixTime(1), endT: UnixTime(1))],
      )
    ).isNone

  test "negative coordinates, and every digit of them":
    let a = ActivityData(
      coords: @[coord(1, -9.14159265358979, 38.72), coord(2, -9.1, 38.75)],
      segments: @[Segment(startT: UnixTime(1), endT: UnixTime(2))],
    )
    check routeWkb(a).get.lines == @[@[(-9.14159265358979, 38.72), (-9.1, 38.75)]]

  test "coordinates before the first segment are left out":
    let a = ActivityData(
      coords: @[coord(1, 9.0, 9.0), coord(5, 3.0, 4.0), coord(6, 3.5, 4.5)],
      segments: @[Segment(startT: UnixTime(5), endT: UnixTime(6))],
    )
    check routeWkb(a).get.lines == @[@[(3.0, 4.0), (3.5, 4.5)]]

suite "route: in the database":
  let dir = getTempDir() / "nch-test-route"

  proc store(name: string): Store =
    removeDir(dir / name)
    openStore(dir / name / "x.db", allFragments)

  test "SpatiaLite is there: a route can be stored and asked how far it is":
    let s = store("sp")
    defer:
      s.close()
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (1, 'f', 'x', 0)"
    )
    s.db.execute(
      "insert into activity(file_id, session, start_t, end_t) values (1, 0, 0, 10)"
    )
    s.db.execute(
      """insert into route(activity_id, geom) values (1,
      GeomFromText('MULTILINESTRING((-9.14 38.72, -9.10 38.75, -9.00 38.80))', 4326))"""
    )
    let metres = s.db.scalar(
      float,
      """select ST_Distance(geom,
      MakePoint(-9.13, 38.73, 4326), 1) from route""",
    )
    check metres > 150 and metres < 250 # (206 m)

  test "the bytes go in through SpatiaLite and come out as the same route":
    let s = store("wkb")
    defer:
      s.close()
    let a = ActivityData(
      coords: @[
        coord(1, -9.14, 38.72),
        coord(2, -9.10, 38.75),
        coord(3, -9.00, 38.80),
        coord(10, 2.35, 48.85),
        coord(11, 2.40, 48.90),
      ],
      segments: @[
        Segment(startT: UnixTime(1), endT: UnixTime(3)),
        Segment(startT: UnixTime(10), endT: UnixTime(11)),
      ],
    )
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (1, 'f', 'x', 0)"
    )
    s.db.execute(
      "insert into activity(file_id, session, start_t, end_t) values (1, 0, 0, 20)"
    )
    let st = prepareStmt(
      s.db, "insert into route(activity_id, geom) values (?, GeomFromWKB(?, 4326))"
    )
    st.bindInt(1, 1)
    st.bindBlob(2, routeWkb(a).get)
    st.run()
    check s.db.scalar(int, "select NumGeometries(geom) from route") == 2
    check s.db.scalar(int, "select ST_NPoints(geom) from route") == 5
    check s.db.scalar(int, "select SRID(geom) from route") == 4326
    check s.db.scalar(string, "select GeometryType(geom) from route") ==
      "MULTILINESTRING"
    check s.db.scalar(
      string,
      "select ST_X(ST_PointN(ST_GeometryN(geom, 2), 2)) || ',' || ST_Y(ST_PointN(ST_GeometryN(geom, 2), 2)) from route",
    ) == "2.4,48.9"
    check s.db.scalar(int, "select count(*) from idx_route_geom") == 1
      # (and it is indexed)
    let km = s.db.scalar(float, "select GeodesicLength(geom) from route") / 1000
    check km > 18 and km < 26 # about 15 km near Lisbon and 7 km in Paris

  test "deleting the user takes the route and its index entry too":
    let s = store("cascade")
    defer:
      s.close()
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (1, 'f', 'x', 0)"
    )
    s.db.execute(
      "insert into activity(file_id, session, start_t, end_t) values (1, 0, 0, 10)"
    )
    s.db.execute(
      """insert into route(activity_id, geom) values (1,
      GeomFromText('MULTILINESTRING((-9.14 38.72, -9.10 38.75))', 4326))"""
    )
    check s.db.scalar(int, "select count(*) from idx_route_geom") == 1
    s.db.execute("delete from user where id = 1")
    check s.db.scalar(int, "select count(*) from route") == 0
    check s.db.scalar(int, "select count(*) from idx_route_geom") == 0
