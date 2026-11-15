## The keys of frames (subject/keys.nim): what they are made of, and that a change of any part changes them.

import std/[options, os, unittest]
import nimchoo/packages/db/statement
import nimchoo/packages/subject/keys
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess

let dir = getTempDir() / "nch-test-keys"

proc open(name: string): Session =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  openSession(path, allFragments, access = allAccess)

suite "keys: made of parts":
  test "a key is 64 hex digits, the same for the same parts":
    let k = keyOf([("a", "x"), ("b", "y")])
    check k.len == 64
    check k == keyOf([("a", "x"), ("b", "y")])
  test "any part, name or order changes it":
    let k = keyOf([("a", "x"), ("b", "y")])
    check k != keyOf([("a", "x"), ("b", "z")])
    check k != keyOf([("a", "w"), ("b", "y")])
    check k != keyOf([("b", "y"), ("a", "x")]) # (the order is fixed by the caller)
    check k != keyOf([("a", "x")])
    check k != keyOf([("a", "x"), ("c", "y")])
  test "parts never cancel or run together":
    check keyOf([("a", "x"), ("b", "x")]) != keyOf([("a", "x")])
    check keyOf([("a", "x"), ("b", "x")]) != keyOf([("a", ""), ("b", "")])
    check keyOf([("a", "xy"), ("b", "")]) != keyOf([("a", "x"), ("b", "y")])
    check keyOf([("a", "x\nb:1:y")]) != keyOf([("a", "x"), ("b", "y")])
    check keyOf([("a", "")]) != keyOf([("a", ""), ("a", "")])

suite "keys: of tables":
  test "the key of tables follows their counters, and nothing else":
    let s = open("tables")
    defer:
      s.close()
    let before = tablesKey(s.db, @["selection", "file"])
    check before == tablesKey(s.db, @["file", "selection", "file"]) # (a set)
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, 'a', 'aa', 0)",
      userId = s.userId,
    )
    check tablesKey(s.db, @["selection", "file"]) != before
    check tablesKey(s.db, @["selection"]) == tablesKey(s.db, @["selection"])
    let selection = tablesKey(s.db, @["selection"])
    s.db.execute("insert into user(name) values ('bob')")
    check tablesKey(s.db, @["selection"]) == selection # (another table)
    check tablesKey(s.db, @["selection", "file"]) != tablesKey(s.db, @["file"])

suite "keys: of frames":
  test "every part of a frame key matters":
    let s = open("frames")
    defer:
      s.close()
    let k = frameKey(s.db, "map/activities/routes", some "sel", @["file"])
    check k == frameKey(s.db, "map/activities/routes", some "sel", @["file"])
    check k != frameKey(s.db, "map/activities/heat", some "sel", @["file"]) # the frame
    check k != frameKey(s.db, "map/activities/routes", some "other", @["file"])
      # the selection
    check k != frameKey(s.db, "map/activities/routes", none string, @["file"])
    check k != frameKey(s.db, "map/activities/routes", some "sel", @["file", "user"])
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, 'a', 'aa', 0)",
      userId = s.userId,
    )
    check k != frameKey(s.db, "map/activities/routes", some "sel", @["file"]) # the data
  test "the same frame of another database is another key; so is another selection that looks the same":
    let a = open("framea")
    let b = open("frameb")
    defer:
      a.close()
      b.close()
    check frameKey(a.db, "f", none string, @["file"]) !=
      frameKey(b.db, "f", none string, @["file"])
    # a frame whose selection and tables have the same key text is not the frame that has neither
    let t = tablesKey(a.db, @["file"])
    check frameKey(a.db, "f", some t, @["file"]) !=
      frameKey(a.db, "f", none string, @["file"])
