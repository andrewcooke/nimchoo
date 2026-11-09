import nimchoo/db/statement
import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/modules
import nimchoo/core/logfile
import nimchoo/user/command as userCommand
import ../support/userdata

let dir = getTempDir() / "nch-test-user"

proc fresh(name: string): string =
  removeDir(dir / name)
  createDir(dir / name)
  dir / name / "x.db"

proc userAs(db, who: string, args: varargs[string]): int =
  ## nch --user WHO user ARGS (which the user command refuses: the user is named after it)
  userCommand.run(Globals(dbPath: db, user: who, fragments: allFragments), @args)

proc user(db: string, args: varargs[string]): int =
  userAs(db, "", @args)

proc edit(db, name: string, args: varargs[string]): int =
  ## nch users --edit NAME ARGS
  user(db, @["--edit", name] & @args)

proc q(db, sqlText: string, T: typedesc): T =
  let s = openStore(db, allFragments)
  defer:
    s.close()
  s.db.scalar(T, sqlText)

proc lines(db: string): seq[string] =
  let s = openStore(db, allFragments)
  defer:
    s.close()
  userLines(s)

suite "nch users":
  test "a new database has the default user, with no FTHR and no activities":
    let db = fresh("fresh")
    check user(db) == exitOk
    check lines(db) ==
      @["user     fthr  activities  default", "default     -           0  yes"]

  test "make a user, with an FTHR, and see them":
    let db = fresh("create")
    check user(db, "--add", "bob", "--fthr", "150") == exitOk
    check user(db, "--add", "carol") == exitOk
    check lines(db) ==
      @[
        "user     fthr  activities  default", "bob       150           0",
        "carol       -           0", "default     -           0  yes",
      ]
    check q(
      db,
      "select fthr from user_profile where user_id = (select id from user where name = 'bob')",
      int,
    ) == 150
    check q(db, "select count(*) from user_profile", int) == 1
      # (carol has no profile row yet)

  test "a user is never made twice, or by accident":
    let db = fresh("twice")
    check user(db, "--add", "bob") == exitOk
    check user(db, "--add", "bob") == exitFailure
    check user(db, "bob", "--fthr", "150") == exitUsage # a name without --add or --edit
    check edit(db, "nobody", "--fthr", "150") == exitFailure # no such user: nothing made
    check q(db, "select count(*) from user", int) == 2

  test "the users are named after the command, not by --user before it":
    let db = fresh("globaluser")
    check userAs(db, "bob", "--add", "carol") == exitUsage
    check userAs(db, "bob", "--edit", "bob", "--fthr", "150") == exitUsage
    check userAs(db, "bob") == exitUsage
    check q(db, "select count(*) from user", int) == 1

  test "set, change and forget the FTHR of a user":
    let db = fresh("fthr")
    check user(db, "--add", "bob") == exitOk
    check edit(db, "bob", "--fthr", "154") == exitOk
    check q(db, "select fthr from user_profile", int) == 154
    check edit(db, "bob", "--fthr", "160") == exitOk
    check q(db, "select fthr from user_profile", int) == 160
    check q(db, "select count(*) from user_profile", int) == 1 # (changed in place)
    check edit(db, "bob", "--clear-fthr") == exitOk
    check q(db, "select count(*) from user_profile where fthr is not null", int) == 0
    check edit(db, "bob", "--clear-fthr") == exitOk # (nothing to forget: fine)
    check edit(db, "default", "--fthr", "154") == exitOk
    check q(
      db,
      "select fthr from user_profile where user_id = (select id from user where name = 'default')",
      int,
    ) == 154

  test "bad values change nothing":
    let db = fresh("bad")
    check edit(db, "default", "--fthr", "79") == exitUsage
    check edit(db, "default", "--fthr", "x") == exitUsage
    check q(db, "select count(*) from user_profile", int) == 0

  test "rename":
    let db = fresh("rename")
    check user(db, "--add", "bob", "--fthr", "150") == exitOk
    check edit(db, "bob", "--rename", "robert") == exitOk
    check q(db, "select count(*) from user where name = 'bob'", int) == 0
    check q(
      db,
      "select fthr from user_profile where user_id = (select id from user where name = 'robert')",
      int,
    ) == 150
    check edit(db, "robert", "--fthr", "155") == exitOk # and it is found by the new name
    check edit(db, "bob", "--rename", "x") == exitFailure # the old name is gone

  test "rename: not to a name that is taken":
    let db = fresh("renamebad")
    check user(db, "--add", "bob") == exitOk
    check edit(db, "bob", "--rename", "default") == exitFailure
    check edit(db, "bob", "--rename", "bob") == exitFailure # (to itself: taken)
    check q(db, "select count(*) from user where name = 'default'", int) == 1
    check q(db, "select count(*) from user", int) == 2

  test "the first user is the default; the default can be renamed and stays the default":
    let db = fresh("defaultrename")
    check q(db, "select name from user where is_default = 1", string) == "default"
    check edit(db, "default", "--rename", "me") == exitOk
    check q(db, "select name from user where is_default = 1", string) == "me"
    check q(db, "select count(*) from user", int) == 1 # (no new empty 'default' appears)
    check edit(db, "me", "--fthr", "150") == exitOk
    check q(
      db,
      "select fthr from user_profile where user_id = (select id from user where name = 'me')",
      int,
    ) == 150

  test "--default moves the default to another user, and only one is ever the default":
    let db = fresh("setdefault")
    check user(db, "--add", "bob") == exitOk
    check q(db, "select name from user where is_default = 1", string) == "default"
    check edit(db, "bob", "--default") == exitOk
    check q(db, "select name from user where is_default = 1", string) == "bob"
    check q(db, "select count(*) from user where is_default = 1", int) == 1
    check lines(db)[^1] == "default     -           0" # (the flag column is blank)
    check user(db, "--add", "carol", "--default") == exitOk
      # made and made the default in one go
    check q(db, "select name from user where is_default = 1", string) == "carol"
    check edit(db, "nobody", "--default") == exitFailure

  test "when the default user is destroyed, another becomes the default":
    let db = fresh("defaultgone")
    check user(db, "--add", "bob") == exitOk
    let s = openStore(db, allFragments)
    s.db.execute("delete from user where name = 'default'")
    s.close()
    check q(db, "select name from user where is_default = 1", string) == "bob"

  test "several changes in one go":
    let db = fresh("several")
    check user(db, "--add", "bob") == exitOk
    check edit(db, "bob", "--fthr", "152", "--rename", "robert") == exitOk
    check q(
      db,
      "select fthr from user_profile where user_id = (select id from user where name = 'robert')",
      int,
    ) == 152

  test "the activities of each user are counted":
    let db = fresh("counts")
    check user(db, "--add", "bob") == exitOk
    let s = openStore(db, allFragments)
    for i in 1 .. 1200:
      s.db.execute(
        "insert into file(user_id, name, sha256, imported_at) values ((select id from user where name = 'bob'), :name, :sha256, 0)",
        name = $i,
        sha256 = $i,
      )
      s.db.execute(
        "insert into activity(file_id, session, start_t, end_t) values (:fileId, 0, 0, 1)",
        fileId = i,
      )
    s.close()
    check lines(db) ==
      @[
        "user     fthr  activities  default", "bob         -       1,200",
        "default     -           0  yes",
      ]

  test "the profile goes with the user":
    let db = fresh("cascade")
    check user(db, "--add", "bob", "--fthr", "150") == exitOk
    let s = openStore(db, allFragments)
    s.db.execute("delete from user where name = 'bob'")
    s.close()
    check q(db, "select count(*) from user_profile", int) == 0

  test "changes are logged (and not the listing)":
    let db = fresh("log")
    let path = dir / "log" / "nch.log"
    let g = Globals(dbPath: db, fragments: allFragments, log: openLog(path))
    check userCommand.run(g, @["--add", "bob", "--fthr", "150"]) == exitOk
    check userCommand.run(g, @[]) == exitOk
    check userCommand.run(g, @["--edit", "default", "--fthr", "151"]) == exitOk
    g.log.close()
    let text = readFile(path)
    check text.contains("users     saved      made the user bob, with an FTHR of 150")
    check text.contains("users     saved      default: FTHR is 151")
    check text.count("saved") == 2

  test "other commands see a made user":
    let db = fresh("others")
    check user(db, "--add", "bob") == exitOk
    let s = openStore(db, allFragments, "bob")
    defer:
      s.close()
    check s.userName == "bob"

suite "nch users --delete":
  test "without -f nothing is deleted; with -f the user and everything of theirs go":
    let db = fresh("remove")
    check user(db, "--add", "bob") == exitOk
    let bob = openStore(db, allFragments, "bob")
    fill(bob, "bobs")
    bob.close()
    check user(db, "--delete", "bob") == exitFailure
    check q(db, "select count(*) from user where name = 'bob'", int) == 1
    check user(db, "--delete", "bob", "-f") == exitOk
    check q(db, "select count(*) from user where name = 'bob'", int) == 0
    check q(db, "select count(*) from file", int) == 0
    check q(db, "select count(*) from activity", int) == 0
    check q(db, "select count(*) from user where name = 'default'", int) == 1
      # (the others stay)

  test "removing the default user makes another the default":
    let db = fresh("removedefault")
    check user(db, "--add", "bob") == exitOk
    check user(db, "--delete", "default", "-f") == exitOk
    check q(db, "select name from user where is_default = 1", string) == "bob"

  test "an unknown user is an error, and nothing is deleted":
    let db = fresh("removeunknown")
    check user(db) == exitOk
    check user(db, "--delete", "nobody", "-f") == exitFailure
    check q(db, "select count(*) from user", int) == 1
