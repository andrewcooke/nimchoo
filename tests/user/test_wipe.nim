import nimchoo/db/statement
import std/[options, os, sequtils, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/errors
import nimchoo/modules
import nimchoo/ui/[live, style]
import nimchoo/user/wipe
import ../support/userdata

let dir = getTempDir() / "nch-test-wipe"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

suite "wipe: what is said":
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
    let l = newLive(
      write = proc(s: string) {.closure, raises: [].} =
        written.add(s),
      now = proc(): int64 {.closure, raises: [].} =
        0,
      size = proc(): tuple[w, h: int] {.closure, raises: [].} =
        (100, 24),
      colour = false,
    )
    countdown(
      l,
      "x",
      3,
      proc(ms: int) {.closure, raises: [].} =
        waits.add(ms),
    )
    check waits == @[1000, 1000, 1000]
    check written.len == 4 # three frames, then the removal
    check written[0].contains("in 3 s") and written[1].contains("in 2 s") and
      written[2].contains("in 1 s")
    check written[3].endsWith("\e[?25h") # the cursor is back

suite "wipe: counting":
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
    c.execute(
      "update fragment set name = 'activity/001-tables.sql' where name = 'importer/001-schema.sql'"
    )
    c.close()
    expect StoreError:
      openStore(d / "x.db", allFragments).close()
    check countActivities(d / "x.db", "") == some 1

  test "a file without an activity table is not counted":
    let d = fresh("nocount")
    let c = db_sqlite.open(d / "x.db", "", "", "")
    c.execute("create table t(x)")
    c.close()
    check countActivities(d / "x.db", "").isNone

suite "wipe: what belongs to a user":
  test "every table that names a user is emptied or goes with the user, so none is forgotten":
    let d = fresh("tables")
    let s = openStore(d / "x.db", allFragments)
    defer:
      s.close()
    var withUser: seq[string]
    for table in s.db.query(
      string, "select name from sqlite_master where type = 'table'"
    ):
      for column in s.db.query(string, "select name from pragma_table_info(?)", table):
        if column == "user_id":
          withUser.add table
    check "file" in withUser and "seen_file" in withUser # (the query finds the tables)
    for t in withUser:
      check t in userTables or t == "user_profile"
        # (a new table has to be put in the list)

  test "removing takes the user and everything under them":
    let d = fresh("remove")
    openStore(d / "x.db", allFragments).close()
    addUser(d / "x.db", "bob")
    let bob = openStore(d / "x.db", allFragments, "bob")
    fill(bob, "bobs")
    removeUser(bob, findUser(bob, "bob"))
    check bob.db.scalar(int, "select count(*) from user where name = 'bob'") == 0
    for t in tables:
      check bob.count(t) == 0
    bob.close()
