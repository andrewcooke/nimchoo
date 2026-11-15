## The identity of a database and the counter of each table (db/versions.nim).

import std/[os, sequtils, strutils, unittest]
import nimchoo/packages/db/[access, statement, store, versions]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess

let dir = getTempDir() / "nch-test-versions"

proc open(name: string): Session =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  openSession(path, allFragments, access = allAccess)

proc version(s: Session, table: string): int64 =
  s.db.scalar(
    int64, "select version from table_version where name = :name", name = table
  )

suite "versions: the identity of a database":
  test "a new database has one, and no two are alike":
    let a = open("ida")
    let b = open("idb")
    defer:
      a.close()
      b.close()
    check databaseIdentity(a.db).len == 32
    check databaseIdentity(a.db).allIt(it in HexDigits and it notin {'A' .. 'F'})
    check databaseIdentity(a.db) != databaseIdentity(b.db)
  test "it stays when the database is opened again":
    let a = open("idagain")
    let id = databaseIdentity(a.db)
    a.close()
    let b = openSession(dir / "idagain.db", allFragments, access = allAccess)
    defer:
      b.close()
    check databaseIdentity(b.db) == id

suite "versions: a counter for each table":
  test "every table a package owns has a counter and its three triggers (so that a new table cannot be missed)":
    let s = open("every")
    defer:
      s.close()
    let tables = countedTables(s.db, baseFragments & allFragments)
    check tables.len > 10
    for t in tables:
      check s.db.scalar(
        int, "select count(*) from table_version where name = :name", name = t
      ) == 1
      for event in ["i", "u", "d"]:
        check s.db.scalar(
          int,
          "select count(*) from sqlite_master where type = 'trigger' and name = :name",
          name = "tv_" & t & "_" & event,
        ) == 1
    # and nothing else has one: the counters and the identity are not counted, and neither is SpatiaLite's own
    check s.db.scalar(int, "select count(*) from table_version") == tables.len
    check "table_version" notin tables and "database_identity" notin tables
  test "an insert, an update and a delete each change the counter":
    let s = open("changes")
    defer:
      s.close()
    let start = s.version("ff_model")
    s.db.execute(
      "insert into ff_model(name, gamma, zero, one, max_secs, zone1, zone2, zone3, zone4, zone5, fitness_days, fatigue_days) values ('x', 2, 1, 6, 60, 68, 83, 94, 105, 121, 42, 7)"
    )
    check s.version("ff_model") == start + 1
    s.db.execute("update ff_model set gamma = 3 where name = 'x'")
    check s.version("ff_model") == start + 2
    s.db.execute("update ff_model set gamma = 3 where name = 'nobody'")
    check s.version("ff_model") == start + 2 # (no row: nothing changed)
    s.db.execute("delete from ff_model where name = 'x'")
    check s.version("ff_model") == start + 3
  test "other tables are not touched; a cascade counts for the table it deletes from":
    let s = open("cascade")
    defer:
      s.close()
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, 'a', 'aa', 0)",
      userId = s.userId,
    )
    s.db.execute(
      "insert into activity(file_id, session, start_t, end_t) values (1, 0, 0, 1)"
    )
    s.db.execute(
      "insert into selection(user_id, activity_id) values (:userId, 1)",
      userId = s.userId,
    )
    let selection = s.version("selection")
    let activity = s.version("activity")
    s.db.execute("delete from activity")
    check s.version("selection") == selection + 1 # (the cascade)
    check s.version("activity") == activity + 1
  test "a database made before a table existed gets its counter when it is opened":
    let s = open("late")
    s.db.execute("drop trigger tv_ff_model_u")
    s.db.execute("delete from table_version where name = 'ff_model'")
    s.close()
    let t = openSession(dir / "late.db", allFragments, access = allAccess)
    defer:
      t.close()
    check t.version("ff_model") == 0
    check t.db.scalar(
      int, "select count(*) from sqlite_master where name = 'tv_ff_model_u'"
    ) == 1

suite "versions: tableVersions":
  test "sorted, each once":
    let s = open("sorted")
    defer:
      s.close()
    let v = tableVersions(s.db, @["selection", "activity", "selection"])
    check v.mapIt(it[0]) == @["activity", "selection"]
  test "a table with no counter is a bug, not an empty list":
    let s = open("nocounter")
    defer:
      s.close()
    expect AssertionDefect:
      discard tableVersions(s.db, @["nonesuch"])

suite "versions: the tables read are recorded (a test of what a view declares)":
  test "the authorizer sees each table, once; what is not recorded is not noted":
    let s = open("record")
    defer:
      s.close()
    startRecording()
    discard s.db.scalar(int, "select count(*) from selection")
    discard s.db.query(
      int64,
      "select a.id from activity a join file f on f.id = a.file_id where f.user_id = :userId",
      userId = s.userId,
    )
    check stopRecording() == @["activity", "file", "selection"]
    check s.db.scalar(int, "select count(*) from file") == 0
    check stopRecording().len == 0 # (not recording: nothing)
  test "recording starts empty":
    let s = open("recordempty")
    defer:
      s.close()
    startRecording()
    discard s.db.scalar(int, "select count(*) from user")
    discard stopRecording()
    startRecording()
    check stopRecording().len == 0
