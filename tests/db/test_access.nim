## The access rules at work in the database layer (packages/db/access.nim): a statement is refused while it is
## prepared, naming the package and the table; and the package of a statement is the one its file is in.

import std/[os, strutils, unittest]
import std/[algorithm, sequtils, tables]
import nimchoo/core/[access, errors, ownership]
import nimchoo/packages/db/[access, statement, store]
from nimchoo/registry import allFragments, allAccess, newAllAccess

let dir = getTempDir() / "nch-test-access"

proc open(name: string): Store =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  openStore(path, allFragments, access = newAllAccess(amEnforce))

proc refusal(s: Store, package, sql: string): string =
  ## What preparing `sql` as `package` says, "" if it is allowed.
  try:
    discard prepareStmtAs(s.db, sql, package)
  except StoreError as e:
    return e.msg

suite "access: statements":
  test "a package may read the tables it depends on and write its own":
    let s = open("own")
    check s.refusal("climbs", "select count(*) from activity") == ""
    check s.refusal("climbs", "delete from effort") == ""
    s.close()

  test "a package may not write the table of another, and the message says who, what and where":
    let s = open("write")
    let why = s.refusal("climbs", "delete from activity")
    check "'climbs'" in why and "'activity'" in why and "'importer'" in why
    check "delete from activity" in why
    check s.refusal(
      "climbs", "insert into selection(user_id, activity_id) values (1, 1)"
    ) != ""
    s.close()

  test "a package may not read the table of one it does not depend on":
    let s = open("read")
    check s.refusal("heartrate", "select count(*) from effort") != ""
    check s.refusal("heartrate", "select count(*) from user") == ""
    s.close()

  test "code outside the packages is not checked":
    let s = open("outside")
    check s.refusal("", "delete from activity") == ""
    s.close()

  test "the package of a source file is the nearest directory above it with a package.nim":
    const
      inPackage = packageOfFile(
        currentSourcePath().parentDir.parentDir.parentDir / "src" / "nimchoo" /
          "packages" / "commands" / "activitiescmd" / "command.nim"
      )
      inCore = packageOfFile(
        currentSourcePath().parentDir.parentDir.parentDir / "src" / "nimchoo" / "core" /
          "x.nim"
      )
      inTests = packageOfFile(currentSourcePath())
    check inPackage == "activitiescmd"
    check inCore == ""
    check inTests == ""

suite "access: the foreign keys that carry a cascade":
  test "the scan of the fragments finds the foreign keys SQLite has":
    let s = open("fk")
    let scanned = parentTables(baseFragments & allFragments)
    let ours = tableOwners(baseFragments & allFragments)
    for table in s.db.query(
      string, "select name from sqlite_master where type = 'table'"
    ):
      if table.toLowerAscii notin ours: # (SpatiaLite's own tables)
        continue
      let real = s.db
        .query(string, "select \"table\" from pragma_foreign_key_list(:t)", t = table)
        .mapIt(it.toLowerAscii).sorted
      check scanned.getOrDefault(table.toLowerAscii).sorted == real.deduplicate(true)
    s.close()

  test "deleting an activity as the importer is allowed, though it cascades into the tables of other packages":
    let s = open("cascade")
    check s.refusal("importer", "delete from activity") == ""
    check s.refusal("importer", "delete from user") != ""
    s.close()

suite "access: fragments":
  test "a package may change the definition of its own tables and may not change another's":
    let s = open("define")
    var why = ""
    try:
      execScriptAs(s.db, "alter table activity add column zz text", "climbs")
    except StoreError as e:
      why = e.msg
    check "'climbs'" in why and "'activity'" in why
    execScriptAs(s.db, "alter table effort add column zz text", "climbs")
    s.close()

  test "a package may put a trigger on a table of one it depends on, and not on one it does not":
    let s = open("trigger")
    execScriptAs(
      s.db,
      "create temp trigger t1 after update of fthr on user_profile begin select 1; end",
      "model",
    )
    var why = ""
    try:
      execScriptAs(
        s.db,
        "create trigger t2 after update of fthr on user_profile begin select 1; end",
        "heartrate",
      )
    except StoreError as e:
      why = e.msg
    check "'heartrate'" in why
    s.close()
