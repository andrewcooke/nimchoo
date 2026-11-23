import std/[options, os, sequtils, strutils, unittest]
import nimchoo/core/ids
import nimchoo/packages/db/[sqltext, statement, store]
import nimchoo/packages/tags/tag
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

let dir = getTempDir() / "nch-test-tags"

proc fresh(name: string): Session =
  removeDir(dir / name)
  createDir(dir / name)
  openSession(dir / name / "x.db", allFragments, access = allAccess)

proc activity(s: Session, name: string): ActivityId =
  ## An activity (in a file of its own) of the session's user.
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:user, :name, :name, 0)",
    user = s.userId,
    name = name,
  )
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t) select id, 0, 0, 10 from file where sha256 = :name",
    name = name,
  )
  ActivityId(s.db.scalar(int64, "select max(id) from activity"))

proc tag(text: string): Tag =
  parseTag(text).tag.get

proc matching(s: Session, patterns: varargs[string]): seq[int64] =
  ## The activities that have a tag matching every pattern.
  var ps: seq[TagPattern]
  for p in patterns:
    ps.add parsePattern(p).pattern.get
  s.db.query(
    int64, sqlOf("select a.id from activity a where 1") & tagsSql(ps) & " order by a.id"
  )

suite "tags: what a tag is":
  test "letters (accents too), digits, '-', '_' and ':'":
    for t in [
      "bike:cotic", "sport:cycling:road", "Arrayán", "año-2024", "bike_2", "a"
    ]:
      check parseTag(t).tag.isSome
      check parseTag(t).problem.isNone

  test "not empty, not starting with '-', nothing else (no space, no '*', no punctuation)":
    for t in ["", "-foo", "bike cotic", "bike:*", "a.b", "a/b", "a,b", "a?b", "a[b]"]:
      check parseTag(t).tag.isNone
      check parseTag(t).problem.isSome
    check parseTag("-foo").problem.get.contains("option")

  test "a pattern may hold '*' as well":
    check parsePattern("bike:*").pattern.isSome
    check parsePattern("*:road").pattern.isSome
    check parsePattern("-x*").pattern.isNone
    check parsePattern("a b*").pattern.isNone

  test "a tag is matched folded: lower case, no accents":
    check tag("Arrayán").folded == "arrayan"
    check tag("Bike:Cotic").folded == "bike:cotic"

suite "tags: kept and matched":
  test "tags are kept as given, one to a folded form, and go with their activity":
    let s = fresh("kept")
    defer:
      s.close()
    let a = s.activity("a")
    s.addTags(a, [tag("bike:Cotic"), tag("bike:cotic"), tag("Arrayán")])
    check s.tagsOf(a).mapIt($it) ==
      @["Arrayán", "bike:Cotic"] # (the first of two that fold the same)
    s.removeTags(a, [tag("ARRAYAN")])
    check s.tagsOf(a).mapIt($it) == @["bike:Cotic"]
    s.db.execute("delete from activity where id = :id", id = a)
    check s.db.scalar(int, "select count(*) from activity_tag") == 0

  test "a pattern matches whatever the case or accents; '*' is anything; several are \"and\"":
    let s = fresh("matched")
    defer:
      s.close()
    let a = s.activity("a")
    let b = s.activity("b")
    let c = s.activity("c")
    s.addTags(a, [tag("bike:cotic"), tag("sport:cycling:road")])
    s.addTags(b, [tag("bike:Brompton"), tag("sport:cycling")])
    s.addTags(c, [tag("sport:running"), tag("Arrayán")])
    check s.matching("bike:COTIC") == @[int64(a)]
    check s.matching("bike:*") == @[int64(a), int64(b)]
    check s.matching("sport:cycling") == @[int64(b)] # (exactly: not sport:cycling:road)
    check s.matching("sport:cycling*") == @[int64(a), int64(b)]
    check s.matching("sport:*:road") == @[int64(a)]
    check s.matching("arrayan") == @[int64(c)]
    check s.matching("bike:*", "sport:*:road") == @[int64(a)]
    check s.matching("bike:*", "sport:running").len == 0
