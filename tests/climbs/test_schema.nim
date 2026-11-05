import std/[os, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/modules
import ../support/userdata

let dir = getTempDir() / "nch-test-climbs-schema"

proc fresh(name: string): Store =
  removeDir(dir / name)
  openStore(dir / name / "x.db", allFragments)

suite "climbs: the tables":
  test "a sector has a route with altitude and a spatial index":
    let s = fresh("route")
    defer: s.close()
    s.db.exec(sql"""insert into sector(length_m, gain_m, gradient, category, found_at, route)
                    values (2960, 118.4, 4.0, '4', 1000000,
                            GeomFromText('LINESTRING Z(10 20 100, 10.01 20 105, 10.02 20 110)', 4326))""")
    check s.db.getValue(sql"select NumPoints(route) from sector") == "3"
    check s.db.getValue(sql"select ST_Z(PointN(route, 3)) from sector") == "110.0"
    check s.db.getValue(sql"select count(*) from pragma_table_info('sector') where name = 'kind'") == "0"        # (dropped, never used)
    # the spatial index finds it by a box
    check s.db.getValue(sql"""select count(*) from sector where id in (select ROWID from SpatialIndex
        where f_table_name = 'sector' and f_geometry_column = 'route' and
              search_frame = BuildMbr(9.9, 19.9, 10.1, 20.1))""") == "1"
    check s.db.getValue(sql"""select count(*) from sector where id in (select ROWID from SpatialIndex
        where f_table_name = 'sector' and f_geometry_column = 'route' and
              search_frame = BuildMbr(50, 50, 51, 51))""") == "0"

  test "a sector has a name, unset, and has not been looked at":
    let s = fresh("name")
    defer: s.close()
    s.db.exec(sql"insert into sector(length_m, gain_m, gradient) values (1000, 50, 5)")
    check s.db.getValue(sql"select name_checked from sector") == "0"
    check s.db.getValue(sql"select count(*) from sector where name is null") == "1"
    s.db.exec(sql"update sector set name = 'Cerro Calan', name_checked = 1")
    check s.db.getValue(sql"select name from sector") == "Cerro Calan"

  test "a sector is not manual until it is made so":
    let s = fresh("manual")
    defer: s.close()
    s.db.exec(sql"insert into sector(length_m, gain_m, gradient) values (1000, 50, 5)")
    check s.db.getValue(sql"select manual from sector") == "0"
    s.db.exec(sql"update sector set name = 'Mi cerro', manual = 1")
    check s.db.getValue(sql"select manual from sector") == "1"

  test "a database made before the rules changed has its automatic names forgotten, to be made again":
    let top = getTempDir() / "nch-test-climbs-migration"
    removeDir(top)
    var before: seq[Fragment]
    for f in allFragments:
      if f.name notin ["climbs/003-names.sql", "climbs/004-no-kind.sql"]: before.add f
    let old = openStore(top / "x.db", before)
    old.db.exec(sql"insert into sector(length_m, gain_m, gradient, name, name_checked) values (1000, 50, 5, 'near La Florida', 1)")
    old.db.exec(sql"insert into sector(length_m, gain_m, gradient, name, name_checked) values (2000, 90, 4, 'Cerro Calan', 1)")
    old.close()
    let now = openStore(top / "x.db", allFragments)
    defer: now.close()
    check now.count("sector") == 2                                   # (the climbs themselves stay)
    check now.db.getValue(sql"select count(*) from sector where name is null and name_checked = 0 and manual = 0") == "2"
    # and it is done once: names given afterwards are kept the next time the database is opened
    now.db.exec(sql"update sector set name = 'Cerro Calan', name_checked = 1 where id = 2")
    now.close()
    let again = openStore(top / "x.db", allFragments)
    defer: again.close()
    check again.db.getValue(sql"select name from sector where id = 2") == "Cerro Calan"

  test "efforts go with their ride or with their sector, and the sector stays when the ride goes":
    let s = fresh("cascade")
    defer: s.close()
    fill(s, "mine")                          # a file, an activity, ...
    s.db.exec(sql"insert into sector(length_m, gain_m, gradient) values (1000, 50, 5)")
    s.db.exec(sql"insert into sector(length_m, gain_m, gradient) values (2000, 100, 5)")
    let a = s.db.getValue(sql"select id from activity")
    for sector in [1, 2]:
      s.db.exec(sql"insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m) values (?, ?, 10.5, 70.5, 60, 100)", sector, a)
    s.db.exec(sql"insert into climbs_done(activity_id, version) values (?, 1)", a)
    check s.count("effort") == 2 and s.count("climbs_done") == 1
    s.db.exec(sql"delete from sector where id = 2")
    check s.count("effort") == 1                      # the sector's efforts go with it
    s.db.exec(sql"delete from file")                  # the ride goes (file, then activity, then what refers to it)
    check s.count("effort") == 0 and s.count("climbs_done") == 0
    check s.count("sector") == 1                      # ... and the sector stays

  test "a lap is another effort; the same pass is not recorded twice":
    let s = fresh("laps")
    defer: s.close()
    fill(s, "mine")
    s.db.exec(sql"insert into sector(length_m, gain_m, gradient) values (1000, 50, 5)")
    let a = s.db.getValue(sql"select id from activity")
    s.db.exec(sql"insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m) values (1, ?, 10.5, 70.5, 60, 100)", a)
    s.db.exec(sql"insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m) values (1, ?, 900.5, 960.5, 60, 4100)", a)
    check s.count("effort") == 2
    expect DbError:
      s.db.exec(sql"insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m) values (1, ?, 10.5, 71, 60.5, 100)", a)
