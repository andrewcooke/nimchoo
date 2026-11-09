import std/[options, os, unittest]
import nimchoo/db/[statement, store]
import nimchoo/modules
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
      for column in s.db.query(
        string, "select name from pragma_table_info(:table)", table = table
      ):
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
