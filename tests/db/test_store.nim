import std/[options, os, sets, strutils, unittest]
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

var seedRuns = 0

proc putSeven(db: DbConn) {.raises: [StoreError].} =
  inc seedRuns
  guard: db.exec(sql"insert into t(x) values (7)")

proc failingSeed(db: DbConn) {.raises: [StoreError].} =
  guard: db.exec(sql"insert into t(x) values (1)")
  raiseStore("the seed failed")

func frag(name, sqlText: string): Fragment =
  Fragment(name: name, sql: sqlText)

suite "database: opening and bringing the schema up to date":
  test "a new database has the schema and the default user, flagged as such":
    let path = tempDb("new")
    let s = open(path)
    check fileExists(path)
    check s.userName == defaultUser
    check int64(s.userId) > 0
    check s.db.getValue(sql"select name from user where is_default = 1") == defaultUser
    for table in ["user", "file", "activity", "coords", "segment", "fragment"]:
      check s.db.getValue(sql"select count(*) from sqlite_master where name = ?",
                          table) == "1"
    s.close()

  test "a store is closed when it goes out of scope; closing by hand as well is fine":
    let path = tempDb("scope")
    block opened:
      let s = open(path)
      s.db.exec(sql"create table scratch(x integer)")
      check fileExists(path & "-wal")        # (the write-ahead log exists while it is open)
    check not fileExists(path & "-wal")      # (the last connection to close copies it back and removes it)
    let t = open(path)
    t.close()
    t.close()                                # (twice: nothing happens the second time)
    let u = open(path)
    check u.db.getValue(sql"select count(*) from scratch") == "0"

  test "a statement is finalized when its last copy goes, so the database can close":
    let path = tempDb("stmt")
    let s = open(path)
    block statements:
      let st = prepareStmt(s.db, "insert into user(name) values (?)")
      let copy = st                          # (a handle: the statement is one)
      copy.bindText(1, "carol")
      copy.run()
      st.bindText(1, "dave")
      st.run()
    s.close()                                # (would complain of unfinalized statements)
    check open(path, "carol").userName == "carol"

  test "the fragments applied are recorded":
    let s = open(tempDb("recorded"))
    var names: seq[string]
    for row in s.db.fastRows(sql"select name from fragment order by name"):
      names.add row[0]
    check names == @["climbs/001-schema.sql", "db/001-schema.sql", "heartrate/001-schema.sql", "importer/001-schema.sql",
                     "landmark/001-schema.sql", "model/001-schema.sql", "names/001-schema.sql", "selection/001-schema.sql",
                     "user/001-schema.sql"]
    s.close()

  test "each fragment is recorded with the checksum of its SQL":
    let path = tempDb("checksums")
    let one = frag("m/001.sql", "create table t(x integer);")
    openStore(path, @[one]).close()
    let s = openStore(path, @[one])
    defer: s.close()
    check s.db.getValue(sql"select sha256 from fragment where name = 'm/001.sql'") == one.checksum
    check one.checksum.len == 64
    check one.checksum != frag("m/001.sql", "create table t(x integer); ").checksum   # (any change)
    check one.checksum == frag("other/name.sql", "create table t(x integer);").checksum  # (only the SQL counts)

  test "a database made from different SQL is refused, and told to start again":
    let path = tempDb("changed")
    openStore(path, @[frag("m/001.sql", "create table t(x integer);")]).close()
    try:
      openStore(path, @[frag("m/001.sql", "create table t(x integer, y integer);")]).close()
      check false
    except StoreError as e:
      check "different version of nch" in e.msg
      check "m/001.sql" in e.msg
      check "nch empty --all -f" in e.msg
    # and the unchanged one is fine
    openStore(path, @[frag("m/001.sql", "create table t(x integer);")]).close()

  test "a database made before checksums were recorded is refused the same way":
    let path = tempDb("nochecksums")
    let old = db_sqlite.open(path, "", "", "")
    old.exec(sql"create table fragment (name text primary key, applied_at integer not null) without rowid")
    old.exec(sql"insert into fragment(name, applied_at) values ('db/001-schema.sql', 0)")
    old.close()
    try:
      openStore(path, allFragments).close()
      check false
    except StoreError as e:
      check "older version of nch" in e.msg
      check "nch empty --all -f" in e.msg

  test "the data a seed puts in is part of the checksum, when it is given a version":
    let plain = frag("m/001.sql", "create table t(x integer);")
    let v1 = plain.withSeed(putSeven, "list-1")
    let v2 = plain.withSeed(putSeven, "list-2")
    check v1.checksum != plain.checksum and v1.checksum != v2.checksum
    check plain.withSeed(putSeven).checksum == plain.checksum       # (no version: the SQL alone)
    let path = tempDb("seedversion")
    openStore(path, @[v1]).close()
    openStore(path, @[v1]).close()                                  # the same data: fine
    try:
      openStore(path, @[v2]).close()                                # other data: refused
      check false
    except StoreError as e:
      check "different version of nch" in e.msg and "nch empty --all -f" in e.msg

  test "data that can be replaced: reseeded when its version changes, remembered, not refused":
    let path = tempDb("reseed")      # (the version is kept in a file: a proc cannot capture a variable)
    let marker = path & ".version"
    writeFile(marker, "one")
    proc fileVersion(): string {.nimcall, raises: [].} =
      try: readFile(getTempDir() / "nch-test-db" / "reseed.db.version") except IOError: ""
    proc putData(db: DbConn) {.nimcall, raises: [StoreError].} =
      guard:
        db.exec(sql"delete from t")
        db.exec(sql"insert into t(x) values (?)", fileVersion())
    let f = frag("m/001.sql", "create table t(x text);").withSeed(putData).withReseed(fileVersion, putData)
    let a = openStore(path, @[f])
    check a.db.getValue(sql"select x from t") == "one"
    check a.db.getValue(sql"select seed_version from fragment where name = 'm/001.sql'") == "one"
    a.close()
    writeFile(marker, "two")                                   # the data now to be put in are other
    let b = openStore(path, @[f])
    check b.db.getValue(sql"select x from t") == "two"         # replaced, not refused
    check b.db.getValue(sql"select seed_version from fragment where name = 'm/001.sql'") == "two"
    b.close()
    # a reseed that fails undoes itself and refuses the database, with the reason
    proc failing(db: DbConn) {.nimcall, raises: [StoreError].} =
      guard: db.exec(sql"delete from t")
      raiseStore("no good list")
    writeFile(marker, "three")
    let bad = frag("m/001.sql", "create table t(x text);").withReseed(fileVersion, failing)
    try:
      openStore(path, @[bad]).close()
      check false
    except StoreError as e:
      check "replacing the data of m/001.sql" in e.msg and "no good list" in e.msg
    writeFile(marker, "two")
    let c = openStore(path, @[f])
    check c.db.getValue(sql"select x from t") == "two"         # (the failed one changed nothing)
    c.close()

  test "a database whose recorded checksum is a legacy one is accepted, and the record is brought up to date":
    let path = tempDb("legacy")
    let old = frag("m/001.sql", "create table t(x integer);").withSeed(putSeven, "list-1")
    openStore(path, @[old]).close()                             # recorded with the data in the checksum
    seedRuns = 0
    let now = frag("m/001.sql", "create table t(x integer);").withSeed(putSeven)
                .withLegacy(@[old.checksum], "list-1")
    check now.checksum != old.checksum
    openStore(path, @[now]).close()                             # accepted
    check seedRuns == 0
    let s = openStore(path, @[now])
    check s.db.getValue(sql"select sha256 from fragment where name = 'm/001.sql'") == now.checksum
    check s.db.getValue(sql"select seed_version from fragment where name = 'm/001.sql'") == "list-1"
    s.close()
    # ... but not a checksum nobody ever recorded
    let other = frag("m/001.sql", "create table t(x integer);").withSeed(putSeven)
                .withLegacy(@["not-a-checksum"], "list-1")
    let path2 = tempDb("legacy2")
    openStore(path2, @[old]).close()
    expect StoreError: openStore(path2, @[other]).close()

  test "a changed fragment that has a seed is noticed too":
    let path = tempDb("changedseeded")
    seedRuns = 0
    openStore(path, @[frag("m/001.sql", "create table t(x integer);").withSeed(putSeven)]).close()
    expect StoreError:
      openStore(path, @[frag("m/001.sql", "create table t(x integer, z integer);").withSeed(putSeven)]).close()
    check seedRuns == 1                                       # (not seeded again)

  test "opening again changes nothing":
    let path = tempDb("again")
    let a = open(path)
    let id = a.userId
    a.close()
    let b = open(path)
    check b.userId == id
    check b.count("user") == 1
    check b.count("fragment") == 9
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
    check int64(b.userId) > 1
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
    a.db.exec(sql"insert into fragment(name, applied_at, sha256) values ('future/001-x.sql', 0, 'x')")
    a.close()
    expect StoreError:
      discard open(path)

  test "a file that is not a database is a StoreError":
    let path = tempDb("junk")
    writeFile(path, "this is not an sqlite database, not at all.")
    expect StoreError:
      discard open(path)

