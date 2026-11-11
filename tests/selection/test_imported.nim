import std/[options, os, unittest]
import nimchoo/core/extension
import nimchoo/packages/db/statement
import nimchoo/packages/importer/after
import nimchoo/packages/selection/imported
import nimchoo/packages/ui/vocabulary
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

let dir = getTempDir() / "nch-test-imported"

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

suite "selection: after an import":
  test "the point has the contribution":
    check extensions.get(afterImport).len == 2
      # (the climbs are worked out too: climbs/test_imported.nim)

  test "the new activities replace the selection, and the report is in the colour of the selection":
    let s = fresh("replace")
    defer:
      s.close()
    let a = s.addActivity("a")
    let b = s.addActivity("b")
    let c = s.addActivity("c")
    let first = selectNewActivities.run(s, @[a])
    check first.get.text == "selected the new activity"
    check first.get.look.colour == selectedColour
    let second = selectNewActivities.run(s, @[b, c])
    check second.get.text == "selected the 2 new activities"
    check s.db.query(int64, "select activity_id from selection order by 1") == @[b, c]
