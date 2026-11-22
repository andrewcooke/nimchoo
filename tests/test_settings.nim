## `nch --config` (`settings.nim`).

import std/[options, os, strutils, unittest]
import nimchoo/core/globals
import nimchoo/settings
from nimchoo/registry import allAccess, allFragments, schema
import nimchoo/packages/db/[statement, store]
import nimchoo/packages/user/session
import ./support/styles

suite "nch --config: the settings":
  let dir = getTempDir() / "nch-test-introspect"

  test "the settings in force, with where each came from":
    let g = Globals(
      dbPath: some(dir / "x.db"), user: some("bob"), offline: true, access: allAccess
    )
    let text =
      configLines(g, 120, @["activities", "packages", "thirdcommand"]).plainText
    check "version" in text and "(--db; not made yet)" in text
    check "bob (there is no database yet)" in text and "yes (`--offline`)" in text
    check "access" in text and "enforced" in text
    check "NCH_DB" in text and "thirdcommand" in text # (the commands are the ones given)
    check "there is no database yet" in text
    check "NO_COLOR" in text and "not set (default)" in text
      # (the environment, with its defaults)

  test "the database's path and where it came from are decided in one place":
    check dbPathAndSource(some("x.db")) == (path: "x.db", source: dsOption)
    check dbPathAndSource(none(string)).source in {dsEnvironment, dsDefault}
    check dbPathAndSource(none(string)).path == resolveDbPath(none(string))
    if dbPathAndSource(none(string)).source == dsDefault:
      check dbPathAndSource(none(string)).path == defaultDbPath()
  test "the fragments of the database are compared with the program's":
    removeDir dir
    createDir dir
    let path = dir / "y.db"
    openSession(path, allFragments, access = allAccess).close()
    check fragmentLines(path) ==
      @[
        "the program has " & $schema.len &
          " fragments (the SQL that makes its tables), and the database has had all of them, as this version has them"
      ]
    # a fragment the database has and this program does not
    let s = openStore(path, allFragments, access = allAccess)
    s.db.execScript(
      "insert into fragment(name, applied_at, sha256) values ('zzz/001.sql', 0, 'x')"
    )
    s.db.execScript(
      "update fragment set sha256 = 'other' where name = 'user/001-schema.sql'"
    )
    s.close()
    let lines = fragmentLines(path).join("\n")
    check "zzz/001.sql: only in the database" in lines
    check "user/001-schema.sql: not the SQL this version has" in lines
    check lines.startsWith("the program has " & $schema.len & " fragments")
    removeDir dir
