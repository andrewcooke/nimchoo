import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/command as destroyCommand
import nimchoo/db/store
import nimchoo/modules

let dir = getTempDir() / "nch-test-destroy"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

proc count(s: Store, table: string): int =
  parseInt(s.db.getValue(sql("select count(*) from " & table)))

proc fill(s: Store, tag: string) =
  ## One of everything, for the user of `s`.
  let u = s.userId
  s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
            u, tag, tag)
  let f = s.db.getValue(sql"select id from file where user_id = ? and sha256 = ?", u, tag)
  s.db.exec(sql"""insert into activity(user_id, file_id, session, start_t, end_t)
                  values (?, ?, 0, 0, 10)""", u, f)
  let a = s.db.getValue(sql"select max(id) from activity")
  s.db.exec(sql"insert into coords(activity_id, t, lon, lat) values (?, 5, 1.0, 2.0)", a)
  s.db.exec(sql"insert into segment(activity_id, n, start_t, end_t) values (?, 1, 0, 10)", a)
  s.db.exec(sql"insert into seen_file(user_id, path, size, mtime, file_id) values (?, ?, 1, 1, ?)",
            u, "/" & tag, f)

func globals(db: string, user = ""): Globals =
  Globals(dbPath: db, user: user, fragments: allFragments)

const tables = ["file", "activity", "coords", "segment", "seen_file"]

suite "destroy: the whole database":
  test "without --force nothing happens":
    let d = fresh("noforce")
    openStore(d / "x.db", allFragments).close()
    check destroyCommand.run(globals(d / "x.db"), @[]) == exitFailure
    check fileExists(d / "x.db")

  test "with --force the file and its journal files go":
    let d = fresh("force")
    openStore(d / "x.db", allFragments).close()
    writeFile(d / "x.db-journal", "")
    check destroyCommand.run(globals(d / "x.db"), @["-f"]) == exitOk
    check not fileExists(d / "x.db")
    check not fileExists(d / "x.db-journal")

  test "no database: nothing to do, and nothing is created":
    let d = fresh("none")
    check destroyCommand.run(globals(d / "x.db"), @["--force"]) == exitOk
    check destroyCommand.run(globals(d / "x.db", "bob"), @["--force"]) == exitOk
    check not fileExists(d / "x.db")

  test "bad arguments are a usage error":
    check destroyCommand.run(globals("x"), @["--bogus"]) == exitUsage
    check destroyCommand.run(globals("x"), @["--help"]) == exitOk

suite "destroy: one user":
  test "the user and everything under them go; others stay":
    let d = fresh("user")
    let a = openStore(d / "x.db", allFragments)
    fill(a, "mine")
    a.close()
    # (a user other than the default has to be made by hand for now)
    let c = db_sqlite.open(d / "x.db", "", "", "")
    c.exec(sql"insert or ignore into user(name) values ('bob')")
    c.close()
    let bob = openStore(d / "x.db", allFragments, "bob")
    fill(bob, "bobs")
    bob.close()

    check destroyCommand.run(globals(d / "x.db", "bob"), @[]) == exitFailure   # no -f
    let before = openStore(d / "x.db", allFragments)
    for t in tables: check before.count(t) == 2
    before.close()

    check destroyCommand.run(globals(d / "x.db", "bob"), @["-f"]) == exitOk
    let after = openStore(d / "x.db", allFragments)
    defer: after.close()
    for t in tables: check after.count(t) == 1
    check after.db.getValue(sql"select count(*) from user where name = 'bob'") == "0"
    check after.db.getValue(sql"select name from file") == "mine"

  test "an unknown user is an error":
    let d = fresh("unknown")
    openStore(d / "x.db", allFragments).close()
    check destroyCommand.run(globals(d / "x.db", "nobody"), @["-f"]) == exitFailure

  test "the default user comes back, empty":
    let d = fresh("default")
    let a = openStore(d / "x.db", allFragments)
    fill(a, "mine")
    a.close()
    check destroyCommand.run(globals(d / "x.db", defaultUser), @["-f"]) == exitOk
    let again = openStore(d / "x.db", allFragments)
    defer: again.close()
    check again.userName == defaultUser
    for t in tables: check again.count(t) == 0
