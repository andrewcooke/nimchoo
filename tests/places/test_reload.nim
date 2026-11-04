import std/[os, strutils, unittest]
import db_connector/db_sqlite
import ../support/env
import nimchoo/cache
import nimchoo/db/store
import nimchoo/errors
import nimchoo/modules
import nimchoo/places/data

let dir = getTempDir() / "nch-test-places-reload"

let listFile = if defined(nchSmallPlaces): "cities-test.tsv" else: "cities.tsv.gz"

proc fresh(name: string): tuple[top, db: string] =
  removeDir(dir / name)
  createDir(dir / name)
  putEnv("NCH_CACHE", dir / name / "cache")
  (dir / name / "cache", dir / name / "x.db")

proc count(s: Store, table: string): int = parseInt(s.db.getValue(sql("select count(*) from " & table)))

proc addActivity(s: Store, tag: string, lon, lat: float) =
  s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)", s.userId, tag, tag)
  let f = s.db.getValue(sql"select max(id) from file")
  s.db.exec(sql"insert into activity(file_id, session, start_t, end_t) values (?, 0, 1000, 1100)", f)
  let a = s.db.getValue(sql"select max(id) from activity")
  s.db.exec(sql("update activity set start = MakePoint(" & $lon & ", " & $lat & ", 4326) where id = " & a))

suite "places: a changed list is loaded without destroying anything":
  teardown: useTestCache()
  test "the database remembers which list it was made from, and opening again changes nothing":
    let (top, db) = fresh("same")
    let a = openStore(db, allFragments)
    check a.db.getValue(sql"select seed_version from fragment where name = 'places/001-schema.sql'") == placesVersion()
    let ids = a.db.getValue(sql"select group_concat(id) from (select id from place order by id limit 5)")
    a.close()
    let b = openStore(db, allFragments)
    check b.db.getValue(sql"select group_concat(id) from (select id from place order by id limit 5)") == ids   # (not reloaded)
    b.close()
  test "another list in system/: the places are replaced, the activities are pointed at the new nearest":
    let (top, db) = fresh("other")
    let a = openStore(db, allFragments)
    a.addActivity("here", 11.4, 11.4)
    a.addActivity("nowhere-in-particular", 100.0, -40.0)
    a.db.exec(sql"insert into activity(file_id, session, start_t, end_t) select file_id, 1, 1000, 1100 from activity limit 1")  # (no start)
    check a.count("place") == carriedPlaces().len
    a.close()
    writeFile(systemDir(top) / listFile, "Alpha\tZZ\t10.0\t10.0\t5000\nBeta\tZZ\t11.5\t11.5\t7000\nGamma\tZZ\t-40.0\t100.0\t9000\n")
    let b = openStore(db, allFragments)
    defer: b.close()
    check b.count("place") == 3
    check b.db.getValue(sql"select count(*) from idx_place_geom") == "3"          # (the spatial index is made again)
    check b.db.getValue(sql"select p.name from activity a join place p on p.id = a.place_id join file f on f.id = a.file_id where f.name = 'here'") == "Beta"
    check b.db.getValue(sql"select p.name from activity a join place p on p.id = a.place_id join file f on f.id = a.file_id where f.name = 'nowhere-in-particular'") == "Gamma"
    check b.db.getValue(sql"select count(*) from activity where start is null and place_id is not null") == "0"
    check b.count("activity") == 3 and b.count("file") == 2                      # (nothing else touched)
    check b.db.getValue(sql"select seed_version from fragment where name = 'places/001-schema.sql'") == placesVersion()
  test "back to the program's own list: loaded again":
    let (top, db) = fresh("back")
    openStore(db, allFragments).close()
    writeFile(systemDir(top) / listFile, "Alpha\tZZ\t10.0\t10.0\t5000\n")
    let a = openStore(db, allFragments)
    check a.count("place") == 1
    a.close()
    removeFile(systemDir(top) / listFile)                 # unpacked again, the program's own
    let b = openStore(db, allFragments)
    check b.count("place") == carriedPlaces().len and b.count("place") > 1
    b.close()
  test "a list that cannot be read: the database is refused with the reason, and is as it was":
    let (top, db) = fresh("bad")
    let a = openStore(db, allFragments)
    let n = a.count("place")
    a.close()
    writeFile(systemDir(top) / listFile, "this is not a list of places")
    try:
      openStore(db, allFragments).close()
      check false
    except StoreError as e:
      check "replacing the data of places/001-schema.sql" in e.msg and (top / "system" / listFile) in e.msg
    removeFile(systemDir(top) / listFile)
    let c = openStore(db, allFragments)
    check c.count("place") == n
    c.close()
  test "a database from before the list left the checksum is accepted and brought up to date":
    let (top, db) = fresh("legacy")
    let a = openStore(db, allFragments)
    var places: Fragment
    for f in allFragments:
      if f.name == "places/001-schema.sql": places = f
    a.db.exec(sql"update fragment set sha256 = ?, seed_version = null where name = 'places/001-schema.sql'", places.legacySums[0])
    let n = a.count("place")
    let id = a.db.getValue(sql"select min(id) from place")
    a.close()
    let b = openStore(db, allFragments)                    # accepted ...
    check b.db.getValue(sql"select sha256 from fragment where name = 'places/001-schema.sql'") == places.checksum
    check b.db.getValue(sql"select seed_version from fragment where name = 'places/001-schema.sql'") == placesVersion()
    check b.count("place") == n
    when not defined(nchSmallPlaces):
      # (the program's own list is the one the legacy database is taken to have: nothing to reload; the
      # short list of the test builds has no such version, so there it is loaded again)
      check b.db.getValue(sql"select min(id) from place") == id
    b.close()
