import std/[os, sequtils, strutils, unittest]
import nimchoo/importer/[events, failure, logsink]
import nimchoo/importer/command as importCommand
import nimchoo/cli/common
import nimchoo/modules
import nimchoo/ui/logfile
import nimchoo/warnings
import ../support/fitbuilder

const base = 900_000_000

let dir = getTempDir() / "nch-test-import-log"

proc bytesToFile(path: string, data: seq[byte]) =
  createDir(parentDir(path))
  var s = newString(data.len)
  for i, x in data: s[i] = char(x)
  writeFile(path, s)

proc tiny(startAt: int): seq[byte] =
  fitFile(
    defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)]) &
    b(0) & le32(startAt) & le32(536870912) & le32(-1073741824) &
    defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T)]) &
    b(1) & le32(startAt) & le32(startAt))

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

func done(o: Outcome): ImportEvent =
  ImportEvent(kind: evFileDone, index: 1, path: "p.fit", outcome: o,
              counts: Counts(activities: 1, segments: 2, coords: 3),
              failure: fkNoActivity, message: "why")

suite "import log: entries":
  test "start and finish":
    check logEntries(ImportEvent(kind: evStart, total: 3)) ==
      @[Entry(level: lvInfo, event: leStart, text: "3 files")]
    let fin = logEntries(ImportEvent(kind: evFinish,
      summary: Summary(done: 3, unchanged: 3, notes: @["odd"])))
    check fin.mapIt(it.level) == @[lvWarn, lvInfo]
    check fin.mapIt(it.event) == @[leNote, leDone]
    check fin[0].text == "odd"
    check fin[1].text == "3 files, 0 imported, 3 unchanged, 0 failed"
  test "what changed or went wrong is logged":
    check logEntries(done(oImported)) ==
      @[Entry(level: lvInfo, event: leImported,
            text: "p.fit  1 activity, 2 segments, 3 coordinates")]
    check logEntries(done(oDuplicate)) ==
      @[Entry(level: lvInfo, event: leDuplicate, text: "p.fit  already imported")]
    var same = done(oDuplicate)
    same.sameAs = "q/p.fit"
    check logEntries(same)[0].text == "p.fit  same content as q/p.fit"
    check logEntries(done(oFailed)) ==
      @[Entry(level: lvError, event: leFailed, text: "p.fit  (no activity) why")]
  test "unchanged files and known failures are not":
    check logEntries(done(oUnchanged)).len == 0
    check logEntries(done(oKnownFailure)).len == 0
    check logEntries(ImportEvent(kind: evFileStart, startIndex: 1, startPath: "p")).len == 0
  test "every advisory is logged in full":
    var ev = done(oImported)
    ev.advisories = @[Warning(offset: 5, kind: wkDuplicateTime, msg: "first"),
                    Warning(offset: 9, kind: wkDuplicateTime, msg: "second")]
    let es = logEntries(ev)
    check es.mapIt(it.level) == @[lvInfo, lvWarn, lvWarn]
    check es.mapIt(it.event) == @[leImported, leAdvisory, leAdvisory]
    check es[1].text == "p.fit  offset 5: first"
    check es[2].text == "p.fit  offset 9: second"

suite "import log: the command":
  test "the log gets the run, even with -q":
    let d = fresh("run")
    bytesToFile(d / "src" / "a.fit", tiny(base + 1))
    writeFile(d / "src" / "bad.fit", "junk")
    let path = d / "nch.log"
    let g = Globals(dbPath: d / "x.db", fragments: allFragments, log: openLog(path))
    check importCommand.run(g, @["-q", d / "src"]) == exitFailure
    g.log.close()
    let text = readFile(path)
    check "start      2 files" in text
    check "imported   " in text and "a.fit  1 activity" in text
    check "ERROR import    failed" in text and "bad.fit  (bad format)" in text
    check "done       2 files, 1 imported, 1 failed" in text

  test "a second run logs no file lines, only the totals":
    let d = fresh("again")
    bytesToFile(d / "src" / "a.fit", tiny(base + 1))
    let path = d / "nch.log"
    var g = Globals(dbPath: d / "x.db", fragments: allFragments)
    discard importCommand.run(g, @["-q", d / "src"])
    g.log = openLog(path)
    check importCommand.run(g, @["-q", d / "src"]) == exitOk
    g.log.close()
    let ls = readFile(path).splitLines.filterIt(it.len > 0)
    check ls.len == 2
    check ls[1].endsWith("done       1 file, 0 imported, 1 unchanged, 0 failed")

  test "no log, no file":
    let d = fresh("nolog")
    bytesToFile(d / "src" / "a.fit", tiny(base + 1))
    let g = Globals(dbPath: d / "x.db", fragments: allFragments)
    check importCommand.run(g, @["-q", d / "src"]) == exitOk
    check not fileExists(d / "nch.log")
