import std/[os, unittest]
import nimchoo/core/globals
import nimchoo/packages/commands/dbcmd/command as dbCommand
import nimchoo/packages/db/store
import nimchoo/modules
import ../../support/userdata

let dir = getTempDir() / "nch-test-dbcommand"

proc fresh(name: string): string =
  removeDir(dir / name)
  createDir(dir / name)
  dir / name / "x.db"

suite "nch db":
  test "no arguments says where, and changes nothing; no database is not made":
    let d = fresh("show")
    check dbCommand.run(globals(d), @[]) == exitOk
    check not fileExists(d)
    openStore(d, allFragments).close()
    check dbCommand.run(globals(d), @[]) == exitOk
    check fileExists(d)
  test "--delete without -f does nothing":
    let d = fresh("noforce")
    openStore(d, allFragments).close()
    check dbCommand.run(globals(d), @["--delete"]) == exitFailure
    check fileExists(d)
  test "--delete -f removes the file and its journal files":
    let d = fresh("force")
    openStore(d, allFragments).close()
    writeFile(d & "-journal", "")
    check dbCommand.run(globals(d), @["--delete", "-f"]) == exitOk
    check not fileExists(d) and not fileExists(d & "-journal")
  test "no database: nothing to delete, and nothing is made":
    let d = fresh("none")
    check dbCommand.run(globals(d), @["--delete", "-f"]) == exitOk
    check not fileExists(d)
  test "bad arguments":
    let d = fresh("bad")
    check dbCommand.run(globals(d), @["-f"]) == exitUsage
    check dbCommand.run(globals(d), @["--nonesuch"]) == exitUsage
    check dbCommand.run(globals(d), @["x"]) == exitUsage
    check dbCommand.run(globals(d), @["--help"]) == exitOk
