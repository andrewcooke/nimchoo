import std/[os, unittest]
import nimchoo/packages/importer/count
import nimchoo/packages/user/[session, users, wipe]
from nimchoo/registry import allFragments, allAccess, newAllAccess
import ../support/userdata

let dir = getTempDir() / "nch-test-count"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

suite "importer: counting a user's activities":
  test "each user's own are counted":
    let d = fresh("count")
    let a = openSession(d / "x.db", allFragments, access = allAccess)
    check activityCount.count(a.db, a.userId) == 0
    fill(a, "mine")
    check activityCount.count(a.db, a.userId) == 1
    addUser(a, "bob")
    check activityCount.count(a.db, findUser(a, "bob")) == 0
    a.close()

  test "it is said as activities, and the one as activity":
    check activityCount.heading == "activities" and activityCount.one == "activity"
