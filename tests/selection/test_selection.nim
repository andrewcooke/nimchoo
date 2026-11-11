import nimchoo/packages/db/statement
import std/[os, sequtils, strutils, unittest]
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
    "insert into selection(user_id, activity_id) select :userId, max(id) from activity",
    userId = s.userId,
  )

suite "selection: the key":
  test "twelve hex digits":
    let k = keyOf(@["a:0"])
    check k.len == 12
    check k.allIt(it in HexDigits and it notin {'A' .. 'F'})
  test "stable, and independent of the order":
    check keyOf(@["a:0", "b:0"]) == keyOf(@["b:0", "a:0"])
    check keyOf(@["a:0", "b:0"]) == keyOf(@["a:0", "b:0"])
  test "a different selection, a different key":
    check keyOf(@["a:0"]) != keyOf(@["a:1"])
    check keyOf(@["a:0"]) != keyOf(@["a:0", "b:0"])
    check keyOf(@["a:0"]) != keyOf(@[])
  test "known value (the SHA-256 of nothing starts e3b0c44298fc)":
    check keyOf(@[]) == "e3b0c44298fc"

proc selectionKey(st: Session): string =
  ## The content key of the user's selection.
  contentKey(st, selectedIds(st))

suite "selection: of the database":
  test "an empty selection has the key of nothing":
    let s = fresh("empty")
    defer:
      s.close()
    check selectionKey(s) == keyOf(@[])
  test "it follows the selection":
    let s = fresh("follows")
    defer:
      s.close()
    s.add "aa"
    let one = selectionKey(s)
    s.add "bb"
    let two = selectionKey(s)
    check one != two
    s.db.execute("delete from selection where activity_id = 2")
    check selectionKey(s) == one
  test "it is the content that counts, not the ids or the database":
    let a = fresh("one")
    defer:
      a.close()
    a.add "aa"
    a.add "bb"
    let b = fresh("two")
    defer:
      b.close()
    b.add "bb" # (other ids, other order)
    b.add "aa"
    check selectionKey(a) == selectionKey(b)
  test "the session counts":
    let a = fresh("sess0")
    defer:
      a.close()
    a.add "aa", 0
    let b = fresh("sess1")
    defer:
      b.close()
    b.add "aa", 1
    check selectionKey(a) != selectionKey(b)
  test "only the user's own selection":
    let s = fresh("owner")
    defer:
      s.close()
    s.add "aa"
    s.db.execute("insert into user(name) values ('bob')")
    let bob =
      openSession(dir / "owner" / "x.db", allFragments, "bob", access = allAccess)
    defer:
      bob.close()
    check selectionKey(bob) == keyOf(@[])
    check selectionKey(s) != keyOf(@[])

suite "selection: for an address (the ids, the check)":
  test "the selected ids, in order; the highest id; the user's own":
    let s = fresh("ids")
    defer:
      s.close()
    check selectedIds(s).len == 0 and maxActivityId(s) == 0
    s.add "a"
    s.add "b"
    s.add "c"
    check selectedIds(s) == @[1'i64, 2, 3] and maxActivityId(s) == 3
    check ownedIds(s, @[3'i64, 1, 9, 2]) == @[3'i64, 1, 2] # (9 is not an activity)
    s.db.execute("insert into user(name, is_default) values ('bob', 0)")
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) select id, 'x', 'x', 0 from user where name = 'bob'"
    )
    s.db.execute(
      "insert into activity(file_id, session, start_t, end_t) select max(id), 0, 0, 1 from file"
    )
    check ownedIds(s, @[1'i64, 4]) == @[1'i64] # (4 is bob's)
  test "the key of the content is the same however the ids are arranged":
    let s = fresh("check")
    defer:
      s.close()
    s.add "a"
    s.add "b"
    let c = contentKey(s, @[1'i64, 2])
    check c == contentKey(s, @[2'i64, 1])
    check c != contentKey(s, @[1'i64])
    check c == selectionKey(s)

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
