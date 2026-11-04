import std/[os, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/empty/command as emptyCommand
import nimchoo/modules
import ../support/userdata

let dir = getTempDir() / "nch-test-empty"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

suite "empty --all: the whole database":
  test "without --force nothing happens":
    let d = fresh("noforce")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db"), @["--all"]) == exitFailure
    check fileExists(d / "x.db")

  test "with --force the file and its journal files go":
    let d = fresh("force")
    openStore(d / "x.db", allFragments).close()
    writeFile(d / "x.db-journal", "")
    check emptyCommand.run(globals(d / "x.db"), @["--all", "-f"]) == exitOk
    check not fileExists(d / "x.db")
    check not fileExists(d / "x.db-journal")

  test "the whole database is not something to do to one user":
    let d = fresh("alluser")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db", "bob"), @["--all", "-f"]) == exitUsage
    check fileExists(d / "x.db")

  test "no database: nothing to do, and nothing is created":
    let d = fresh("none")
    check emptyCommand.run(globals(d / "x.db"), @["--all", "--force"]) == exitOk
    check emptyCommand.run(globals(d / "x.db", "bob"), @["--force"]) == exitOk
    check not fileExists(d / "x.db")

  test "bad arguments are a usage error":
    check emptyCommand.run(globals("x"), @["--bogus"]) == exitUsage
    check emptyCommand.run(globals("x"), @["--help"]) == exitOk

suite "empty: one user's data":
  test "the user stays; their data and only theirs go":
    let d = fresh("user")
    let a = openStore(d / "x.db", allFragments)
    fill(a, "mine")
    a.close()
    addUser(d / "x.db", "bob")
    let bob = openStore(d / "x.db", allFragments, "bob")
    fill(bob, "bobs")
    bob.db.exec(sql"insert into user_profile(user_id, fthr) values (?, 150)", bob.userId)
    bob.close()

    check emptyCommand.run(globals(d / "x.db", "bob"), @[]) == exitFailure       # no -f
    let before = openStore(d / "x.db", allFragments)
    for t in tables: check before.count(t) == 2
    before.close()

    check emptyCommand.run(globals(d / "x.db", "bob"), @["-f"]) == exitOk
    let after = openStore(d / "x.db", allFragments)
    defer: after.close()
    for t in tables: check after.count(t) == 1
    check after.db.getValue(sql"select count(*) from user where name = 'bob'") == "1"
    check after.db.getValue(sql"select name from file") == "mine"
    check after.db.getValue(sql"select fthr from user_profile") == "150"

  test "without --user it is the default user's data":
    let d = fresh("default")
    let a = openStore(d / "x.db", allFragments)
    fill(a, "mine")
    a.close()
    addUser(d / "x.db", "bob")
    let bob = openStore(d / "x.db", allFragments, "bob")
    fill(bob, "bobs")
    bob.close()
    check emptyCommand.run(globals(d / "x.db"), @["-f"]) == exitOk
    let again = openStore(d / "x.db", allFragments)
    defer: again.close()
    check again.userName == defaultUser                  # (still there)
    check again.db.getValue(sql"select name from file") == "bobs"
    check again.count("file") == 1

  test "an unknown user is an error":
    let d = fresh("unknown")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db", "nobody"), @["-f"]) == exitFailure
