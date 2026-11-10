## `nch packages` (src/nimchoo/introspect.nim): its command line, and the facts about the running program.

import std/[os, sequtils, strutils, unittest]
import nimchoo/core/[globals, registry]
import nimchoo/introspect
import nimchoo/packages/util/args/args
from nimchoo/registry import allAccess, commands, schema
import nimchoo/packages/db/[statement, store]
import nimchoo/packages/user/session
from nimchoo/registry import allFragments

suite "nch packages: the command line":
  test "no arguments is the list; a name is the detail":
    check parseArgs(@[]).params.view == vList
    let p = parseArgs(@["importer"])
    check p.problem == "" and p.params.view == vDetail and p.params.package == "importer"

  test "the other views":
    check parseArgs(@["--points"]).params.view == vPoints
    check parseArgs(@["--tables"]).params.view == vTables
    check parseArgs(@["--dot"]).params.view == vDot
    check parseArgs(@["--config"]).params.view == vConfig
    check parseArgs(@["--graph"]).params.view == vLayers
    check parseArgs(@["--graph", "db"]).params.view == vTree
    check parseArgs(@["db", "--graph"]).params.root == "db"
    check parseArgs(@["--graph", "--reverse", "db"]).params.reverse

  test "combinations that mean nothing are refused":
    check parseArgs(@["--points", "--tables"]).problem.contains("choose one")
    check parseArgs(@["importer", "--points"]).problem.contains(
      "goes with nothing but --graph"
    )
    check parseArgs(@["--reverse"]).problem.contains("--reverse goes with")
    check parseArgs(@["--graph", "--reverse"]).problem.contains("--reverse goes with")
    check parseArgs(@["a", "b"]).problem.len > 0
    check parseArgs(@["--nonesuch"]).problem.len > 0

  test "every option has help and is in the usage, at any width":
    for width in [50, 80, 120]:
      let text = usageText(width)
      for line in text.splitLines:
        if not (line.startsWith("usage: ") or line.startsWith("       nch ")):
          check line.len <= width
      for d in packagesSpec().docs:
        for n in d.names:
          check n in text

suite "nch packages: the settings":
  let dir = getTempDir() / "nch-test-introspect"

  test "the settings in force, with where each came from":
    let g = Globals(dbPath: dir / "x.db", user: "bob", offline: true, access: allAccess)
    let text = configLines(g).join("\n")
    check "version" in text and "(--db; not made yet)" in text
    check "bob  (--user)" in text and "yes (--offline)" in text
    check "access" in text and "enforced" in text
    check "NCH_DB" in text and "packages" in text
    check "there is no database file yet" in text

  test "the fragments of the database are compared with the program's":
    removeDir dir
    createDir dir
    let path = dir / "y.db"
    openSession(path, allFragments, access = allAccess).close()
    check fragmentLines(path)[0] ==
      "fragments: the program has " & $schema.len & "; the database has had " &
      $schema.len
    check "  all of them match" in fragmentLines(path)
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
    removeDir dir

  test "nch provides the command itself; no package may take its name":
    check "packages" in builtinCommands
    check "packages" notin commands.mapIt(it.name)
