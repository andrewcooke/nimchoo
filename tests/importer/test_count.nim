import std/[options, os, unittest]
import db_connector/db_sqlite
import nimchoo/packages/db/statement
import nimchoo/packages/db/store
import nimchoo/core/errors
import nimchoo/packages/importer/count
import nimchoo/modules
import ../support/userdata

let dir = getTempDir() / "nch-test-count"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

suite "importer: counting activities":
  test "activities are counted straight from the file, whatever its layout":
    let d = fresh("count")
    let a = openStore(d / "x.db", allFragments, access = allAccess)
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
      openStore(d / "x.db", allFragments, access = allAccess).close()
    check countActivities(d / "x.db", "") == some 1

  test "a file without an activity table is not counted":
    let d = fresh("nocount")
    let c = db_sqlite.open(d / "x.db", "", "", "")
    c.execute("create table t(x)")
    c.close()
    check countActivities(d / "x.db", "").isNone
