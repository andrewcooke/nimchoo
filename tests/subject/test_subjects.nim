## The subjects registry (subject/subjects.nim) and the activities as the default subject.

import std/[os, sequtils, unittest]
import nimchoo/core/extension
import nimchoo/packages/db/statement
import nimchoo/packages/subject/subjects
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

let dir = getTempDir() / "nch-test-subjects"

proc open(name: string): Session =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  openSession(path, allFragments, access = allAccess)

proc addSelected(s: Session, tag: string) =
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :name, 0)",
    userId = s.userId,
    name = tag,
  )
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t) select max(id), 0, 0, 1 from file"
  )
  s.db.execute(
    "insert into selection(user_id, activity_id) select :userId, max(id) from activity",
    userId = s.userId,
  )

suite "subjects: the real registry":
  test "exactly one is the default, and it is the activities":
    let all = extensions.get(subjectPoint)
    check all.len >= 1
    check all.filterIt(it.isDefault).len == 1
    check defaultSubject(all).name == "activities"
  test "names are unique, and each has a summary":
    let all = extensions.get(subjectPoint)
    check all.mapIt(it.name).deduplicate.len == all.len
    check all.allIt(it.summary.len > 0 and it.name.len > 0)

suite "subjects: the key of the activities' selection":
  test "the same while the selection is the same, and another when it changes":
    let s = open("sel")
    defer:
      s.close()
    let activities = defaultSubject(extensions.get(subjectPoint))
    let empty = activities.selectionKey(s)
    check empty == activities.selectionKey(s)
    s.addSelected("a")
    let one = activities.selectionKey(s)
    check one != empty
    s.addSelected("b")
    check activities.selectionKey(s) != one
    s.db.execute("delete from selection where activity_id = 2")
    check activities.selectionKey(s) == one
  test "it belongs to the user: another user's empty selection is not the same key":
    let s = open("user")
    defer:
      s.close()
    let activities = defaultSubject(extensions.get(subjectPoint))
    s.db.execute("insert into user(name) values ('bob')")
    let bob = openSession(dir / "user.db", allFragments, "bob", access = allAccess)
    defer:
      bob.close()
    check activities.selectionKey(s) != activities.selectionKey(bob)
