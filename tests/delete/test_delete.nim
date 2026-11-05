import std/[os, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/delete/[command, remove]
import nimchoo/modules
import ../support/userdata

let dir = getTempDir() / "nch-test-delete"

proc fresh(name: string): string =
  removeDir(dir / name)
  createDir(dir / name)
  dir / name / "x.db"

proc run(db: string, args: varargs[string], user = ""): int =
  command.run(globals(db, user), @args)

proc extra(s: Store, tag: string, session, startT: int, sport = "") =
  ## A second activity (another session) in the file `tag`.
  let f = s.db.getValue(sql"select id from file where name = ?", tag)
  s.db.exec(sql"insert into activity(file_id, session, start_t, end_t, sport) values (?, ?, ?, ?, nullif(?, ''))",
            f, session, startT, startT + 10, sport)
  s.db.exec(sql"insert into selection(user_id, activity_id) select ?, max(id) from activity", s.userId)

suite "delete: the plan":
  test "the selected activities of the user, their files, the sports and the dates; those of others counted apart":
    let d = fresh("plan")
    openStore(d, allFragments).close()                      # (the database, so that a user can be added)
    addUser(d, "bob")
    let s = openStore(d, allFragments)
    defer: s.close()
    fill(s, "a")
    fill(s, "b")
    s.db.exec(sql"update activity set start_t = 1535371200, sport = 'cycling' where file_id = (select id from file where name = 'a')")
    s.db.exec(sql"update activity set start_t = 1535500000, sport = 'running' where file_id = (select id from file where name = 'b')")
    let bob = openStore(d, allFragments, "bob")
    defer: bob.close()
    fill(bob, "c")
    s.db.exec(sql"insert into selection(user_id, activity_id) select ?, a.id from activity a join file f on f.id = a.file_id where f.name = 'c'", s.userId)
    let p = planDelete(s)
    check p.ids.len == 2 and p.fileIds.len == 2 and p.others == 1
    check p.sports == @[("cycling", 1), ("running", 1)]
    check describe(p) == "2 activities (cycling 1, running 1) from 2018-08-27 to 2018-08-28"
    check describe(Plan()) == "0 activities"
  test "one activity, one day; no sport recorded":
    let d = fresh("one")
    let s = openStore(d, allFragments)
    defer: s.close()
    fill(s, "a")
    s.db.exec(sql"update activity set start_t = 1535371200")
    check describe(planDelete(s)) == "1 activity (no sport 1) on 2018-08-27"

suite "delete: the command":
  test "without -f nothing is deleted; with -f the activities and what was made from them go, the climbs stay":
    let d = fresh("basic")
    let s = openStore(d, allFragments)
    fill(s, "a")
    fill(s, "b")
    s.db.exec(sql"insert into sector(length_m, gain_m, gradient, name) values (1000, 50, 5, 'Cerro')")
    s.db.exec(sql"""insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m)
      select 1, id, 1, 61, 60, 0 from activity""")
    s.db.exec(sql"insert into climbs_done(activity_id, version) select id, 1 from activity")
    s.close()
    check run(d) == exitFailure
    let before = openStore(d, allFragments)
    check before.count("activity") == 2 and before.count("effort") == 2
    before.close()
    check run(d, "-f") == exitOk
    let after = openStore(d, allFragments)
    defer: after.close()
    for t in ["activity", "coords", "segment", "selection", "effort", "climbs_done", "file", "seen_file"]:
      check after.count(t) == 0
    check after.count("sector") == 1 and after.db.getValue(sql"select name from sector") == "Cerro"
  test "only the selection is deleted":
    let d = fresh("only")
    let s = openStore(d, allFragments)
    fill(s, "a")
    fill(s, "b")
    s.db.exec(sql"delete from selection where activity_id = (select a.id from activity a join file f on f.id = a.file_id where f.name = 'b')")
    s.close()
    check run(d, "-f") == exitOk
    let after = openStore(d, allFragments)
    defer: after.close()
    check after.count("activity") == 1 and after.db.getValue(sql"select name from file") == "b"
    check after.count("seen_file") == 1 and after.count("coords") == 1
  test "activities of other users are left alone; they say so":
    let d = fresh("others")
    openStore(d, allFragments).close()                      # (the database, so that a user can be added)
    addUser(d, "bob")
    let s = openStore(d, allFragments)
    fill(s, "mine")
    let bob = openStore(d, allFragments, "bob")
    fill(bob, "bobs")
    s.db.exec(sql"insert into selection(user_id, activity_id) select ?, a.id from activity a join file f on f.id = a.file_id where f.name = 'bobs'", s.userId)
    bob.close()
    s.close()
    check run(d, "-f") == exitOk
    let after = openStore(d, allFragments)
    defer: after.close()
    check after.count("activity") == 1 and after.db.getValue(sql"select name from file") == "bobs"
  test "only the user's own selection is looked at: --user":
    let d = fresh("user")
    openStore(d, allFragments).close()                      # (the database, so that a user can be added)
    addUser(d, "bob")
    let s = openStore(d, allFragments)
    fill(s, "mine")
    let bob = openStore(d, allFragments, "bob")
    fill(bob, "bobs")
    bob.close()
    s.close()
    check run(d, "-f", user = "bob") == exitOk
    let after = openStore(d, allFragments)
    defer: after.close()
    check after.count("activity") == 1 and after.db.getValue(sql"select name from file") == "mine"
  test "a file that holds other activities is kept until the last goes":
    let d = fresh("sessions")
    let s = openStore(d, allFragments)
    fill(s, "tri")
    s.extra("tri", 1, 100, "swimming")
    s.db.exec(sql"delete from selection where activity_id = (select min(id) from activity)")        # only the second is selected
    s.close()
    check run(d, "-f") == exitOk
    let mid = openStore(d, allFragments)
    check mid.count("activity") == 1 and mid.count("file") == 1 and mid.count("seen_file") == 1    # (the file stays)
    mid.db.exec(sql"insert into selection(user_id, activity_id) select ?, id from activity", mid.userId)
    mid.close()
    check run(d, "-f") == exitOk
    let after = openStore(d, allFragments)
    defer: after.close()
    check after.count("activity") == 0 and after.count("file") == 0 and after.count("seen_file") == 0
  test "nothing selected, or only others' activities: said, and not an error":
    let d = fresh("none")
    openStore(d, allFragments).close()                      # (the database, so that a user can be added)
    addUser(d, "bob")
    let s = openStore(d, allFragments)
    fill(s, "a")
    s.db.exec(sql"delete from selection")
    s.close()
    check run(d, "-f") == exitOk
    let again = openStore(d, allFragments)
    check again.count("activity") == 1
    let bob = openStore(d, allFragments, "bob")
    fill(bob, "bobs")
    again.db.exec(sql"insert into selection(user_id, activity_id) select ?, a.id from activity a join file f on f.id = a.file_id where f.name = 'bobs'", again.userId)
    bob.close()
    again.close()
    check run(d, "-f") == exitOk
    let last = openStore(d, allFragments)
    defer: last.close()
    check last.count("activity") == 2
  test "bad arguments, and help":
    let d = fresh("args")
    check run(d, "--help") == exitOk
    check run(d, "--nonesuch") == exitUsage
    check run(d, "x") == exitUsage
    check not fileExists(d)
