## `nch activities --import` remembers the paths it has seen: a path whose size and
## modification time are unchanged is skipped without being read.

import nimchoo/packages/db/statement
import std/[os, strutils, times, unittest]
import ../support/shims
import nimchoo/packages/importer/batch
import nimchoo/packages/commands/activitiescmd/command as activitiesCommand
import nimchoo/core/globals
import nimchoo/packages/db/store
import nimchoo/core/errors
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/fit/default
import nimchoo/packages/fit/model
import ../support/fitbuilder

proc importCmd(g: Globals, args: seq[string]): int =
  ## `nch activities --import ARGS` (the paths first, then the options)
  var paths, flags: seq[string]
  var i = 0
  while i < args.len:
    if args[i] in ["-q", "--quiet", "--slow"]:
      flags.add args[i]
    elif args[i] in ["-j", "--jobs"]:
      flags.add args[i]
      flags.add args[i + 1]
      inc i
    elif args[i].startsWith("-"):
      flags.add args[i]
    else:
      paths.add args[i]
    inc i
  activitiesCommand.run(g, @["--import"] & paths & flags)

const base = 900_000_000

let dir = getTempDir() / "nch-test-import-fast"

proc realProfile(): Profile {.raises: [].} =
  try:
    loadDefaultProfile()
  except NchError as e:
    raiseAssert e.msg

proc bytesToFile(path: string, data: seq[byte]) =
  createDir(parentDir(path))
  var s = newString(data.len)
  for i, x in data:
    s[i] = char(x)
  writeFile(path, s)

proc tiny(startAt: int): seq[byte] =
  fitFile(
    defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)]) & b(0) &
      le32(startAt) & le32(536870912) & le32(-1073741824) &
      defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T)]) & b(1) & le32(startAt) &
      le32(startAt)
  )

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

proc open(path: string): Store =
  openStore(path, allFragments, access = allAccess)

proc count(s: Store, table: string): int =
  s.db.scalar(int, "select count(*) from " & table)

type Counted = ref object
  loads: int

proc counting(c: Counted): ImportOptions =
  ## Options whose profile source counts how often it is asked.
  ImportOptions(
    profile: proc(): Profile {.closure, raises: [].} =
      inc c.loads
      realProfile()
  )

suite "import: skipping what has not changed":
  test "the second run skips by path, without reading":
    let d = fresh("skip")
    let path = d / "a.fit"
    bytesToFile(path, tiny(base + 1))
    let st = open(d / "x.db")
    defer:
      st.close()
    check importReport(st, @[d]).imported == 1
    # new content of the same size and the same modification time: not read
    let mtime = getLastModificationTime(path)
    var changed = tiny(base + 1)
    changed[33] = changed[33] xor 0xff # a coordinate byte
    bytesToFile(path, changed)
    setLastModificationTime(path, mtime)
    let r = importReport(st, @[d])
    check r.unchanged == 1
    check r.imported == 0
    check r.lines[0].contains("unchanged")
    # --slow does read it, and finds a different file
    check importReport(st, @[d], ImportOptions(slow: true)).imported == 1

  test "a changed modification time means the file is looked at again":
    let d = fresh("mtime")
    let path = d / "a.fit"
    bytesToFile(path, tiny(base + 1))
    let st = open(d / "x.db")
    defer:
      st.close()
    discard importReport(st, @[d])
    setLastModificationTime(
      path, getLastModificationTime(path) + initDuration(seconds = 5)
    )
    let r = importReport(st, @[d])
    check r.duplicates == 1
    check r.lines[0].contains("duplicate") # same content: found by its hash
    check importReport(st, @[d]).lines[0].contains("unchanged") # and now remembered

  test "a changed size means the file is looked at again":
    let d = fresh("size")
    let path = d / "a.fit"
    bytesToFile(path, tiny(base + 1))
    let st = open(d / "x.db")
    defer:
      st.close()
    discard importReport(st, @[d])
    bytesToFile(path, tiny(base + 2) & b(0))
    let r = importReport(st, @[d])
    check r.imported + r.failed == 1 # not skipped as unchanged

  test "a moved or copied file is found by its hash, then remembered":
    let d = fresh("moved")
    bytesToFile(d / "one" / "a.fit", tiny(base + 1))
    let st = open(d / "x.db")
    defer:
      st.close()
    discard importReport(st, @[d / "one"])
    createDir(d / "two")
    copyFile(d / "one" / "a.fit", d / "two" / "b.fit") # same content, new path
    let r = importReport(st, @[d / "two"])
    check r.duplicates == 1
    check r.lines[0].contains("same content as " & (d / "one" / "a.fit"))
    check st.count("activity") == 1
    check importReport(st, @[d / "two"]).lines[0].contains("unchanged")

  test "a database with no record of the paths fills it in on the first run":
    let d = fresh("empty")
    bytesToFile(d / "a.fit", tiny(base + 1))
    let st = open(d / "x.db")
    defer:
      st.close()
    discard importReport(st, @[d])
    st.db.execute("delete from seen_file")
    check importReport(st, @[d]).lines[0].contains("duplicate")
    check st.count("seen_file") == 1
    check importReport(st, @[d]).lines[0].contains("unchanged")

  test "rows are written in batches, for many files":
    let d = fresh("many")
    for i in 1 .. 450:
      bytesToFile(d / ("r" & $i & ".fit"), tiny(base + i))
    let st = open(d / "x.db")
    defer:
      st.close()
    check importReport(st, @[d], ImportOptions(quiet: true)).imported == 450
    check st.count("seen_file") == 450
    let r = importReport(st, @[d], ImportOptions(quiet: true))
    check r.unchanged == 450
    check r.imported == 0

  test "files that are gone leave their rows alone":
    let d = fresh("gone")
    bytesToFile(d / "a.fit", tiny(base + 1))
    bytesToFile(d / "b.fit", tiny(base + 2))
    let st = open(d / "x.db")
    defer:
      st.close()
    discard importReport(st, @[d])
    removeFile(d / "a.fit")
    let r = importReport(st, @[d])
    check r.unchanged == 1
    check st.count("seen_file") == 2

