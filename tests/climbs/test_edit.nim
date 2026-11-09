import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/climbs/[command, edit, ordinal, report]
import nimchoo/db/[statement, store]
import nimchoo/errors
import nimchoo/modules

let dir = getTempDir() / "nch-test-climbs-edit"

proc fresh(name: string, climbs: openArray[(string, float)]): string =
  ## A database with sectors: (name, gain), "" for none; named ones are marked as looked at.
  removeDir(dir / name)
  createDir(dir / name)
  result = dir / name / "x.db"
  let s = openStore(result, allFragments)
  defer:
    s.close()
  for (n, gain) in climbs:
    s.db.exec(
      sql"""insert into sector(length_m, gain_m, gradient, name, route)
      values (2000, ?, 5, ?, GeomFromText('LINESTRING Z(-70 -33 100, -70.01 -33 200)', 4326))""",
      gain,
      n,
    )
    assignNumber(s, lastInsertId(s.db))
      # (the number a climb gets when it is named: in the order made)

proc climbs(db: string, args: varargs[string]): int =
  command.run(Globals(dbPath: db, fragments: allFragments, offline: true), @args)

proc q(db, sqlText: string): string =
  let s = openStore(db, allFragments)
  defer:
    s.close()
  s.db.getValue(sql(sqlText))

proc shown(db: string): seq[string] =
  let s = openStore(db, allFragments)
  defer:
    s.close()
  for r in allSectors(s):
    result.add r.name

suite "nch climbs: names, and the list of all":
  test "listing, and nothing to list":
    let empty = fresh("none", [])
    check climbs(empty, "--all") == exitOk
    let db =
      fresh("list", [("Farellones", 300.0), ("Cuesta", 100.0), ("cuesta", 200.0)])
    check climbs(db, "--all") == exitOk
    check shown(db) == @["Farellones", "cuesta₂", "Cuesta₁"]
    let s = openStore(db, allFragments)
    defer:
      s.close()
    check sectorLines(allSectors(s))[0].startsWith("climb")
    check sectorLines(allSectors(s)).len == 4
    check climbs(db) == exitOk # (nothing selected: said, not an error)
  test "rename by the name as shown; the group closes up; the name is kept":
    let db =
      fresh("rename", [("Cuesta", 100.0), ("Cuesta", 200.0), ("Farellones", 300.0)])
    check shown(db) == @["Farellones", "Cuesta₂", "Cuesta₁"]
    check climbs(db, "--edit", "cuesta₁", "--rename", "Old road") == exitOk
      # (case does not matter)
    check q(db, "select name from sector where id = 1") == "Old road"
    check q(db, "select manual from sector where id = 1") == "1"
    check shown(db) == @["Farellones", "Cuesta", "Old road"]
  test "names that differ only in accents or capitals are one group, with the number kept":
    let db = fresh("accents", [("Ñuñoa", 100.0), ("ñuñoa", 200.0), ("Nunoa", 300.0)])
    check shown(db) == @["Nunoa₃", "ñuñoa₂", "Ñuñoa₁"]
    check climbs(db, "--edit", "ÑUÑOA₂", "--rename", "Other") == exitOk
    check q(db, "select name from sector where id = 2") == "Other"
  test "a shared name needs its number; a name that is not there is an error; nothing changes":
    let db = fresh("errors", [("Cuesta", 100.0), ("Cuesta", 200.0)])
    check climbs(db, "--edit", "Cuesta", "--rename", "X") == exitFailure
    check climbs(db, "--edit", "Nowhere", "--rename", "X") == exitFailure
    check q(db, "select count(*) from sector where manual = 1") == "0"
    let s = openStore(db, allFragments)
    defer:
      s.close()
    expect StoreError:
      discard findShown(s, "Cuesta")
    check findShown(s, "Cuesta₁") == 1 and findShown(s, "cuesta 2") == 2 and
      findShown(s, "CUESTA1") == 1 # (typed any way)
  test "a name that looks numbered is refused":
    let db = fresh("numbered", [("Cuesta", 100.0)])
    check climbs(db, "--edit", "Cuesta", "--rename", "Cuesta₂") == exitUsage
    check q(db, "select name from sector") == "Cuesta"
  test "--auto hands the climb back to the program":
    let db = fresh("auto", [("Cuesta", 100.0)])
    check climbs(db, "--edit", "Cuesta", "--rename", "Mine") == exitOk
    check q(db, "select manual from sector") == "1"
    check climbs(db, "--edit", "Mine", "--auto") == exitOk
    check q(db, "select coalesce(name, '-') from sector") == ""
      # (named again at once: offline, nothing)
    check q(db, "select manual from sector") == "0"
  test "--user is allowed (it says whose selection and whose best time); the changes are shared":
    let db = fresh("user", [("Cuesta", 100.0)])
    check command.run(
      Globals(dbPath: db, user: "default", fragments: allFragments, offline: true),
      @["--all"],
    ) == exitOk
    check command.run(
      Globals(dbPath: db, user: "default", fragments: allFragments, offline: true),
      @["--edit", "Cuesta", "--rename", "Mine"],
    ) == exitOk
  test "a manual name survives the program's naming":
    let db = fresh("survive", [("", 100.0)])
    check climbs(db, "--edit", "unnamed", "--rename", "Mine") == exitOk
    check q(db, "select count(*) from sector where name is null") == "0"
      # (nothing left for the program)

suite "nch climbs: retiring":
  test "a retired climb is hidden from the list but keeps its place in the numbering; unretire shows it again":
    let db = fresh(
      "retire",
      [("Cuesta", 100.0), ("Cuesta", 200.0), ("Cuesta", 300.0), ("Farellones", 400.0)],
    )
    check shown(db) == @["Farellones", "Cuesta₃", "Cuesta₂", "Cuesta₁"]
    check climbs(db, "--edit", "Cuesta₂", "--retire") == exitOk
    check shown(db) ==
      @["Farellones", "Cuesta₃", "Cuesta₁"] # (the gap shows: no ₂)
    check q(db, "select retired from sector where id = 2") == "1"
    check q(db, "select count(*) from sector") == "4" # nothing is deleted
    let s = openStore(db, allFragments)
    defer:
      s.close()
    check allSectors(s, retired = true)[0].name == "Cuesta₂"
    check allSectors(s, retired = true).len == 1 and countRetired(s) == 1
    check findShown(s, "Cuesta₂") == 2 # (it can still be found by its name)
    check climbs(db, "--retired") == exitOk
    check climbs(db, "--edit", "cuesta₂", "--unretire") == exitOk
    check shown(db) == @["Farellones", "Cuesta₃", "Cuesta₂", "Cuesta₁"]
  test "the duplicates report runs; an unknown climb is a failure":
    let db = fresh("dupscmd", [("Cuesta", 100.0), ("Farellones", 400.0)])
    check climbs(db, "--duplicates") == exitOk
    check climbs(db, "--edit", "Nowhere", "--retire") == exitFailure
