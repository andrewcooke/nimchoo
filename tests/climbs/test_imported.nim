import std/[options, os, sequtils, unittest]
import nimchoo/core/extension
import nimchoo/packages/db/statement
import nimchoo/packages/climbs/imported
import nimchoo/packages/importer/after
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, extensions

let dir = getTempDir() / "nch-test-climbs-imported"

proc fresh(name: string): Session =
  removeDir(dir / name)
  openSession(dir / name / "x.db", allFragments, access = allAccess)

proc addActivity(s: Session, sha: string): int64 =
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, 0)",
    userId = s.userId,
    name = sha,
    sha256 = sha,
  )
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t) select max(id), 0, 0, 1 from file"
  )
  s.db.scalar(int64, "select max(id) from activity")

suite "climbs: after an import":
  test "the point has the contribution":
    check extensions.get(afterImport).anyIt(it.failed == workNewClimbs.failed)

  test "the climbs of the activities not looked at are worked out, and said; a second time there is nothing":
    let s = fresh("work")
    defer:
      s.close()
    let a = s.addActivity("a")
    let b = s.addActivity("b")
    check s.db.scalar(int, "select count(*) from climbs_done") == 0
    let first = workNewClimbs.run(s, @[a])
    check first.isSome and
      first.get.text == "worked out the climbs of 2 activities: 0 new climbs"
      # (all that were lacking, not only the one named: a re-import catches up)
    check s.db.scalar(int, "select count(*) from climbs_done") == 2
    check workNewClimbs.run(s, @[b]).isNone
