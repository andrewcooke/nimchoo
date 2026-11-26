import std/[os, unittest]
import nimchoo/packages/db/statement
import nimchoo/packages/importer/active
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess
import ../support/userdata

let dir = getTempDir() / "nch-test-importer-active"

suite "active time: the riding less the breaks in which nothing was recorded":
  test "manual, carried and pause are taken off; a GPS error is no time missing":
    removeDir(dir)
    createDir(dir)
    let s = openSession(dir / "x.db", allFragments, access = allAccess)
    defer:
      s.close()
    fill(s, "a")
    let a = s.db.scalar(int64, "select max(id) from activity")
    s.db.execute(
      "update activity set riding_start_epoch = 1000, riding_end_epoch = 2000 where id = :id",
      id = a,
    )
    check s.db.scalar(
      int, "select " & activeSql() & " from activity a where a.id = :id", id = a
    ) == 1000 # (no breaks: the riding)
    for (b, e, kind) in [
      (1100, 1200, "manual"),
      (1300, 1350, "carried"),
      (1400, 1430, "pause"),
      (1500, 1501, "error"),
    ]:
      s.db.execute(
        "insert into ride_break(activity_id, start_epoch, end_epoch, kind) values (:id, :b, :e, :kind)",
        id = a,
        b = b,
        e = e,
        kind = kind,
      )
    check s.db.scalar(
      int, "select " & activeSql() & " from activity a where a.id = :id", id = a
    ) == 1000 - 100 - 50 - 30
