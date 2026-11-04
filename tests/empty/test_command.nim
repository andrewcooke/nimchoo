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

  test "no database: nothing to do, and nothing is created":
    let d = fresh("none")
    check emptyCommand.run(globals(d / "x.db"), @["--all", "--force"]) == exitOk
    check emptyCommand.run(globals(d / "x.db"), @["--user", "bob", "--force"]) == exitOk
    check not fileExists(d / "x.db")

suite "empty: what to empty is named":
  test "there is no default: a target is needed, and only one":
    let d = fresh("target")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db"), @[]) == exitUsage
    check emptyCommand.run(globals(d / "x.db"), @["-f"]) == exitUsage
    check emptyCommand.run(globals(d / "x.db"), @["--all", "--user", "bob", "-f"]) == exitUsage
    check emptyCommand.run(globals(d / "x.db"), @["--all", "--cache", "-f"]) == exitUsage
    check fileExists(d / "x.db")

  test "--user before the command is refused, with a hint":
    let d = fresh("globaluser")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db", "bob"), @["--all", "-f"]) == exitUsage
    check emptyCommand.run(globals(d / "x.db", "bob"), @["--user", "bob", "-f"]) == exitUsage
    check fileExists(d / "x.db")

  test "bad arguments are a usage error":
    check emptyCommand.run(globals("x"), @["--bogus"]) == exitUsage
    check emptyCommand.run(globals("x"), @["--help"]) == exitOk

suite "empty --user: one user's data":
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

    check emptyCommand.run(globals(d / "x.db"), @["--user", "bob"]) == exitFailure       # no -f
    let before = openStore(d / "x.db", allFragments)
    for t in tables: check before.count(t) == 2
    before.close()

    check emptyCommand.run(globals(d / "x.db"), @["--user", "bob", "-f"]) == exitOk
    let after = openStore(d / "x.db", allFragments)
    defer: after.close()
    for t in tables: check after.count(t) == 1
    check after.db.getValue(sql"select count(*) from user where name = 'bob'") == "1"
    check after.db.getValue(sql"select name from file") == "mine"
    check after.db.getValue(sql"select fthr from user_profile") == "150"

  test "an unknown user is an error":
    let d = fresh("unknown")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db"), @["--user", "nobody", "-f"]) == exitFailure

suite "empty --cache: the files commands made":
  test "the generated files go; the unpacked ones and the token stay; no -f needed":
    let d = fresh("cache")
    putEnv("NCH_CACHE", d / "cache")
    defer: delEnv("NCH_CACHE")
    createDir(d / "cache" / "user")
    createDir(d / "cache" / "system")
    writeFile(d / "cache" / "user" / "heatmap--key-ab.geojson", "{}")
    writeFile(d / "cache" / "user" / "ff--key-cd.csv", "time\n")
    writeFile(d / "cache" / "system" / "libraries.txt", "x")
    writeFile(d / "cache" / "server-token", "secret")
    check emptyCommand.run(globals(d / "none.db"), @["--cache"]) == exitOk
    check not fileExists(d / "cache" / "user" / "heatmap--key-ab.geojson")
    check not fileExists(d / "cache" / "user" / "ff--key-cd.csv")
    check fileExists(d / "cache" / "system" / "libraries.txt")
    check fileExists(d / "cache" / "server-token")
    check not fileExists(d / "none.db")            # (the database is not touched, or made)
    check emptyCommand.run(globals(d / "none.db"), @["--cache"]) == exitOk      # nothing left: fine
