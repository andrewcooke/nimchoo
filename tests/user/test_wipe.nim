import std/[os, unittest]
import nimchoo/packages/db/statement
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/user/users
import nimchoo/packages/user/wipe
import ../support/userdata

let dir = getTempDir() / "nch-test-wipe"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

suite "wipe: what is said":
  test "what is to go":
    check describe(@[counted(74, "activity", "activities")], "bob") ==
      "74 activities and user bob"
    check describe(@[counted(1, "activity", "activities")], "bob") ==
      "1 activity and user bob"
    check describe(
      @[counted(3, "activity", "activities"), counted(2, "note", "notes")], "bob"
    ) == "3 activities, 2 notes and user bob"
    check describe(@[], "bob") == "user bob"

suite "wipe: what belongs to a user":
  test "every table that names a user is emptied or goes with the user, so none is forgotten":
    let d = fresh("tables")
    let s = openSession(d / "x.db", allFragments, access = allAccess)
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
    openSession(d / "x.db", allFragments, access = allAccess).close()
    addUser(d / "x.db", "bob")
    let bob = openSession(d / "x.db", allFragments, "bob", access = allAccess)
    fill(bob, "bobs")
    deleteUser(bob, findUser(bob, "bob"))
    check bob.db.scalar(int, "select count(*) from user where name = 'bob'") == 0
    for t in tables:
      check bob.count(t) == 0
    bob.close()
