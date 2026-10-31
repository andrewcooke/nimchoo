import std/[options, os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/[migrations, statement, store]
import nimchoo/errors

let dir = getTempDir() / "nch-test-db"

proc tempDb(name: string): string =
  createDir(dir)
  result = dir / name & ".db"
  removeFile(result)

proc count(s: Store, table: string): int =
  parseInt(s.db.getValue(sql("select count(*) from " & table)))

suite "database: opening and migrating":
  test "a new database has the schema and the default user":
    let path = tempDb("new")
    let s = openStore(path)
    check fileExists(path)
    check s.userName == defaultUser
    check s.userId > 0
    for table in ["user", "file", "activity", "coords"]:
      check s.db.getValue(sql"select count(*) from sqlite_master where name = ?",
                          table) == "1"
    check s.db.getValue(sql"pragma user_version") == $allMigrations.len
    check s.count("user") == 1
    s.close()

  test "opening again changes nothing":
    let path = tempDb("again")
    let a = openStore(path)
    let id = a.userId
    a.close()
    let b = openStore(path)
    check b.userId == id
    check b.count("user") == 1
    check b.db.getValue(sql"pragma user_version") == $allMigrations.len
    b.close()

  test "the directory is created":
    let path = dir / "sub" / "deeper" / "x.db"
    removeDir(dir / "sub")
    openStore(path).close()
    check fileExists(path)
    removeDir(dir / "sub")

  test "an in-memory database":
    let s = openStore(":memory:")
    check s.count("user") == 1
    s.close()

  test "another user":
    let path = tempDb("users")
    let a = openStore(path)
    a.db.exec(sql"insert into user(name) values ('bob')")
    a.close()
    let b = openStore(path, "bob")
    check b.userName == "bob"
    check b.userId > 1
    b.close()

  test "an unknown user is an error, and leaves the database usable":
    let path = tempDb("nouser")
    openStore(path).close()
    expect StoreError:
      discard openStore(path, "nobody")
    openStore(path).close()

  test "a database from a newer version is refused":
    let path = tempDb("newer")
    let a = openStore(path)
    a.db.exec(sql"pragma user_version = 99")
    a.close()
    expect StoreError:
      discard openStore(path)

  test "a file that is not a database is a StoreError":
    let path = tempDb("junk")
    writeFile(path, "this is not an sqlite database, not at all.")
    expect StoreError:
      discard openStore(path)

suite "database: the schema":
  test "foreign keys are enforced":
    let s = openStore(":memory:")
    expect DbError:
      s.db.exec(sql"""insert into file(user_id, name, sha256, imported_at)
                      values (999, 'f', 'x', 0)""")
    s.close()

  test "coords is WITHOUT ROWID, keyed by activity and time":
    let s = openStore(":memory:")
    check s.db.getValue(sql"select wr from pragma_table_list where name = 'coords'") == "1"
    check s.db.getValue(sql"select group_concat(name) from pragma_table_info('coords') where pk > 0") != ""
    s.close()

  test "a duplicate key is a StoreError":
    let s = openStore(":memory:")
    s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, 'f', 'x', 0)", s.userId)
    s.db.exec(sql"""insert into activity(user_id, file_id, session, start_t, end_t)
                    values (?, 1, 0, 0, 0)""", s.userId)
    let ins = prepareStmt(s.db,
      "insert into coords(activity_id, t, lon, lat, alt) values (?, ?, ?, ?, ?)")
    defer: finalize(ins)
    for _ in 0 .. 0:
      ins.bindInt(1, 1); ins.bindInt(2, 100); ins.bindReal(3, 1.5)
      ins.bindReal(4, 2.5); ins.bindNull(5)
      ins.run()
    ins.bindInt(1, 1); ins.bindInt(2, 100); ins.bindReal(3, 1.5)
    ins.bindReal(4, 2.5); ins.bindNull(5)
    expect StoreError:
      ins.run()
    s.close()

suite "database: prepared statements":
  test "a statement can be run again and again, with nulls":
    let s = openStore(":memory:")
    s.db.exec(sql"create table t(a integer, b real, c text, d integer)")
    let ins = prepareStmt(s.db, "insert into t values (?, ?, ?, ?)")
    defer: finalize(ins)
    for i in 1 .. 3:
      ins.bindInt(1, int64(i))
      ins.bindReal(2, some(float(i) / 2))
      ins.bindOptText(3, if i == 2: "" else: "x" & $i)
      ins.bindInt(4, none(int))
      ins.run()
    check s.count("t") == 3
    check s.db.getValue(sql"select b from t where a = 3") == "1.5"
    check s.db.getValue(sql"select count(*) from t where c is null") == "1"
    check s.db.getValue(sql"select count(*) from t where d is null") == "3"
    s.close()

  test "a bad statement is a StoreError":
    let s = openStore(":memory:")
    expect StoreError:
      discard prepareStmt(s.db, "insert into nonesuch values (1)")
    s.close()

suite "database: where it lives":
  test "the option wins, then the environment, then the data directory":
    let saved = getEnv("NCH_DB")
    putEnv("NCH_DB", "/from/env.db")
    check resolveDbPath("/from/option.db") == "/from/option.db"
    check resolveDbPath("") == "/from/env.db"
    delEnv("NCH_DB")
    check resolveDbPath("").endsWith("nch" / "nch.db")
    if saved.len > 0: putEnv("NCH_DB", saved)
