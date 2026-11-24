## `nch tags`: what a scope means, and adding, removing and renaming (src/nimchoo/packages/tags/found.nim).

import std/[options, os, sequtils, unittest]
import nimchoo/core/ids
import nimchoo/packages/db/statement
import nimchoo/packages/tags/[found, params, tag]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

let dir = getTempDir() / "nch-test-tags-found"

proc pattern(t: string): TagPattern =
  parsePattern(t).pattern.get

proc world(name: string): Session =
  ## Three activities: a (bike:cotic, sport:cycling), b (bike:uk, sport:cycling), c (sport:running); a and c selected.
  removeDir(dir / name)
  createDir(dir / name)
  result = openSession(dir / name / "x.db", allFragments, access = allAccess)
  for (n, tags) in [
    ("a", @["bike:cotic", "sport:cycling"]),
    ("b", @["bike:uk", "sport:cycling"]),
    ("c", @["sport:running"]),
  ]:
    result.db.execute(
      "insert into file(user_id, name, sha256, imported_epoch) values (:user, :name, :name, 0)",
      user = result.userId,
      name = n,
    )
    result.db.execute(
      "insert into activity(file_id, session, start_epoch, end_epoch, riding_start_epoch, riding_end_epoch) select id, 0, 0, 10, 0, 10 from file where name = :name",
      name = n,
    )
    let id = ActivityId(result.db.scalar(int64, "select max(id) from activity"))
    result.addTags(id, tags.mapIt(parseTag(it).tag.get))
    if n != "b":
      result.db.execute(
        "insert into activity_selection(user_id, activity_id) values (:user, :id)",
        user = result.userId,
        id = id,
      )

let selection = TagScope(kind: tsSelection)
let all = TagScope(kind: tsAll)
proc named(within: bool, ps: varargs[string]): TagScope =
  TagScope(kind: tsMatching, patterns: ps.mapIt(pattern(it)), within: within)

suite "nch tags: what a scope means":
  test "the selection's tags, all of them, those matching (anywhere, or within the selection)":
    let s = world("scope")
    defer:
      s.close()
    check s.counts(selection) ==
      @[("bike:cotic", 1), ("sport:cycling", 1), ("sport:running", 1)]
    check s.counts(all) ==
      @[("bike:cotic", 1), ("bike:uk", 1), ("sport:cycling", 2), ("sport:running", 1)]
    check s.counts(named(false, "bike:*")) == @[("bike:cotic", 1), ("bike:uk", 1)]
    check s.counts(named(true, "bike:*")) == @[("bike:cotic", 1)]
    check s.counts(named(false, "BIKE:UK", "sport:running")) ==
      @[("bike:uk", 1), ("sport:running", 1)]

suite "nch tags: adding, removing, renaming":
  test "--add gives the tags to the activities of the scope (no criteria: the selected ones)":
    let s = world("add")
    defer:
      s.close()
    check s.addTo(selection, @[parseTag("hard").tag.get]) == (activities: 2, added: 2)
    check s.addTo(named(false, "sport:cycling"), @[parseTag("hard").tag.get]) ==
      (activities: 2, added: 1) # (a has it already)
    check s.counts(named(false, "hard")) == @[("hard", 3)]

  test "--delete removes the tags of the scope, and only those":
    let s = world("delete")
    defer:
      s.close()
    check s.remove(named(true, "sport:*")) == 2 # (a's and c's: b is not selected)
    check s.counts(all) == @[("bike:cotic", 1), ("bike:uk", 1), ("sport:cycling", 1)]

  test "--rename renames; where an activity has the new name already the two become one":
    let s = world("rename")
    defer:
      s.close()
    discard s.addTo(named(false, "bike:uk"), @[parseTag("bike:cotic").tag.get])
      # b: bike:uk and bike:cotic
    check s.merges(named(false, "bike:uk"), parseTag("bike:cotic").tag.get) == 1
    check s.rename(named(false, "bike:uk"), parseTag("bike:cotic").tag.get) == 1
    check s.counts(named(false, "bike:*")) == @[("bike:cotic", 2)]
    check s.rename(named(false, "bike:cotic"), parseTag("Bike:Cotic").tag.get) == 2
      # (a new case only)
    check s.counts(named(false, "bike:*")) == @[("Bike:Cotic", 2)]
