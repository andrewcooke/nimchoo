import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/climbs/report
import nimchoo/db/store
import nimchoo/errors
import nimchoo/modules
import nimchoo/sector/[command, edit]

let dir = getTempDir() / "nch-test-sector"

proc fresh(name: string, climbs: openArray[(string, float)]): string =
  ## A database with sectors: (name, gain), "" for none; named ones are marked as looked at.
  removeDir(dir / name)
  createDir(dir / name)
  result = dir / name / "x.db"
  let s = openStore(result, allFragments)
  defer: s.close()
  for (n, gain) in climbs:
    s.db.exec(sql"""insert into sector(length_m, gain_m, gradient, name, route)
      values (2000, ?, 5, ?, GeomFromText('LINESTRING Z(-70 -33 100, -70.01 -33 200)', 4326))""",
              gain, n)

proc sector(db: string, args: varargs[string]): int =
  command.run(Globals(dbPath: db, fragments: allFragments, offline: true), @args)

proc q(db, sqlText: string): string =
  let s = openStore(db, allFragments)
  defer: s.close()
  s.db.getValue(sql(sqlText))

proc shown(db: string): seq[string] =
  let s = openStore(db, allFragments)
  defer: s.close()
  for r in allSectors(s): result.add r.name

suite "nch sector":
  test "listing, and nothing to list":
    let empty = fresh("none", [])
    check sector(empty) == exitOk
    let db = fresh("list", [("Farellones", 300.0), ("Cuesta", 100.0), ("cuesta", 200.0)])
    check sector(db) == exitOk
    check shown(db) == @["Farellones", "cuesta (1/2)", "Cuesta (2/2)"]
    let s = openStore(db, allFragments)
    defer: s.close()
    check catalogueLines(allSectors(s))[0].startsWith("climb")
    check catalogueLines(allSectors(s)).len == 4
  test "rename by the name as shown; the group closes up; the name is kept":
    let db = fresh("rename", [("Cuesta", 100.0), ("Cuesta", 200.0), ("Farellones", 300.0)])
    check shown(db) == @["Farellones", "Cuesta (1/2)", "Cuesta (2/2)"]
    check sector(db, "--edit", "cuesta (2/2)", "--rename", "Old road") == exitOk        # (case does not matter)
    check q(db, "select name from sector where id = 1") == "Old road"
    check q(db, "select manual from sector where id = 1") == "1"
    check shown(db) == @["Farellones", "Cuesta", "Old road"]
  test "a shared name needs its number; a name that is not there is an error; nothing changes":
    let db = fresh("errors", [("Cuesta", 100.0), ("Cuesta", 200.0)])
    check sector(db, "--edit", "Cuesta", "--rename", "X") == exitFailure
    check sector(db, "--edit", "Nowhere", "--rename", "X") == exitFailure
    check q(db, "select count(*) from sector where manual = 1") == "0"
    let s = openStore(db, allFragments)
    defer: s.close()
    expect StoreError: discard findShown(s, "Cuesta")
    check findShown(s, "Cuesta (1/2)") == 2
  test "a name that looks numbered is refused":
    let db = fresh("numbered", [("Cuesta", 100.0)])
    check sector(db, "--edit", "Cuesta", "--rename", "Cuesta (2/3)") == exitUsage
    check q(db, "select name from sector") == "Cuesta"
  test "--auto hands the climb back to the program":
    let db = fresh("auto", [("Cuesta", 100.0)])
    check sector(db, "--edit", "Cuesta", "--rename", "Mine") == exitOk
    check q(db, "select manual from sector") == "1"
    check sector(db, "--edit", "Mine", "--auto") == exitOk
    check q(db, "select coalesce(name, '-') from sector") == ""          # (named again at once: offline, nothing)
    check q(db, "select manual from sector") == "0"
  test "--user before the command is refused":
    let db = fresh("user", [("Cuesta", 100.0)])
    check command.run(Globals(dbPath: db, user: "default", fragments: allFragments), @[]) == exitUsage
  test "a manual name survives the program's naming":
    let db = fresh("survive", [("", 100.0)])
    check sector(db, "--edit", "unnamed", "--rename", "Mine") == exitOk
    check q(db, "select count(*) from sector where name is null") == "0"        # (nothing left for the program)
