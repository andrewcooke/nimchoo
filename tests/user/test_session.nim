import std/[os, unittest]
import nimchoo/packages/db/statement
import nimchoo/packages/user/session
import nimchoo/core/errors
from nimchoo/registry import allFragments, allAccess

let dir = getTempDir() / "nch-test-session"

proc tempDb(name: string): string =
  createDir(dir)
  result = dir / name & ".db"
  removeFile(result)

proc open(path: string, user = defaultUser): Session =
  ## The whole schema.
  openSession(path, allFragments, user, access = allAccess)

suite "session: the user a command works for":
  test "a new database has the schema and the default user, flagged as such":
    let path = tempDb("new")
    let s = open(path)
    check fileExists(path)
    check s.userName == defaultUser
    check int64(s.userId) > 0
    check s.db.scalar(string, "select name from user where is_default = 1") ==
      defaultUser
    for table in ["user", "file", "activity", "coords", "segment", "fragment"]:
      check s.db.scalar(
        int, "select count(*) from sqlite_master where name = :name", name = table
      ) == 1
    s.close()

  test "another user":
    let path = tempDb("users")
    let a = open(path)
    a.db.execute("insert into user(name) values ('bob')")
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

  test "the default user is made when there are none, and moves to the oldest when it has gone":
    let path = tempDb("nodefault")
    let a = open(path)
    a.db.execute("insert into user(name) values ('bob')")
    a.db.execute("delete from user where is_default = 1")
    a.close()
    check openSession(path, allFragments, access = allAccess).userName == "bob"
