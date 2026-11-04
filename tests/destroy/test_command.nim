import std/[options, os, sequtils, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/destroy/command as destroyCommand
import nimchoo/db/store
import nimchoo/errors
import nimchoo/modules
import nimchoo/ui/[live, style]

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
  s.db.exec(sql"""insert into activity(file_id, session, start_t, end_t)
                  values (?, 0, 0, 10)""", f)
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

suite "destroy: what is said":
  test "what is to go":
    check describe(some 74, "") == "74 activities for all users"
    check describe(some 1, "bob") == "1 activity and user bob"
    check describe(none int, "") == "all data for all users"

  test "the countdown line is red, with the number bold":
    let l = countdownLine("74 activities for all users", 4)
    check l.text == "deleting 74 activities for all users in 4 s ... (Ctrl-C to cancel)"
    check l.allIt(it.look.colour == red)
    check l[1].text == "4" and l[1].look.bold

  test "it counts down once a second, then takes the line away":
    var written: seq[string]
    var waits: seq[int]
    let l = newLive(write = proc(s: string) {.closure, raises: [].} = written.add(s),
                    now = proc(): int64 {.closure, raises: [].} = 0,
                    size = proc(): tuple[w, h: int] {.closure, raises: [].} = (100, 24),
                    colour = false)
    countdown(l, "x", 3, proc(ms: int) {.closure, raises: [].} = waits.add(ms))
    check waits == @[1000, 1000, 1000]
    check written.len == 4                 # three frames, then the removal
    check written[0].contains("in 3 s") and written[1].contains("in 2 s") and
          written[2].contains("in 1 s")
    check written[3].endsWith("\e[?25h")   # the cursor is back

suite "destroy: counting":
  test "activities are counted straight from the file, whatever its layout":
    let d = fresh("count")
    let a = openStore(d / "x.db", allFragments)
    fill(a, "mine")
    a.close()
    check countActivities(d / "x.db", "") == some 1
    check countActivities(d / "x.db", defaultUser) == some 1
    check countActivities(d / "x.db", "nobody") == some 0
    # an older layout, which openStore refuses
    let c = db_sqlite.open(d / "x.db", "", "", "")
    c.exec(sql"update fragment set name = 'activity/001-tables.sql' where name like 'importer/%'")
    c.close()
    expect StoreError:
      openStore(d / "x.db", allFragments).close()
    check countActivities(d / "x.db", "") == some 1

  test "a file without an activity table is not counted":
    let d = fresh("nocount")
    let c = db_sqlite.open(d / "x.db", "", "", "")
    c.exec(sql"create table t(x)")
    c.close()
    check countActivities(d / "x.db", "").isNone
