import std/[options, os, sequtils, sets, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/[fragment, statement, store]
import nimchoo/errors
import nimchoo/modules

let dir = getTempDir() / "nch-test-db"

proc tempDb(name: string): string =
  createDir(dir)
  result = dir / name & ".db"
  removeFile(result)

proc open(path: string, user = defaultUser): Store =
  ## The whole schema.
  openStore(path, allFragments, user)

proc count(s: Store, table: string): int =
  parseInt(s.db.getValue(sql("select count(*) from " & table)))

func frag(name, sqlText: string, legacy = 0): Fragment =
  Fragment(name: name, sql: sqlText, legacy: legacy)

suite "database: opening and bringing the schema up to date":
  test "a new database has the schema and the default user":
    let path = tempDb("new")
    let s = open(path)
    check fileExists(path)
    check s.userName == defaultUser
    check s.userId > 0
    for table in ["user", "file", "activity", "coords", "segment", "fragment"]:
      check s.db.getValue(sql"select count(*) from sqlite_master where name = ?",
                          table) == "1"
    s.close()

  test "the fragments applied are recorded":
    let s = open(tempDb("recorded"))
    var names: seq[string]
    for row in s.db.fastRows(sql"select name from fragment order by name"):
      names.add row[0]
    check names == @["activity/001-tables.sql", "activity/002-segment.sql",
                     "activity/003-seen.sql", "db/001-user.sql"]
    s.close()

  test "opening again changes nothing":
    let path = tempDb("again")
    let a = open(path)
    let id = a.userId
    a.close()
    let b = open(path)
    check b.userId == id
    check b.count("user") == 1
    check b.count("fragment") == 4
    b.close()

  test "the directory is created":
    let path = dir / "sub" / "deeper" / "x.db"
    removeDir(dir / "sub")
    open(path).close()
    check fileExists(path)
    removeDir(dir / "sub")

  test "an in-memory database":
    let s = open(":memory:")
    check s.count("user") == 1
    s.close()

  test "another user":
    let path = tempDb("users")
    let a = open(path)
    a.db.exec(sql"insert into user(name) values ('bob')")
    a.close()
    let b = open(path, "bob")
    check b.userName == "bob"
    check b.userId > 1
    b.close()

  test "an unknown user is an error, and leaves the database usable":
    let path = tempDb("nouser")
    open(path).close()
    expect StoreError:
      discard open(path, "nobody")
    open(path).close()

  test "a database with a fragment this build does not have is refused":
    let path = tempDb("newer")
    let a = open(path)
    a.db.exec(sql"insert into fragment(name, applied_at) values ('future/001-x.sql', 0)")
    a.close()
    expect StoreError:
      discard open(path)

  test "a file that is not a database is a StoreError":
    let path = tempDb("junk")
    writeFile(path, "this is not an sqlite database, not at all.")
    expect StoreError:
      discard open(path)

suite "database: fragments":
  test "applied in the order given, each only once":
    let path = tempDb("order")
    let one = frag("m/001.sql", "create table t(x integer);")
    let two = frag("m/002.sql", "create index t_x on t(x);")   # needs the first
    let s = openStore(path, @[one, two])
    check s.count("t") == 0
    s.close()
    let again = openStore(path, @[one, two])   # nothing to apply: no clash
    again.close()

  test "a module's fragments can be used without the others":
    let s = openStore(":memory:", @[frag("m/001.sql", "create table t(x);")])
    check s.count("user") == 1               # the database's own
    check s.db.getValue(sql"select count(*) from sqlite_master where name = 'file'") == "0"
    s.close()

  test "a fragment added later is applied to an existing database":
    let path = tempDb("later")
    let one = frag("m/001.sql", "create table t(x);")
    openStore(path, @[one]).close()
    let s = openStore(path, @[one, frag("m/002.sql", "create table u(y);")])
    check s.count("u") == 0
    check s.count("fragment") == 3
    s.close()

  test "a fragment that fails is rolled back completely":
    let path = tempDb("rollback")
    let bad = frag("m/001.sql", "create table ok1(x); create table ok1(y);")
    expect StoreError:
      discard openStore(path, @[bad])
    # nothing of it remains, so a corrected fragment of that name applies
    let s = openStore(path, @[frag("m/001.sql", "create table ok1(x);")])
    check s.count("ok1") == 0
    check s.count("fragment") == 2
    s.close()

  test "the error says which fragment":
    try:
      discard openStore(":memory:", @[frag("m/001.sql", "create tabel nonsense")])
      check false
    except StoreError as e:
      check "m/001.sql" in e.msg

  test "a database from the first release is recognised and upgraded":
    # what the first release made: one migration, recorded in user_version
    let path = tempDb("step1")
    let old = open(path)
    old.close()
    let c = db_sqlite.open(path, "", "", "")
    c.exec(sql"drop table fragment")
    c.exec(sql"drop table segment")
    c.exec(sql"drop table seen_file")
    c.exec(sql"pragma user_version = 1")
    c.exec(sql"""insert into file(user_id, name, sha256, imported_at)
                 values (1, 'old.fit', 'x', 0)""")
    c.exec(sql"""insert into activity(user_id, file_id, session, start_t, end_t)
                 values (1, 1, 0, 0, 10)""")
    c.exec(sql"""insert into coords(activity_id, t, lon, lat) values (1, 5, 1.0, 2.0)""")
    c.close()
    let s = open(path)
    check s.count("activity") == 1
    check s.count("coords") == 1
    check s.count("segment") == 0            # the new table exists
    check s.count("user") == 1
    check s.count("fragment") == 4
    s.close()

  test "every sql file on disk is in the list of fragments, and the other way round":
    var onDisk: HashSet[string]
    for path in walkFiles("src/nimchoo/*/sql/*.sql"):
      onDisk.incl path.parentDir.parentDir.lastPathPart & "/" & path.extractFilename
    var listed = toHashSet(["db/001-user.sql"])   # the database's own
    for f in allFragments: listed.incl f.name
    check onDisk == listed

suite "database: the schema":
  test "foreign keys are enforced":
    let s = open(":memory:")
    expect DbError:
      s.db.exec(sql"""insert into file(user_id, name, sha256, imported_at)
                      values (999, 'f', 'x', 0)""")
    s.close()

  test "coords and segment are WITHOUT ROWID, keyed by activity":
    let s = open(":memory:")
    for table in ["coords", "segment"]:
      check s.db.getValue(sql"select wr from pragma_table_list where name = ?",
                          table) == "1"
    s.close()

  test "a duplicate key is a StoreError":
    let s = open(":memory:")
    s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, 'f', 'x', 0)", s.userId)
    s.db.exec(sql"""insert into activity(user_id, file_id, session, start_t, end_t)
                    values (?, 1, 0, 0, 0)""", s.userId)
    let ins = prepareStmt(s.db,
      "insert into coords(activity_id, t, lon, lat, alt) values (?, ?, ?, ?, ?)")
    defer: finalize(ins)
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
    let s = open(":memory:")
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
    let s = open(":memory:")
    expect StoreError:
      discard prepareStmt(s.db, "insert into nonesuch values (1)")
    s.close()

  test "a script of several statements":
    let s = open(":memory:")
    execScript(s.db, "create table a(x); create table b(y);")
    check s.db.getValue(sql"select count(*) from sqlite_master where name in ('a', 'b')") == "2"
    expect StoreError:
      execScript(s.db, "create table c(x); create table c(y);")
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