suite "database: fragments":
  test "a seed runs right after its fragment's SQL, once":
    seedRuns = 0
    let path = tempDb("seed")
    let seeded = frag("m/001.sql", "create table t(x integer);").withSeed(putSeven)
    openStore(path, @[seeded]).close()
    check seedRuns == 1
    let s = openStore(path, @[seeded])                         # again: not run again
    defer: s.close()
    check seedRuns == 1
    check s.count("t") == 1
    check s.db.getValue(sql"select x from t") == "7"

  test "a seed that fails undoes its fragment":
    let path = tempDb("seedfail")
    expect StoreError:
      openStore(path, @[frag("m/001.sql", "create table t(x integer);").withSeed(failingSeed)]).close()
    let s = openStore(path, @[frag("m/001.sql", "create table t(x integer);")])   # the fragment was not recorded
    defer: s.close()
    check s.count("t") == 0

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

  test "every sql file on disk is in the list of fragments, and the other way round":
    var onDisk: HashSet[string]
    for path in walkFiles("src/nimchoo/*/*.sql"):
      onDisk.incl path.parentDir.lastPathPart & "/" & path.extractFilename
    var listed = toHashSet(["db/001-schema.sql"])   # the database's own
    for f in allFragments: listed.incl f.name
    check onDisk == listed

suite "database: cascades":
  test "deleting a user deletes everything under them":
    let s = open(":memory:")
    defer: s.close()
    s.db.exec(sql"""insert into file(user_id, name, sha256, imported_at)
                    values (1, 'f', 'x', 0)""")
    s.db.exec(sql"""insert into activity(file_id, session, start_t, end_t)
                    values (1, 0, 0, 10)""")
    s.db.exec(sql"insert into coords(activity_id, t, lon, lat) values (1, 5, 1.0, 2.0)")
    s.db.exec(sql"insert into segment(activity_id, n, start_t, end_t) values (1, 1, 0, 10)")
    s.db.exec(sql"insert into seen_file(user_id, path, size, mtime, file_id) values (1, '/p', 1, 1, 1)")
    s.db.exec(sql"delete from user where id = 1")
    for t in ["file", "activity", "coords", "segment", "seen_file"]:
      check s.count(t) == 0

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
    s.db.exec(sql"""insert into activity(file_id, session, start_t, end_t)
                    values (1, 0, 0, 0)""")
    let ins = prepareStmt(s.db,
      "insert into coords(activity_id, t, lon, lat, alt) values (?, ?, ?, ?, ?)")
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
