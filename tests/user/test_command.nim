import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/modules
import nimchoo/ui/logfile
import nimchoo/user/command as userCommand

let dir = getTempDir() / "nch-test-user"

proc fresh(name: string): string =
  removeDir(dir / name)
  createDir(dir / name)
  dir / name / "x.db"

proc userAs(db, who: string, args: varargs[string]): int =
  ## nch --user WHO user ARGS
  userCommand.run(Globals(dbPath: db, user: who, fragments: allFragments), @args)

proc user(db: string, args: varargs[string]): int =
  userAs(db, "", @args)

proc q(db, sqlText: string): string =
  let s = openStore(db, allFragments)
  defer: s.close()
  s.db.getValue(sql(sqlText))

proc lines(db: string): seq[string] =
  let s = openStore(db, allFragments)
  defer: s.close()
  userLines(s)

suite "nch user":
  test "a new database has the default user, with no FTHR and no activities":
    let db = fresh("fresh")
    check user(db) == exitOk
    check lines(db) == @["user     fthr  activities  default", "default     -           0  yes"]

  test "make a user, with an FTHR, and see them":
    let db = fresh("create")
    check user(db, "--add", "bob", "--fthr", "150") == exitOk
    check user(db, "--add", "carol") == exitOk
    check lines(db) == @["user     fthr  activities  default", "bob       150           0",
                         "carol       -           0", "default     -           0  yes"]
    check q(db, "select fthr from user_profile where user_id = (select id from user where name = 'bob')") == "150"
    check q(db, "select count(*) from user_profile") == "1"           # (carol has no profile row yet)

  test "a user is never made twice, or by accident":
    let db = fresh("twice")
    check user(db, "--add", "bob") == exitOk
    check user(db, "--add", "bob") == exitFailure
    check user(db, "bob", "--fthr", "150") == exitUsage                 # a name without --add
    check userAs(db, "nobody", "--fthr", "150") == exitFailure     # no such user: nothing made
    check q(db, "select count(*) from user") == "2"

  test "set, change and forget the FTHR of the current user":
    let db = fresh("fthr")
    check user(db, "--add", "bob") == exitOk
    check userAs(db, "bob", "--fthr", "154") == exitOk
    check q(db, "select fthr from user_profile") == "154"
    check userAs(db, "bob", "--fthr", "160") == exitOk
    check q(db, "select fthr from user_profile") == "160"
    check q(db, "select count(*) from user_profile") == "1"            # (changed in place)
    check userAs(db, "bob", "--clear-fthr") == exitOk
    check q(db, "select count(*) from user_profile where fthr is not null") == "0"
    check userAs(db, "bob", "--clear-fthr") == exitOk              # (nothing to forget: fine)
    check user(db, "--fthr", "154") == exitOk                           # the default user
    check q(db, "select fthr from user_profile where user_id = (select id from user where name = 'default')") == "154"

  test "bad values change nothing":
    let db = fresh("bad")
    check user(db, "--fthr", "79") == exitUsage
    check user(db, "--fthr", "x") == exitUsage
    check q(db, "select count(*) from user_profile") == "0"

  test "rename":
    let db = fresh("rename")
    check user(db, "--add", "bob", "--fthr", "150") == exitOk
    check userAs(db, "bob", "--rename", "robert") == exitOk
    check q(db, "select count(*) from user where name = 'bob'") == "0"
    check q(db, "select fthr from user_profile where user_id = (select id from user where name = 'robert')") == "150"
    check userAs(db, "robert", "--fthr", "155") == exitOk          # and it is found by the new name
    check userAs(db, "bob", "--rename", "x") == exitFailure         # the old name is gone

  test "rename: not to a name that is taken":
    let db = fresh("renamebad")
    check user(db, "--add", "bob") == exitOk
    check userAs(db, "bob", "--rename", "default") == exitFailure
    check userAs(db, "bob", "--rename", "bob") == exitFailure        # (to itself: taken)
    check q(db, "select count(*) from user where name = 'default'") == "1"
    check q(db, "select count(*) from user") == "2"

  test "the first user is the default; the default can be renamed and stays the default":
    let db = fresh("defaultrename")
    check q(db, "select name from user where is_default = 1") == "default"
    check user(db, "--rename", "me") == exitOk
    check q(db, "select name from user where is_default = 1") == "me"
    check q(db, "select count(*) from user") == "1"             # (no new empty 'default' appears)
    check user(db, "--fthr", "150") == exitOk                    # with no --user: it is the one used
    check q(db, "select fthr from user_profile where user_id = (select id from user where name = 'me')") == "150"

  test "--default moves the default to another user, and only one is ever the default":
    let db = fresh("setdefault")
    check user(db, "--add", "bob") == exitOk
    check q(db, "select name from user where is_default = 1") == "default"
    check userAs(db, "bob", "--default") == exitOk
    check q(db, "select name from user where is_default = 1") == "bob"
    check q(db, "select count(*) from user where is_default = 1") == "1"
    check user(db, "--fthr", "160") == exitOk                    # now acts on bob
    check q(db, "select fthr from user_profile where user_id = (select id from user where name = 'bob')") == "160"
    check lines(db)[^1] == "default     -           0"             # (the flag column is blank)
    check user(db, "--add", "carol", "--default") == exitOk       # made and made the default in one go
    check q(db, "select name from user where is_default = 1") == "carol"
    check userAs(db, "nobody", "--default") == exitFailure

  test "when the default user is destroyed, another becomes the default":
    let db = fresh("defaultgone")
    check user(db, "--add", "bob") == exitOk
    let s = openStore(db, allFragments)
    s.db.exec(sql"delete from user where name = 'default'")
    s.close()
    check q(db, "select name from user where is_default = 1") == "bob"

  test "several changes in one go":
    let db = fresh("several")
    check user(db, "--add", "bob") == exitOk
    check userAs(db, "bob", "--fthr", "152", "--rename", "robert") == exitOk
    check q(db, "select fthr from user_profile where user_id = (select id from user where name = 'robert')") == "152"

  test "the activities of each user are counted":
    let db = fresh("counts")
    check user(db, "--add", "bob") == exitOk
    let s = openStore(db, allFragments)
    for i in 1 .. 1200:
      s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values ((select id from user where name = 'bob'), ?, ?, 0)",
                $i, $i)
      s.db.exec(sql"insert into activity(file_id, session, start_t, end_t) values (?, 0, 0, 1)", i)
    s.close()
    check lines(db) == @["user     fthr  activities  default", "bob         -       1,200", "default     -           0  yes"]

  test "the profile goes with the user":
    let db = fresh("cascade")
    check user(db, "--add", "bob", "--fthr", "150") == exitOk
    let s = openStore(db, allFragments)
    s.db.exec(sql"delete from user where name = 'bob'")
    s.close()
    check q(db, "select count(*) from user_profile") == "0"

  test "changes are logged (and not the listing)":
    let db = fresh("log")
    let path = dir / "log" / "nch.log"
    let g = Globals(dbPath: db, fragments: allFragments, log: openLog(path))
    check userCommand.run(g, @["--add", "bob", "--fthr", "150"]) == exitOk
    check userCommand.run(g, @[]) == exitOk
    check userCommand.run(g, @["--fthr", "151"]) == exitOk
    g.log.close()
    let text = readFile(path)
    check text.contains("user      saved      made the user bob, with an FTHR of 150")
    check text.contains("user      saved      default: FTHR is 151")
    check text.count("saved") == 2

  test "other commands see a made user":
    let db = fresh("others")
    check user(db, "--add", "bob") == exitOk
    let s = openStore(db, allFragments, "bob")
    defer: s.close()
    check s.userName == "bob"
