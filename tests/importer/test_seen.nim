import std/[options, os, tables, unittest]
import nimchoo/core/ids
import nimchoo/packages/db/statement
import nimchoo/packages/importer/[failure, seen]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

let dir = getTempDir() / "nch-test-seen"

proc fresh(name: string): Session =
  removeDir(dir / name)
  createDir(dir / name)
  openSession(dir / name / "x.db", allFragments, access = allAccess)

suite "seen: what the import remembers of a path":
  test "a file or a failure, read back as it was written":
    let s = fresh("roundtrip")
    defer:
      s.close()
    s.db.execute(
      "insert into file(id, user_id, name, sha256, imported_epoch) values (7, :u, 'a', 'x', 0)",
      u = s.userId,
    )
    var b: SeenBuffer
    b.add "/a.fit", Seen(size: 10, mtime: 20, kind: skFile, fileId: ids.FileId(7))
    b.add "/b.fit",
      Seen(size: 11, mtime: 21, kind: skFailure, failure: fkBadFormat, message: "bad")
    s.flush(b)
    let t = loadSeen(s)
    check t["/a.fit"].kind == skFile and t["/a.fit"].fileId == ids.FileId(7)
    check t["/b.fit"].failed and t["/b.fit"].failure == fkBadFormat and
      t["/b.fit"].message == "bad"
    check t["/a.fit"].matches(10, 20) and not t["/a.fit"].matches(10, 21)
  test "a row of a kind this program does not know, or of neither, is not kept: the file is looked at again":
    let s = fresh("unknown")
    defer:
      s.close()
    s.db.execute(
      "insert into seen_file(user_id, path, size, modified_epoch, failure, message) values (:u, '/x', 1, 1, 'from_the_future', 'm')",
      u = s.userId,
    )
    s.db.execute(
      "insert into seen_file(user_id, path, size, modified_epoch) values (:u, '/y', 1, 1)",
      u = s.userId,
    )
    check loadSeen(s).len == 0
  test "labels of failures":
    check kindOf("bad_format") == some(fkBadFormat)
    check kindOf("nope").isNone
