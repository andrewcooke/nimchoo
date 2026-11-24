## Completing the tags of `nch activities --tags` (src/nimchoo/packages/activities/completion.nim).

import std/[options, unittest]
import nimchoo/core/ids
import nimchoo/packages/db/statement
import nimchoo/packages/activities/completion
import nimchoo/packages/tags/tag
import nimchoo/packages/user/[session, users]
import ../support/completiondb
from nimchoo/registry import allFragments, allAccess

proc addActivity(s: Session, name: string, tags: varargs[string]) =
  ## An activity of the user of `s`, with these tags.
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_epoch) values (:userId, :name, :name, 0)",
    userId = s.userId,
    name = name,
  )
  let f = s.db.scalar(int64, "select max(id) from file")
  s.db.execute(
    "insert into activity(file_id, session, start_epoch, end_epoch) values (:fileId, 0, 0, 10)",
    fileId = f,
  )
  var ts: seq[Tag]
  for t in tags:
    ts.add parseTag(t).tag.get
  s.addTags(ActivityId(s.db.scalar(int64, "select max(id) from activity")), ts)

suite "completing tags":
  test "the tags of the user's activities, each once, that start with what is typed (case and accents aside)":
    let s = freshDb("tags")
    s.addActivity("a", "sport:cycling:road", "bike:Cotic")
    s.addActivity("b", "sport:cycling:road", "Arrayán")
    s.addActivity("c", "sport:running")
    s.addActivity("d")
    let g = s.completing()
    s.close()
    check completeTags(g, "") ==
      @["Arrayán", "bike:Cotic", "sport:cycling:road", "sport:running"]
    check completeTags(g, "sport:c") == @["sport:cycling:road"]
    check completeTags(g, "BIKE") == @["bike:Cotic"]
    check completeTags(g, "arraya") == @["Arrayán"]

  test "another user's tags are not offered, and --user says whose are":
    let s = freshDb("tags-users")
    s.addActivity("a", "sport:cycling")
    s.addUser("bob")
    let b = openSession(s.path, allFragments, some("bob"), allAccess)
    b.addActivity("b", "sport:running")
    b.close()
    let mine = s.completing()
    let bobs = s.completing("bob")
    s.close()
    check completeTags(mine, "") == @["sport:cycling"]
    check completeTags(bobs, "") == @["sport:running"]
