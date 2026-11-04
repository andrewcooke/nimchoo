import std/[algorithm, os, sequtils, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/importer/batch
import nimchoo/importer/command as importCommand
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/modules
import ../support/fitbuilder

const ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"
const base = 900_000_000

let dir = getTempDir() / "nch-test-import-cmd"

proc bytesToFile(path: string, data: seq[byte]) =
  createDir(parentDir(path))
  var s = newString(data.len)
  for i, x in data: s[i] = char(x)
  writeFile(path, s)

proc tiny(startAt: int): seq[byte] =
  ## A different small activity for each `startAt` (so a different file hash).
  fitFile(
    defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)]) &
    b(0) & le32(startAt) & le32(536870912) & le32(-1073741824) &
    defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T)]) &
    b(1) & le32(startAt) & le32(startAt))

proc fresh(name: string): string =
  ## An empty directory to work in.
  result = dir / name
  removeDir(result)
  createDir(result)

proc open(path: string): Store = openStore(path, allFragments)

func globals(db: string, user = ""): Globals =
  Globals(dbPath: db, user: user, fragments: allFragments)

suite "nch import: finding files":
  test "directories are searched recursively, for .fit and .FIT only":
    let d = fresh("tree")
    bytesToFile(d / "b.fit", tiny(base + 1))
    bytesToFile(d / "sub" / "a.FIT", tiny(base + 2))
    bytesToFile(d / "sub" / "deeper" / "c.Fit", tiny(base + 3))
    writeFile(d / "notes.txt", "not a fit file")
    writeFile(d / "sub" / "README", "nor this")
    let st = open(d / "x.db")
    defer: st.close()
    let r = importReport(st, @[d])
    check r.imported == 3
    check r.failed == 0
    # sorted, one line per file, then the summary
    let imported = r.lines.filterIt(it.startsWith("imported"))
    check imported.len == 3
    let names = imported.mapIt(it.split("  ")[1])
    check names == names.sorted
    check r.lines[^1] == "done: 3 files, 3 imported, 0 failed"

  test "a file given twice, or by its directory too, is imported once":
    let d = fresh("dups")
    bytesToFile(d / "a.fit", tiny(base + 1))
    let st = open(d / "x.db")
    defer: st.close()
    let r = importReport(st, @[d / "a.fit", d, d / "a.fit"])
    check r.imported == 1
    check r.duplicates + r.unchanged == 0
    check r.lines[^1] == "done: 1 file, 1 imported, 0 failed"

  test "an explicit file is tried whatever it is called":
    let d = fresh("ext")
    bytesToFile(d / "ride.bin", tiny(base + 1))
    let st = open(d / "x.db")
    defer: st.close()
    check importReport(st, @[d / "ride.bin"]).imported == 1

  test "a path that is not there, and a directory with no FIT files":
    let d = fresh("missing")
    createDir(d / "empty")
    writeFile(d / "empty" / "x.txt", "text")
    let st = open(d / "x.db")
    defer: st.close()
    let r = importReport(st, @[d / "nonesuch", d / "empty"])
    check r.failed == 2
    check r.lines[0].contains("no such file or directory")
    check r.lines[1].contains("no .fit files found")
    check r.lines[^1] == "done: 2 files, 0 imported, 2 failed (not found 2)"

suite "nch import: a mixed run":
  test "a bad file does not stop the others, or undo them":
    let d = fresh("mixed")
    bytesToFile(d / "1-good.fit", tiny(base + 1))
    writeFile(d / "2-bad.fit", "this is not a fit file at all")
    bytesToFile(d / "3-good.fit", tiny(base + 2))
    let st = open(d / "x.db")
    defer: st.close()
    let r = importReport(st, @[d])
    check r.imported == 2
    check r.failed == 1
    check r.lines.anyIt(it.startsWith("failed    ") and it.contains("2-bad.fit"))
    check st.db.getValue(sql"select count(*) from activity") == "2"

  test "importing again skips what is already there":
    let d = fresh("again")
    bytesToFile(d / "a.fit", tiny(base + 1))
    let st = open(d / "x.db")
    defer: st.close()
    discard importReport(st, @[d])
    let r = importReport(st, @[d])
    check r.imported == 0
    check r.unchanged == 1
    check r.lines[0].contains("unchanged")
    # looking at every file finds it is a file already imported
    let slow = importReport(st, @[d], ImportOptions(slow: true))
    check slow.duplicates == 1
    check slow.lines[0].contains("duplicate")

  test "quiet shows only failures and the summary":
    let d = fresh("quiet")
    bytesToFile(d / "a.fit", tiny(base + 1))
    writeFile(d / "b.fit", "junk")
    let st = open(d / "x.db")
    defer: st.close()
    let r = importReport(st, @[d], ImportOptions(quiet: true))
    check r.lines.len == 2
    check r.lines[0].startsWith("failed")
    check r.lines[1] == "done: 2 files, 1 imported, 1 failed (bad format 1)"

  test "repeated advisories in a file are grouped":
    let d = fresh("warn")
    # three records in the same second: two duplicate warnings
    let body = fitFile(
      defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)]) &
      b(0) & le32(base) & le32(1) & le32(1) & b(0) & le32(base) & le32(2) & le32(2) &
      b(0) & le32(base) & le32(3) & le32(3) &
      defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T)]) &
      b(1) & le32(base) & le32(base))
    bytesToFile(d / "dup.fit", body)
    let st = open(d / "x.db")
    defer: st.close()
    let r = importReport(st, @[d])
    check r.imported == 1
    check r.stderr.len == 1
    check r.stderr[0].contains("dup.fit")
    check r.stderr[0].contains("and 1 more like it")

suite "nch import: the command":
  test "exit codes":
    let d = fresh("run")
    bytesToFile(d / "a.fit", tiny(base + 1))
    let g = globals(d / "x.db")
    check importCommand.run(g, @["--help"]) == exitOk
    check importCommand.run(g, @[]) == exitUsage
    check importCommand.run(g, @["--nonesuch", d]) == exitUsage
    check importCommand.run(g, @["-q", d]) == exitOk
    check importCommand.run(g, @["-q", d]) == exitOk              # skipped is not a failure
    check importCommand.run(g, @["-q", d / "nonesuch"]) == exitFailure
    writeFile(d / "bad.fit", "junk")
    check importCommand.run(g, @["-q", d]) == exitFailure

  test "an unknown user is a failure":
    let d = fresh("user")
    bytesToFile(d / "a.fit", tiny(base + 1))
    check importCommand.run(globals(d / "x.db", "nobody"), @["-q", d]) ==
      exitFailure

  test "the real ride goes in":
    let d = fresh("ride")
    let st = open(d / "x.db")
    let r = importReport(st, @[ride])
    check r.lines[0].endsWith("(1 activity, 20 segments, 2099 coordinates)")
    st.close()
