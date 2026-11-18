import std/unittest
import nimchoo/core/extension
import nimchoo/packages/db/statement
import nimchoo/packages/subject/subjects
import nimchoo/packages/user/session
import nimchoo/packages/climbs/[chosen, work]
import nimchoo/registry
import ../support/climbdata

proc world(name: string): Session =
  ## A climb, ridden twice by the default user.
  let s = fresh(name)
  addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
  addRide(s, "default", "two", 2_000_000, 6.0, eastbound(6.0))
  discard ensureClimbs(s)
  s

suite "climbs selection":
  test "it is empty at first, and replaced as a whole":
    let s = world("chosen-replace")
    defer:
      s.close()
    check chosenClimbs(s).len == 0
    let all = s.db.query(int64, "select id from sector order by id")
    check all.len >= 1
    s.replaceClimbSelection(all)
    check chosenClimbs(s).len == all.len
    s.replaceClimbSelection(@[all[0]])
    check chosenClimbs(s) == @[all[0]]
    s.replaceClimbSelection(@[])
    check chosenClimbs(s).len == 0

  test "a retired climb is hidden from it, and comes back when unretired":
    let s = world("chosen-retired")
    defer:
      s.close()
    let all = s.db.query(int64, "select id from sector order by id")
    s.replaceClimbSelection(all)
    s.db.execute("update sector set retired = 1 where id = :id", id = all[0])
    check all[0] notin chosenClimbs(s)
    s.db.execute("update sector set retired = 0 where id = :id", id = all[0])
    check all[0] in chosenClimbs(s)

  test "deleting the climbs empties it":
    let s = world("chosen-delete")
    defer:
      s.close()
    s.replaceClimbSelection(s.db.query(int64, "select id from sector"))
    s.db.execute("delete from sector")
    check chosenClimbs(s).len == 0

suite "climbs subject":
  test "the climbs are a subject, not the default, and count the selection":
    let found = extensions.get(subjectPoint)
    var climbs: seq[Subject]
    for x in found:
      if x.name == "climbs":
        climbs.add x
    check climbs.len == 1 and not climbs[0].isDefault
    let s = world("chosen-subject")
    defer:
      s.close()
    check climbs[0].selected(s) == 0
    s.replaceClimbSelection(s.db.query(int64, "select id from sector"))
    check climbs[0].selected(s) > 0
