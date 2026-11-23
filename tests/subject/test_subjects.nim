## The subjects registry (subject/subjects.nim) and the activities as the default subject.

import std/[options, os, sequtils, unittest]
import nimchoo/core/line
import nimchoo/packages/util/args/args
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
    "insert into activity_selection(user_id, activity_id) select :userId, max(id) from activity",
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

suite "subjects: the activities' selection":
  test "how many it holds follows the selection, and is the user's own":
    let s = open("sel")
    defer:
      s.close()
    let activities = defaultSubject(extensions.get(subjectPoint))
    check activities.selected(s) == 0
    s.addSelected("a")
    s.addSelected("b")
    check activities.selected(s) == 2
    s.db.execute("insert into user(name) values ('bob')")
    let bob = openSession(dir / "sel.db", allFragments, some("bob"), access = allAccess)
    defer:
      bob.close()
    check activities.selected(bob) == 0

suite "subjects: choosing one by name, for every view":
  let all = @[Subject(name: "activities", isDefault: true), Subject(name: "climbs")]
  test "a name is lower case letters and digits":
    check isWord("climbs") and isWord("a1")
    for bad in ["", "Climbs", "a-b", "a b"]:
      check not isWord(bad)
  test "the positional SUBJECT is taken, once at a time":
    var names: seq[string]
    check takeSubject(names, "climbs").isNone and names == @["climbs"]
    check takeSubject(names, "No").isSome and names == @["climbs"]
  test "none given is the default; a name is found; another is not":
    check findSubject(all, none(string)).get.name == "activities"
    check findSubject(all, some("climbs")).get.name == "climbs"
    check findSubject(all, some("nothing")).isNone
  test "what is said when there is none is the same for every view":
    check noSubject(all, some("nothing"), "a map").plainText ==
      "no subject 'nothing' (the subjects are activities, climbs)"
    check noSubject(@[], none(string), "a calendar").plainText ==
      "no subject can be shown on a calendar"
