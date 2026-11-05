import std/[os, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/modules

suite "places: the table is kept empty":
  test "a new database has the table and no places":
    let s = openStore(":memory:", allFragments)
    defer: s.close()
    check s.db.getValue(sql"select count(*) from sqlite_master where name = 'place'") == "1"
    check s.db.getValue(sql"select count(*) from place") == "0"
  test "a database that still has the list loses it the next time it is opened":
    let top = getTempDir() / "nch-test-places-empty"
    removeDir(top)
    var before: seq[Fragment]
    for f in allFragments:
      if f.name != "places/002-empty.sql": before.add f
    let old = openStore(top / "x.db", before)
    old.db.exec(sql"insert into place(name, country, population, source, geom) values ('Santiago', 'CL', 1, 'geonames', MakePoint(-70.6, -33.4, 4326))")
    check old.db.getValue(sql"select count(*) from place") == "1"
    old.close()
    let now = openStore(top / "x.db", allFragments)
    defer: now.close()
    check now.db.getValue(sql"select count(*) from place") == "0"
