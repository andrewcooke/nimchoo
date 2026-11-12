import std/[os, sequtils, strutils, unittest]
import ../support/env
import nimchoo/core/[extension, globals]
import nimchoo/packages/db/statement
import nimchoo/packages/climbs/imported
import nimchoo/packages/importer/after
import nimchoo/packages/ui/style
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

let ctx = quietContext(Globals(offline: true))

useTestCache() # (the places are looked for in the test cache, never the real one)

suite "climbs: after an import":
  test "the point has the contribution":
    check extensions.get(afterImport).anyIt(it.failed == workNewClimbs.failed)

  test "the climbs of the activities not looked at are found, and said; a second time there is nothing":
    let s = fresh("work")
    defer:
      s.close()
    let a = s.addActivity("a")
    let b = s.addActivity("b")
    check s.db.scalar(int, "select count(*) from climbs_done") == 0
    let first = workNewClimbs.run(s, @[a], ctx)
    check first.len == 1 and
      first[0].text == "climbs for 2 activities: 0 new climbs, 0 efforts"
      # (all that were lacking, not only the one named: a re-import catches up)
    check s.db.scalar(int, "select count(*) from climbs_done") == 2
    check workNewClimbs.run(s, @[b], ctx).len == 0

  test "it shows how far it has got, and the last frame is the final one":
    let s = fresh("show")
    defer:
      s.close()
    let a = s.addActivity("a")
    discard s.addActivity("b")
    var frames: seq[tuple[text: string, final: bool]]
    var shown = ctx
    shown.show = proc(lines: seq[Line], final: bool) {.closure, raises: [].} =
      var text = ""
      for l in lines:
        for sp in l:
          text.add sp.text
        text.add "\n"
      frames.add (text, final)
    discard workNewClimbs.run(s, @[a], shown)
    check frames.len >= 2
    check frames[^1].final and not frames[0].final
    check frames[^1].text == "climbing 2 / 2 activities\nclimbs 0 · efforts 0\n"
    check frames[0].text.startsWith("climbing ")
    var finals = 0
    for f in frames:
      if f.final:
        inc finals
    check finals == 1
  test "nothing to work out: nothing is shown":
    let s = fresh("nothing")
    defer:
      s.close()
    let a = s.addActivity("a")
    check workNewClimbs.run(s, @[a], ctx).len == 1
    var frames = 0
    var shown = ctx
    shown.show = proc(lines: seq[Line], final: bool) {.closure, raises: [].} =
      inc frames
    check workNewClimbs.run(s, @[a], shown).len == 0
    check frames == 0
  test "climbs with no name are named, as nch climbs does, and said":
    let s = fresh("naming")
    defer:
      s.close()
    let a = s.addActivity("a")
    s.db.execute(
      """insert into sector(length_m, gain_m, gradient, category, route)
      values (1000, 90, 9, '4', GeomFromText('LINESTRING Z(-70.60 -33.40 10, -70.59 -33.40 100)', 4326))"""
    )
    check s.db.scalar(int, "select count(*) from sector where name is null") == 1
    let said = workNewClimbs.run(s, @[a], ctx)
    check said.len == 1 and said[0].text.startsWith("climbs for ")
    # (offline, with nothing in the test cache: not named, and not marked as having no name near; the names are tested in
    # test_naming.nim)
    check s.db.scalar(int, "select count(*) from sector where name is null") == 1
    check workNewClimbs.run(s, @[a], ctx).len == 0 # (nothing new to say)
