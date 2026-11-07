import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/landmark/command as landmarkCommand
import nimchoo/modules

let dir = getTempDir() / "nch-test-landmark-cmd"

proc fresh(name: string): string =
  removeDir(dir / name)
  createDir(dir / name)
  let db = dir / name / "x.db"
  let s = openStore(db, allFragments)
  defer:
    s.close()
  s.db.exec(sql"insert into country(iso, name, geoname_id) values ('CL', 'Chile', 1)")
  for (id, name, cls, code, lon, lat) in [
    (1, "Estero de la Yerba Loca", "H", "STM", -70.364, -33.344),
    (2, "Cerro Yerba Loca", "T", "MT", -70.6, -29.7),
  ]:
    s.db.exec(
      sql"insert into feature(id, country, name, class, code, population, geom) values (?, 'CL', ?, ?, ?, 0, MakePoint(cast(? as real), cast(? as real), 4326))",
      id,
      name,
      cls,
      code,
      lon,
      lat,
    )
  db

proc landmark(db: string, args: varargs[string]): int =
  landmarkCommand.run(
    Globals(dbPath: db, fragments: allFragments, offline: true), @args
  )

proc q(db, sqlText: string): string =
  let s = openStore(db, allFragments)
  defer:
    s.close()
  s.db.getValue(sql(sqlText))

suite "nch landmarks":
  test "listing, with nothing and with something":
    let db = fresh("list")
    check landmark(db) == exitOk
    check landmark(db, "--add", "Casa", "--at", "-70.6,-33.4") == exitOk
    check landmark(db) == exitOk
    check q(db, "select name from landmark") == "Casa"
    check q(db, "select radius_m from landmark") == "1000.0"
  test "a suggestion by name is picked by its number":
    let db = fresh("pick")
    check landmark(db, "--search", "yerba") == exitOk
    # both are 0 population; by name: "Cerro Yerba Loca" is 1, "Estero de la Yerba Loca" is 2
    check landmark(
      db, "--add", "Yerba Loca", "--search", "yerba", "--pick", "2", "--radius", "1500"
    ) == exitOk
    check q(db, "select name from landmark") == "Yerba Loca"
    check abs(parseFloat(q(db, "select lon from landmark")) + 70.364) < 1e-9
    check q(db, "select radius_m from landmark") == "1500.0"
  test "a number that is not among the suggestions, and a name used twice, are failures; nothing is made":
    let db = fresh("fail")
    check landmark(db, "--add", "X", "--search", "yerba", "--pick", "9") == exitFailure
    check landmark(db, "--add", "Casa", "--at", "1,1") == exitOk
    check landmark(db, "--add", "casa", "--at", "2,2") == exitFailure
    check q(db, "select count(*) from landmark") == "1"
  test "suggestions round a position (offline: from the names already loaded)":
    let db = fresh("near")
    check landmark(db, "--near", "-70.364,-33.344") == exitOk
    check landmark(
      db, "--add", "Yerba Loca", "--near", "-70.364,-33.344", "--pick", "1"
    ) == exitOk
    check q(db, "select count(*) from landmark") == "1"
  test "removing":
    let db = fresh("remove")
    check landmark(db, "--add", "Casa", "--at", "1,1") == exitOk
    check landmark(db, "--delete", "nothing", "-f") == exitFailure
    check landmark(db, "--delete", "casa") == exitFailure # (without -f nothing is done)
    check q(db, "select count(*) from landmark") == "1"
    check landmark(db, "--delete", "casa", "-f") == exitOk
    check q(db, "select count(*) from landmark") == "0"
  test "bad arguments are a usage error; --user before the command is refused":
    let db = fresh("usage")
    check landmark(db, "--add", "X") == exitUsage
    check landmark(db, "--pick", "1") == exitUsage
    check landmarkCommand.run(
      Globals(dbPath: db, user: "default", fragments: allFragments), @[]
    ) == exitUsage