suite "import: remembered failures":
  test "a file that failed is not tried again, and is reported as known":
    let d = fresh("known")
    writeFile(d / "bad.fit", "this is not a fit file at all")
    let st = open(d / "x.db")
    defer:
      st.close()
    let first = importReport(st, @[d])
    check first.failed == 1
    check first.known == 0
    let second = importReport(st, @[d])
    check second.failed == 0
    check second.known == 1
    check second.lines[0].startsWith("known")
    check second.lines[^1].contains("1 known failure (use --slow to retry)")
    check st.db.scalar(string, "select failure from seen_file") == "bad_format"

  test "the kinds of failure are remembered":
    let d = fresh("kinds")
    let noSession = fitFile(defn(0, 20, @[(253, 4, uint32T)]) & b(0) & le32(base))
    bytesToFile(d / "nosession.fit", noSession)
    let st = open(d / "x.db")
    defer:
      st.close()
    discard importReport(st, @[d])
    check st.db.scalar(string, "select failure from seen_file") == "no_activity"

  test "a known failure is retried when the file changes":
    let d = fresh("fixed")
    let path = d / "a.fit"
    writeFile(path, "broken")
    let st = open(d / "x.db")
    defer:
      st.close()
    discard importReport(st, @[d])
    bytesToFile(path, tiny(base + 1)) # repaired, saved over it
    let r = importReport(st, @[d])
    check r.imported == 1
    check r.known == 0
    check st.db.scalar(int, "select failure is null from seen_file") == 1

  test "--slow retries the known failures":
    let d = fresh("retry")
    writeFile(d / "bad.fit", "broken")
    let st = open(d / "x.db")
    defer:
      st.close()
    discard importReport(st, @[d])
    let r = importReport(st, @[d], ImportOptions(slow: true))
    check r.failed == 1
    check r.known == 0

  test "known failures do not make later runs fail":
    let d = fresh("status")
    writeFile(d / "bad.fit", "broken")
    let g = Globals(
      dbPath: d / "x.db", fragments: allFragments, access: allAccess, offline: true
    )
    check importCmd(g, @["-q", d]) == exitFailure # new failure
    check importCmd(g, @["-q", d]) == exitOk # known now
    check importCmd(g, @["-q", "--slow", d]) == exitFailure

suite "import: the profile is loaded only when needed":
  test "not for files that are skipped, nor for copies of imported content":
    let d = fresh("lazy")
    bytesToFile(d / "one" / "a.fit", tiny(base + 1))
    let st = open(d / "x.db")
    defer:
      st.close()
    let c = Counted()
    discard importReport(st, @[d / "one"], c.counting)
    check c.loads == 1
    discard importReport(st, @[d / "one"], c.counting) # skipped by path
    check c.loads == 1
    createDir(d / "two")
    copyFile(d / "one" / "a.fit", d / "two" / "b.fit")
    discard importReport(st, @[d / "two"], c.counting) # known by hash
    check c.loads == 1
    discard importReport(st, @[d / "one"], c.counting)
    check c.loads == 1
