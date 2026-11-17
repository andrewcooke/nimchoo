## The counters of tables are gone (db/versions.nim: `003-drop-versions.sql` and its seed).

import std/[os, unittest]
import nimchoo/packages/db/[statement, versions]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

let dir = getTempDir() / "nch-test-versions"

proc open(name: string): Session =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  openSession(path, allFragments, access = allAccess)

proc count(s: Session, kind, pattern: string): int =
  s.db.scalar(
    int,
    "select count(*) from sqlite_master where type = :kind and name like :pattern",
    kind = kind,
    pattern = pattern,
  )

suite "versions: the counters are dropped":
  test "a new database has neither the counters nor the identity, nor any of their triggers":
    let s = open("new")
    defer:
      s.close()
    check s.count("table", "table_version") == 0
    check s.count("table", "database_identity") == 0
    check s.count("trigger", "tv_%") == 0
  test "the seed drops the triggers a database made while they existed, and nothing else":
    let s = open("old")
    defer:
      s.close()
    s.db.execScriptAs(
      "create trigger tv_file_i after insert on file begin select 1; end;", ""
    )
    s.db.execScriptAs(
      "create trigger other_file_i after insert on file begin select 1; end;", ""
    )
    dropCounters(s.db)
    check s.count("trigger", "tv_%") == 0
    check s.count("trigger", "other_file_i") == 1
