## Completing the sports of `nch activities` (src/nimchoo/packages/activities/completion.nim).

import std/unittest
import nimchoo/packages/db/statement
import nimchoo/packages/activities/completion
import nimchoo/packages/user/[session, users]
import ../support/completiondb
from nimchoo/registry import allFragments, allAccess

proc addActivity(s: Session, tag, sport, subSport: string) =
  ## An activity of the user of `s` (`sport` "": none recorded).
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :name, 0)",
    userId = s.userId,
    name = tag,
  )
  let f = s.db.scalar(int64, "select max(id) from file")
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t, sport, sub_sport) values (:fileId, 0, 0, 10, nullif(:sport, ''), nullif(:subSport, ''))",
    fileId = f,
    sport = sport,
    subSport = subSport,
  )

suite "completing sports":
  test "the sports of the user's activities, each once, that start with what is typed":
    let s = freshDb("sports")
    s.addActivity("a", "cycling", "road")
    s.addActivity("b", "cycling", "mountain")
    s.addActivity("c", "running", "")
    s.addActivity("d", "", "")
    let g = s.completing()
    s.close()
    check completeSports(g, "") == @["cycling", "running"]
    check completeSports(g, "c") == @["cycling"]
    check completeSports(g, "R") == @["running"]
    check completeSubSports(g, "") == @["mountain", "road"]
    check completeSubSports(g, "r") == @["road"]

  test "another user's sports are not offered, and --user says whose are":
    let s = freshDb("sports-users")
    s.addActivity("a", "cycling", "")
    s.addUser("bob")
    let b = openSession(s.path, allFragments, "bob", allAccess)
    b.addActivity("b", "running", "")
    b.close()
    let mine = s.completing()
    let bobs = s.completing("bob")
    s.close()
    check completeSports(mine, "") == @["cycling"]
    check completeSports(bobs, "") == @["running"]
