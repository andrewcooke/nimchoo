import nimchoo/db/statement
import std/[os, unittest]
import nimchoo/core/globals
import nimchoo/db/store
import nimchoo/delete/[remove, run]
import nimchoo/selection/command as activitiesCommand
import nimchoo/packages/ui/style
import nimchoo/modules
import ../support/userdata

let dir = getTempDir() / "nch-test-delete"

proc fresh(name: string): string =
  removeDir(dir / name)
  createDir(dir / name)
  dir / name / "x.db"

proc runAs(db, user: string, args: varargs[string]): int =
  ## nch --user USER activities --delete ARGS
  activitiesCommand.run(globals(db, user), @["--delete"] & @args)

proc run(db: string, args: varargs[string]): int =
  ## nch activities --delete ARGS
  runAs(db, "", @args)

proc selected(s: Store): seq[int64] =
  ## The ids of the user's selection.
  s.db.query(
    int64,
    "select activity_id from selection where user_id = :userId order by 1",
    userId = s.userId,
  )

proc extra(s: Store, tag: string, session, startT: int, sport = "") =
  ## A second activity (another session) in the file `tag`.
  let f = s.db.scalar(int64, "select id from file where name = :name", name = tag)
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t, sport) values (:fileId, :session, :startT, :endT, nullif(:sport, ''))",
    fileId = f,
    session = session,
    startT = startT,
    endT = startT + 10,
    sport = sport,
  )
  s.db.execute(
    "insert into selection(user_id, activity_id) select :userId, max(id) from activity",
    userId = s.userId,
  )

