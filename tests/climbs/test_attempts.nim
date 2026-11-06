import std/[strutils, times, unittest]
import db_connector/db_sqlite
import nimchoo/climbs/[attempts, display, work]
import nimchoo/db/store
import ../support/[climbdata, userdata]

suite "attempts: the ranks":
  test "one plus the number that are faster; equal times share a rank":
    check rankOf([500.0, 480.0, 520.0], 500.0) == 2
    check rankOf([500.0, 500.0, 520.0], 500.0) == 1
    check rankOf([500.0], 500.0) == 1

proc world(name: string): Store =
  ## The default user rode at 5 and at 6 m/s, bob at 4 m/s; only the slowest-but-one ride is selected.
  let s = fresh(name)
  addUser(s.path, "bob")
  addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
  addRide(s, "bob", "two", 2_000_000, 4.0, eastbound(4.0))
  addRide(s, "default", "three", 3_000_000, 6.0, eastbound(6.0))
  discard ensureClimbs(s)
  s.db.exec(sql"insert into selection(user_id, activity_id) select ?, id from activity where start_t = 1000000", s.userId)
  s

suite "attempts: from the tables":
  test "the selection chooses the climbs, not the attempts: every attempt of the user counts":
    let s = world("attempts-selection")
    defer: s.close()
    let ids = selectedClimbs(s)
    check ids.len == 1
    let sums = summaries(s, ids)
    check sums[0].attempts.len == 2                    # the selected ride and the other, which is not selected
    check sums[0].attempts[0].activity.startT.int64 == 1_000_000 and sums[0].attempts[0].rank == 2
    check sums[0].attempts[1].rank == 1 and sums[0].attempts[1].total == 2
  test "the leaderboard compares people's best times, not attempts":
    let s = world("attempts-riders")
    defer: s.close()
    let r = summaries(s, selectedClimbs(s))[0].riders
    check r.len == 2
    check r[0].user == "default" and r[0].rank == 1 and r[0].me and r[0].total == 2    # (the 6 m/s ride)
    check r[1].user == "bob" and r[1].rank == 2 and not r[1].me
  test "nothing is selected: no climbs; a retired climb is hidden":
    let s = world("attempts-none")
    defer: s.close()
    s.db.exec(sql"delete from selection")
    check selectedClimbs(s).len == 0
    s.db.exec(sql"insert into selection(user_id, activity_id) select ?, id from activity", s.userId)
    check selectedClimbs(s).len == 1
    s.db.exec(sql"update sector set retired = 1")
    check selectedClimbs(s).len == 0
    check namedClimbs(s, @["unnamed"]).len == 0
  test "--name: the climbs whose shown name holds the text, case and accents ignored":
    let s = world("attempts-name")
    defer: s.close()
    s.db.exec(sql"update sector set name = 'Cuesta Chacabuco', manual = 1")
    check namedClimbs(s, @["chacabuco"]).len == 1
    check namedClimbs(s, @["CUESTA"]).len == 1
    check namedClimbs(s, @["nothing", "cuesta"]).len == 1
    check namedClimbs(s, @["farellones"]).len == 0
    s.db.exec(sql"delete from selection")                  # (the selection is not looked at)
    check namedClimbs(s, @["cuesta"]).len == 1

suite "attempts: the lines":
  test "the summary of the user's attempts, and with -v the attempts, the fastest first":
    let s = world("lines-own")
    defer: s.close()
    let rows = summaries(s, selectedClimbs(s))
    let table = summaryLines(rows, everyone = false, verbose = false, zone = utc())
    check table.len == 2
    check table[0].startsWith("climb") and "attempts" in table[0] and table[0].endsWith("rank")
    check table[1].startsWith(unnamed) and table[1].endsWith("1 of 2")          # the latest is the faster
    let long = summaryLines(rows, false, true, utc())
    check long.len == 4 and long[0] == table[0] and long[1] == table[1]
    check long[2].strip.startsWith("1 of 2") and long[3].strip.startsWith("2 of 2")
    check long[2].startsWith("    ") and "1970-02-" in long[2]
  test "with everyone: the people, never the personal rank":
    let s = world("lines-everyone")
    defer: s.close()
    let rows = summaries(s, selectedClimbs(s))
    let table = summaryLines(rows, true, false, utc())
    check "riders" in table[0] and "fastest" in table[0] and "attempts" notin table[0]
    check table[1].endsWith("1 of 2") and "default" in table[1]
    let long = summaryLines(rows, true, true, utc())
    check long.len == 4 and "default (you)" in long[2] and "bob" in long[3]
  test "a climb you never rode: dashes":
    let s = world("lines-never")
    defer: s.close()
    s.db.exec(sql"update file set user_id = (select id from user where name = 'bob')")
    let table = summaryLines(summaries(s, selectedClimbs(s)), false, false, utc())
    check "0" in table[1] and table[1].endsWith("-")
