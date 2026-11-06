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
    check groups[0].members[0].unique == 2 and groups[0].members[1].unique == 0         # the two short rides matched only it; the long ride both
    let lines = duplicateLines(groups)
    check lines[0].startsWith("climbs that are nearly the same")
    check lines.anyIt(it.contains("2/3 efforts unique")) and lines.anyIt(it.contains("0/1 effort unique"))      # (the long ride also matched the short climb)
    check lines.filterIt(it.startsWith("hide:")) == @["hide: nch climbs --edit 'NAME' --retire"]      # one line, at the end, with NAME as the stand-in
    check lines[^1].startsWith("hide:")
    check groups[0].members[1].hideable and not groups[0].members[0].hideable
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

suite "climbs: duplicates, one line that shows how to hide":
  test "several groups: one hide line, at the end, with NAME as a stand-in":
    let groups = @[
      Group(members: @[Member(id: 1, name: "A₁", efforts: 5), Member(id: 2, name: "A₂", efforts: 2, hideable: true)]),
      Group(members: @[Member(id: 4, name: "B₁", efforts: 9), Member(id: 5, name: "B₂", efforts: 3, hideable: true)])]
    let lines = duplicateLines(groups)
    check lines.filterIt(it.startsWith("hide:")) == @["hide: nch climbs --edit 'NAME' --retire"]
    check lines[^1] == "hide: nch climbs --edit 'NAME' --retire"
  test "nothing that can be hidden (all retired, or none a copy of a more ridden one): no hide line":
    let lines = duplicateLines(@[Group(members: @[Member(id: 1, name: "A₁", efforts: 5),
                                                  Member(id: 2, name: "A₂", efforts: 2, retired: true, hideable: true)])])
    check not lines.anyIt(it.contains("hide:"))

suite "climbs: duplicates, retire the redundant":
  proc twoClimbs(name: string): Store =
    result = fresh(name)
    addRide(result, "default", "long", 1_000_000, 5.0, eastbound(5.0))
    addRide(result, "default", "short", 2_000_000, 5.0, eastbound(5.0, to0 = 3500.0))
    addRide(result, "default", "short2", 3_000_000, 5.0, eastbound(5.0, to0 = 3500.0))
    discard ensureClimbs(result)
  test "the climb whose every ride also matched a copy is retired; the one with rides of its own stays":
    let s = twoClimbs("retire1")
    defer: s.close()
    let done = retireCopies(s, @[])
    check done.len == 1 and done[0].efforts == 1          # (the long climb: its one ride also matched the short one)
    check s.count("sector where retired = 1") == 1
    check s.count("effort") == 4                          # (efforts are kept)
    check retireCopies(s, @[]).len == 0                   # (and the last of the group is never retired)
  test "--name chooses the groups; the empty text is all of them":
    let s = twoClimbs("retire2")
    defer: s.close()
    check retireCopies(s, @["zzz-no-such-name"]).len == 0
    check s.count("sector where retired = 1") == 0
    check retireCopies(s, @[""]).len == 1
  test "retired climbs give no coverage: the shorter climb is kept when the longer is already retired":
    let s = twoClimbs("retire3")
    defer: s.close()
    s.db.exec(sql"update sector set retired = 1 where id = 1")
    check retireCopies(s, @[]).len == 0
    check s.count("sector where retired = 1") == 1
  test "the least ridden goes first: a one-off is retired before a climb ridden often":
    let s = twoClimbs("retire4")
    defer: s.close()
    # the long climb has 1 effort and the short one 3: the long goes, not the short, whatever their gains
    s.db.exec(sql"update sector set gain_m = 1 where gain_m > 1 and id = (select sector_id from effort group by sector_id order by count(*) limit 1)")
    check retireCopies(s, @[])[0].efforts == 1
  test "--unretire shows the retired climbs of the chosen groups again":
    let s = twoClimbs("retire5")
    defer: s.close()
    check retireCopies(s, @[]).len == 1
    check unretireCopies(s, @["zzz-no-such-name"]).len == 0
    check s.count("sector where retired = 1") == 1
    check unretireCopies(s, @[]).len == 1
    check s.count("sector where retired = 1") == 0
