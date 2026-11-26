import std/[options, os, unittest]
import nimchoo/core/ids
import nimchoo/packages/db/statement
import nimchoo/packages/tags/[sport, tag]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess
import ../support/userdata

let dir = getTempDir() / "nch-test-tags-sport"

suite "tags: an activity's sport":
  test "the text of the tag as the sport and the sub-sport":
    check sportParts("cycling:road") == ("cycling", "road")
    check sportParts("cycling") == ("cycling", "")
    check sportParts("cycling:road:fast") == ("cycling", "road:fast")
    check sportParts("") == ("", "")

  test "the sport is the sport: tag, as given; the first of several; none, nothing; another tag is not one":
    removeDir(dir)
    createDir(dir)
    let s = openSession(dir / "x.db", allFragments, access = allAccess)
    defer:
      s.close()
    for name in ["none", "one", "two", "case", "other"]:
      fill(s, name)
    proc give(name: string, tags: varargs[string]) =
      let a = s.db.scalar(
        int64,
        "select a.id from activity a join file f on f.id = a.file_id where f.name = :name",
        name = name,
      )
      for t in tags:
        s.addTags(ActivityId(a), [parseTag(t).tag.get])

    give("one", "sport:cycling:road", "bike:cotic")
    give("two", "sport:running", "sport:cycling")
    give("case", "Sport:Cycling:Gravel")
    give("other", "sportive", "sport")
    var got: seq[(string, string)]
    for r in s.db.query(
      (string, string),
      "select f.name, " & sportSql() &
        " from activity a join file f on f.id = a.file_id order by a.id",
    ):
      got.add r
    check got ==
      @[
        ("none", ""),
        ("one", "cycling:road"),
        ("two", "cycling"), # (the first in the order of their folded forms)
        ("case", "Cycling:Gravel"),
        ("other", ""),
      ]
