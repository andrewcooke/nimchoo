import std/[os, sequtils, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/modules
import nimchoo/selection/selection

let dir = getTempDir() / "nch-test-selection"

proc fresh(name: string): Store =
  removeDir(dir / name)
  openStore(dir / name / "x.db", allFragments)

proc add(s: Store, sha: string, session = 0) =
  ## An activity of file `sha`, in the selection.
  s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
            s.userId, sha, sha)
  let f = s.db.getValue(sql"select max(id) from file")
  s.db.exec(sql"insert into activity(file_id, session, start_t, end_t) values (?, ?, 0, 1)",
            f, session)
  s.db.exec(sql"insert into selection(user_id, activity_id) select ?, max(id) from activity",
            s.userId)

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

suite "selection: of the database":
  test "an empty selection has the key of nothing":
    let s = fresh("empty")
    defer: s.close()
    check selectionKey(s) == keyOf(@[])
  test "it follows the selection":
    let s = fresh("follows")
    defer: s.close()
    s.add "aa"
    let one = selectionKey(s)
    s.add "bb"
    let two = selectionKey(s)
    check one != two
    s.db.exec(sql"delete from selection where activity_id = 2")
    check selectionKey(s) == one
  test "it is the content that counts, not the ids or the database":
    let a = fresh("one")
    defer: a.close()
    a.add "aa"
    a.add "bb"
    let b = fresh("two")
    defer: b.close()
    b.add "bb"                      # (other ids, other order)
    b.add "aa"
    check selectionKey(a) == selectionKey(b)
  test "the session counts":
    let a = fresh("sess0")
    defer: a.close()
    a.add "aa", 0
    let b = fresh("sess1")
    defer: b.close()
    b.add "aa", 1
    check selectionKey(a) != selectionKey(b)
  test "only the user's own selection":
    let s = fresh("owner")
    defer: s.close()
    s.add "aa"
    s.db.exec(sql"insert into user(name) values ('bob')")
    let bob = openStore(dir / "owner" / "x.db", allFragments, "bob")
    defer: bob.close()
    check selectionKey(bob) == keyOf(@[])
    check selectionKey(s) != keyOf(@[])
