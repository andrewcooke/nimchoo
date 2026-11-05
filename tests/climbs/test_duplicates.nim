import std/[sequtils, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/climbs/[duplicates, work]
import nimchoo/db/store
import ../support/[climbdata, userdata]

suite "climbs: duplicates":
  test "climbs that largely overlap are grouped, the most ridden first, with the command to hide the others":
    let s = fresh("dups")
    defer: s.close()
    addRide(s, "default", "long", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "default", "short", 2_000_000, 5.0, eastbound(5.0, to0 = 3500.0))
    addRide(s, "default", "short2", 3_000_000, 5.0, eastbound(5.0, to0 = 3500.0))
    discard ensureClimbs(s)
    let groups = duplicateGroups(s)
    check groups.len == 1 and groups[0].members.len == 2
    check groups[0].members[0].efforts == 3 and groups[0].members[1].efforts == 1      # the shorter one is the most ridden
    let lines = duplicateLines(groups)
    check lines[0].startsWith("climbs that largely overlap")
    check lines.anyIt(it.contains("3 efforts")) and lines.anyIt(it.contains("1 effort"))
    check lines.anyIt(it.strip.startsWith("hide: nch sector --edit \"unnamed (1/2)\" --retire"))      # the longer, biggest gain, is (1/2)
    check groups[0].members[1].hideable and not groups[0].members[0].hideable
    check not lines.anyIt(it.contains("unnamed (2/2)\" --retire"))                      # (the most ridden is not offered)
  test "climbs far apart, or one climb, are not duplicates":
    let s = fresh("nodups")
    defer: s.close()
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "default", "north", 2_000_000, 5.0, eastbound(5.0), northM = 5000.0)
    discard ensureClimbs(s)
    check s.count("sector") == 2
    check duplicateGroups(s).len == 0
    check duplicateLines(@[]) == @["no climbs overlap: nothing to tidy"]
  test "retired ones are in the report, marked, and are not offered again":
    let s = fresh("dupsretired")
    defer: s.close()
    addRide(s, "default", "long", 1_000_000, 5.0, eastbound(5.0))
    addRide(s, "default", "short", 2_000_000, 5.0, eastbound(5.0, to0 = 3500.0))
    discard ensureClimbs(s)
    s.db.exec(sql"update sector set retired = 1 where id = 1")
    let lines = duplicateLines(duplicateGroups(s))
    check lines.anyIt(it.contains("retired")) and not lines.anyIt(it.contains("--retire"))
