import nimchoo/db/statement
import std/[unittest]
import nimchoo/core/globals
import nimchoo/climbs/command as climbsCommand
import nimchoo/db/store
import nimchoo/core/ids
import nimchoo/modules
import ../support/[climbdata, userdata]

proc climbs(path: string, args: varargs[string], user = ""): int =
  climbsCommand.run(globals(path, user), @args)

suite "nch climbs":
  test "help, and a bad option":
    check climbsCommand.run(Globals(), @["--help"]) == exitOk
    check climbsCommand.run(Globals(), @["--bogus"]) == exitUsage
    check climbsCommand.run(Globals(), @["extra"]) == exitUsage

  test "an empty selection is said, with what to do, and is not an error":
    let s = fresh("command-empty")
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    let path = s.path
    s.close()
    check climbs(path) == exitOk
    # ... and the catalogue is there to list, and the climbs were worked out on the way
    check climbs(path, "--all") == exitOk
    let again = openStore(path, allFragments)
    defer:
      again.close()
    check again.count("sector") == 1 and again.count("climbs_done") == 1

  test "the climbs of the selected activities":
    let s = fresh("command-selected")
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    s.db.execute(
      "insert into selection(user_id, activity_id) select :userId, id from activity",
      userId = s.userId,
    )
    let path = s.path
    s.close()
    check climbs(path) == exitOk
    check climbs(path, "--all") == exitOk
    check climbsCommand.run(globals(path), @["-v"]) == exitOk
    check climbsCommand.run(globals(path), @["--everyone", "-v"]) == exitOk

  test "--name looks at all the climbs; no climb of that name is a failure":
    let s = fresh("command-name")
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    let path = s.path
    s.close()
    check climbsCommand.run(globals(path), @["--name", "unnamed"]) == exitOk
      # (nothing is selected)
    check climbsCommand.run(globals(path), @["--name", "nonesuch"]) == exitFailure
    check climbsCommand.run(globals(path), @["--name", "unnamed", "--all"]) == exitUsage

  test "--all --delete: nothing without -f; with -f the climbs and their efforts go, the rides stay, and they come back":
    let s = fresh("command-delete")
    addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
    let path = s.path
    s.close()
    check climbs(path, "--all") == exitOk # (works the climbs out)
    check climbs(path, "--all", "--delete") == exitFailure
    let before = openStore(path, allFragments)
    check before.count("sector") == 1
    before.close()
    check climbsCommand.run(globals(path), @["--all", "--delete", "-f"]) == exitOk
    let after = openStore(path, allFragments)
    check after.count("sector") == 0 and after.count("effort") == 0 and
      after.count("climbs_done") == 0
    check after.count("activity") == 1
    after.close()
    check climbs(path, "--all") == exitOk # (and they are worked out again)
    let again = openStore(path, allFragments)
    defer:
      again.close()
    check again.count("sector") == 1
    check climbsCommand.run(globals(path), @["--delete", "-f"]) == exitUsage

  test "a selection with no climbs in it is not an error":
    let s = fresh("command-none")
    addRide(s, "default", "flat", 1_000_000, 5.0, @[0.0, 5.0, 10.0])
    s.db.execute(
      "insert into selection(user_id, activity_id) select :userId, id from activity",
      userId = s.userId,
    )
    let path = s.path
    s.close()
    check climbs(path) == exitOk

  test "no climbs found yet is not an error either":
    let s = fresh("command-nothing")
    let path = s.path
    s.close()
    check climbs(path, "--all") == exitOk

  test "it works for the user named before the command":
    let s = fresh("command-user")
    addUser(s.path, "bob")
    addRide(s, "bob", "two", 2_000_000, 4.0, eastbound(4.0))
    let bob = UserId(s.db.scalar(int64, "select id from user where name = 'bob'"))
    s.db.execute(
      "insert into selection(user_id, activity_id) select :userId, id from activity",
      userId = bob,
    )
    let path = s.path
    s.close()
    check climbs(path, user = "bob") == exitOk
    check climbs(path) == exitOk # the default user selected nothing: a note