suite "delete: the plan":
  test "the activities, their files, the sports and the dates":
    let d = fresh("plan")
    let s = openStore(d, allFragments)
    defer:
      s.close()
    fill(s, "a")
    fill(s, "b")
    s.db.execute(
      "update activity set start_t = 1535371200, sport = 'cycling' where file_id = (select id from file where name = 'a')"
    )
    s.db.execute(
      "update activity set start_t = 1535500000, sport = 'running' where file_id = (select id from file where name = 'b')"
    )
    let p = planDelete(s, s.selected)
    check p.ids.len == 2 and p.fileIds.len == 2
    check p.sports == @[("cycling", 1), ("running", 1)]
    check describe(p) ==
      "2 activities (cycling 1, running 1) from 2018-08-27 to 2018-08-28"
    check describe(Plan()) == "0 activities"
  test "only the user's own activities are planned, whatever ids are given":
    let d = fresh("planown")
    openStore(d, allFragments).close()
    addUser(d, "bob")
    let s = openStore(d, allFragments)
    defer:
      s.close()
    fill(s, "mine")
    let bob = openStore(d, allFragments, "bob")
    defer:
      bob.close()
    fill(bob, "bobs")
    let p = planDelete(s, @[1'i64, 2'i64])
    check p.ids == @[1'i64]
  test "one activity, one day; no sport recorded":
    let d = fresh("one")
    let s = openStore(d, allFragments)
    defer:
      s.close()
    fill(s, "a")
    s.db.execute("update activity set start_t = 1535371200")
    check describe(planDelete(s, s.selected)) == "1 activity (no sport 1) on 2018-08-27"

suite "delete: the command":
  test "without -f nothing is deleted; with -f the activities and what was made from them go, the climbs stay":
    let d = fresh("basic")
    let s = openStore(d, allFragments)
    fill(s, "a")
    fill(s, "b")
    s.db.execute(
      "insert into sector(length_m, gain_m, gradient, name) values (1000, 50, 5, 'Cerro')"
    )
    s.db.execute(
      """insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m)
      select 1, id, 1, 61, 60, 0 from activity"""
    )
    s.db.execute(
      "insert into climbs_done(activity_id, version) select id, 1 from activity"
    )
    s.close()
    check run(d) == exitFailure
    let before = openStore(d, allFragments)
    check before.count("activity") == 2 and before.count("effort") == 2
    before.close()
    check run(d, "-f") == exitOk
    let after = openStore(d, allFragments)
    defer:
      after.close()
    for t in [
      "activity", "coords", "segment", "selection", "effort", "climbs_done", "file",
      "seen_file",
    ]:
      check after.count(t) == 0
    check after.count("sector") == 1 and
      after.db.scalar(string, "select name from sector") == "Cerro"
  test "only the selection is deleted":
    let d = fresh("only")
    let s = openStore(d, allFragments)
    fill(s, "a")
    fill(s, "b")
    s.db.execute(
      "delete from selection where activity_id = (select a.id from activity a join file f on f.id = a.file_id where f.name = 'b')"
    )
    s.close()
    check run(d, "-f") == exitOk
    let after = openStore(d, allFragments)
    defer:
      after.close()
    check after.count("activity") == 1 and
      after.db.scalar(string, "select name from file") == "b"
    check after.count("seen_file") == 1 and after.count("coords") == 1
  test "only the user's own selection is looked at: --user":
    let d = fresh("user")
    openStore(d, allFragments).close() # (the database, so that a user can be added)
    addUser(d, "bob")
    let s = openStore(d, allFragments)
    fill(s, "mine")
    let bob = openStore(d, allFragments, "bob")
    fill(bob, "bobs")
    bob.close()
    s.close()
    check runAs(d, "bob", "-f") == exitOk
    let after = openStore(d, allFragments)
    defer:
      after.close()
    check after.count("activity") == 1 and
      after.db.scalar(string, "select name from file") == "mine"
  test "a file that holds other activities is kept until the last goes":
    let d = fresh("sessions")
    let s = openStore(d, allFragments)
    fill(s, "tri")
    s.extra("tri", 1, 100, "swimming")
    s.db.execute(
      "delete from selection where activity_id = (select min(id) from activity)"
    ) # only the second is selected
    s.close()
    check run(d, "-f") == exitOk
    let mid = openStore(d, allFragments)
    check mid.count("activity") == 1 and mid.count("file") == 1 and
      mid.count("seen_file") == 1 # (the file stays)
    mid.db.execute(
      "insert into selection(user_id, activity_id) select :userId, id from activity",
      userId = mid.userId,
    )
    mid.close()
    check run(d, "-f") == exitOk
    let after = openStore(d, allFragments)
    defer:
      after.close()
    check after.count("activity") == 0 and after.count("file") == 0 and
      after.count("seen_file") == 0
  test "nothing selected: said, and not an error":
    let d = fresh("none")
    let s = openStore(d, allFragments)
    fill(s, "a")
    s.db.execute("delete from selection")
    s.close()
    check run(d, "-f") == exitOk
    let again = openStore(d, allFragments)
    defer:
      again.close()
    check again.count("activity") == 1
  test "criteria pick the activities, with no need of a selection":
    let d = fresh("criteria")
    let s = openStore(d, allFragments)
    fill(s, "run")
    fill(s, "ride")
    fill(s, "ride2")
    s.db.execute(
      "update activity set sport = 'running' where file_id = (select id from file where name = 'run')"
    )
    s.db.execute(
      "update activity set sport = 'cycling' where file_id <> (select id from file where name = 'run')"
    )
    s.db.execute("delete from selection")
    s.close()
    check run(d, "--sport", "cycling") == exitFailure # no -f: nothing done
    let before = openStore(d, allFragments)
    check before.count("activity") == 3
    before.close()
    check run(d, "--sport", "cycling", "-f") == exitOk
    let after = openStore(d, allFragments)
    defer:
      after.close()
    check after.count("activity") == 1 and
      after.db.scalar(string, "select sport from activity") == "running"
  test "--all deletes every activity of the user, and not another user's":
    let d = fresh("all")
    openStore(d, allFragments).close()
    addUser(d, "bob")
    let s = openStore(d, allFragments)
    fill(s, "a")
    fill(s, "b")
    let bob = openStore(d, allFragments, "bob")
    fill(bob, "bobs")
    bob.close()
    s.db.execute("delete from selection")
    s.close()
    check run(d, "--all", "-f") == exitOk
    let after = openStore(d, allFragments)
    defer:
      after.close()
    check after.count("activity") == 1 and
      after.db.scalar(string, "select name from file") == "bobs"
    check after.count("user") == 2 # (the users stay)
  test "no activity meets the criteria: said, not an error":
    let d = fresh("nomatch")
    let s = openStore(d, allFragments)
    fill(s, "a")
    s.close()
    check run(d, "--sport", "swimming", "-f") == exitFailure
      # (nobody has the sport: refused, as for any listing)
    check run(d, "--from", "2030-01-01", "-f") == exitOk
    let after = openStore(d, allFragments)
    defer:
      after.close()
    check after.count("activity") == 1
  test "bad arguments, and help":
    let d = fresh("args")
    check run(d, "--help") == exitOk
    check run(d, "--nonesuch") == exitUsage
    check run(d, "x") == exitUsage
    check activitiesCommand.run(globals(d), @["-f"]) == exitUsage # -f goes with --delete
    check activitiesCommand.run(globals(d), @["--all", "--delete", "--select"]) ==
      exitUsage
    check activitiesCommand.run(globals(d), @["--all", "--delete", "-v"]) == exitUsage
    check not fileExists(d)

suite "delete: progress":
  test "the report comes after each chunk: how many activities are gone and how many files are forgotten":
    let d = fresh("progress")
    let s = openStore(d, allFragments)
    defer:
      s.close()
    for i in 1 .. 60:
      fill(s, "t" & $i)
    var seen: seq[(int, int, int)]
    let done = deleteActivities(
      s,
      planDelete(s, s.selected),
      proc(n, total, files: int) {.closure, raises: [].} =
        seen.add (n, total, files)
      ,
    )
    check seen == @[(25, 60, 25), (50, 60, 50), (60, 60, 60)]
    check done == Done(activities: 60, files: 60, kept: 0)
    check s.count("activity") == 0 and s.count("file") == 0
  test "a file with activities in two chunks is forgotten when the later one goes; one that keeps an activity stays":
    let d = fresh("progressfiles")
    let s = openStore(d, allFragments)
    defer:
      s.close()
    fill(s, "tri") # activity 1, file tri
    for i in 1 .. 29:
      fill(s, "t" & $i) # activities 2 .. 30
    s.extra("tri", 1, 100, "swimming")
      # activity 31: a second session of tri, in the second chunk
    fill(s, "keeper") # activity 32: its file will keep another activity
    s.extra("keeper", 1, 200, "running") # activity 33
    s.db.execute("delete from selection where activity_id = 33")
    var seen: seq[(int, int, int)]
    let done = deleteActivities(
      s,
      planDelete(s, s.selected),
      proc(n, total, files: int) {.closure, raises: [].} =
        seen.add (n, total, files)
      ,
    )
    check seen ==
      @[(25, 32, 24), (32, 32, 30)]
        # tri stays in the first chunk (its second session is to come)
    check done.activities == 32 and done.kept == 1 and done.files == 30
      # (tri and the 29 others; keeper stays)
    check s.count("activity") == 1 and
      s.db.scalar(string, "select name from file") == "keeper"

suite "delete: the display":
  test "two lines, as the import's: the word in bold, then the counts in red joined by grey dots":
    let lines = deletingLines(340, 1381, 120)
    check lines.len == 2
    check lines[0].text == "deleting 340 / 1,381 activities"
    check lines[0][0].look.bold and lines[0][0].text == "deleting "
    check lines[1].text == "activities 340 · files 120"
    check lines[1][0].look.colour == red and lines[1][2].look.colour == red
    check lines[1][1].text == " · " and lines[1][1].look.colour == grey
    check deletingLines(1, 1, 1)[0].text == "deleting 1 / 1 activity"
