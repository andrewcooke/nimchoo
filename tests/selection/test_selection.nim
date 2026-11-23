import nimchoo/packages/db/statement
import std/[options, os, unittest]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/selection/selection

let dir = getTempDir() / "nch-test-selection"

proc fresh(name: string): Session =
  removeDir(dir / name)
  openSession(dir / name / "x.db", allFragments, access = allAccess)

proc add(s: Session, sha: string, session = 0) =
  ## An activity of file `sha`, in the selection.
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, 0)",
    userId = s.userId,
    name = sha,
    sha256 = sha,
  )
  let f = s.db.scalar(int64, "select max(id) from file")
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t) values (:fileId, :session, 0, 1)",
    fileId = f,
    session = session,
  )
  s.db.execute(
    "insert into activity_selection(user_id, activity_id) select :userId, max(id) from activity",
    userId = s.userId,
  )

suite "selection: reading it":
  test "the selected ids, in order; nothing when empty":
    let s = fresh("ids")
    defer:
      s.close()
    check selectedIds(s).len == 0
    s.add "a"
    s.add "b"
    s.add "c"
    check selectedIds(s) == @[1'i64, 2, 3]
  test "only the user's own selection":
    let s = fresh("owner")
    defer:
      s.close()
    s.add "aa"
    s.db.execute("insert into user(name) values ('bob')")
    let bob =
      openSession(dir / "owner" / "x.db", allFragments, some("bob"), access = allAccess)
    defer:
      bob.close()
    check selectedIds(bob).len == 0
    check selectedIds(s) == @[1'i64]

suite "selection: replacing it":
  test "the new ids replace the old ones; an empty list empties it":
    let s = fresh("replace")
    s.add "a"
    s.add "b"
    s.add "c"
    let all = selectedIds(s)
    check all.len == 3
    s.replaceSelection(all[1 .. 2])
    check selectedIds(s) == all[1 .. 2]
    s.replaceSelection(@[])
    check selectedIds(s).len == 0
    s.close()
