import std/[os, sequtils, strutils, unittest]
import nimchoo/activity/[batch, display, events, failure]
import nimchoo/db/store
import nimchoo/modules
import nimchoo/ui/[live, style]
import ./fitbuilder

const base = 900_000_000

let dir = getTempDir() / "nch-test-import-display"

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

func texts(ls: seq[Line]): seq[string] = ls.mapIt(it.text)

suite "import display: the lines":
  test "the counts of a run in progress":
    var s = Summary(total: 3000, imported: 3, skipped: 1196, failed: 5, warnings: 17)
    s.failures[fkNoActivity] = 4
    s.failures[fkBadFormat] = 1
    check renderImport(s, 1204, "ride.fit").texts == @[
      "importing 1,204 / 3,000   ride.fit",
      "imported 3 · skipped 1,196 · failed 5 (no activity 4, bad format 1) · warnings 17"]

  test "no failures and no warnings: nothing alarming":
    let ls = renderImport(Summary(total: 10, imported: 2, skipped: 1), 4, "x.fit")
    check ls[1].text == "imported 2 · skipped 1 · failed 0"
    check ls[1].allIt(it.look.fg notin {cRed, cYellow})

  test "known failures are shown apart from skipped":
    check renderImport(Summary(total: 5, skipped: 1, known: 2), 3, "x").texts[1] ==
      "imported 0 · skipped 1 · known failures 2 · failed 0"

  test "at the end there is no current file":
    check renderImport(Summary(total: 5, done: 5), 5, "").texts[0] == "importing 5 / 5"

  test "the done line points at the log if files failed":
    var s = Summary(done: 3, imported: 2, failed: 1)
    s.failures[fkBadFormat] = 1
    check doneLine(s, "/x/nch.log") ==
      "done: 3 files: 2 imported, 0 skipped, 1 failed (bad format 1); details in /x/nch.log"
    check doneLine(s, "") == "done: 3 files: 2 imported, 0 skipped, 1 failed (bad format 1)"
    check doneLine(Summary(done: 1, imported: 1), "/x") ==
      "done: 1 file: 1 imported, 0 skipped, 0 failed"

  test "colours: imported green, failed red, warnings yellow":
    var s = Summary(total: 5, imported: 1, failed: 1, warnings: 2)
    s.failures[fkBadFormat] = 1
    let second = renderImport(s, 2, "x")[1]
    check second[0].look.fg == cGreen
    check second.anyIt(it.look.fg == cRed and it.text.startsWith("failed"))
    check second.anyIt(it.look.fg == cYellow and it.text.startsWith("warnings"))

suite "import display: a run":
  type Fake = ref object
    now: int64
    live, outs, errs: seq[string]

  proc fakeLive(f: Fake): Live =
    newLive(write = proc(s: string) {.closure, raises: [].} = f.live.add(s),
            now = proc(): int64 {.closure, raises: [].} = f.now,
            size = proc(): tuple[w, h: int] {.closure, raises: [].} = (100, 24),
            colour = false)

  proc run(f: Fake, d: string, advanceBy: int64): Summary =
    let st = openStore(d / "x.db", allFragments)
    defer: st.close()
    let ticker: Sink = proc(ev: ImportEvent) {.closure, raises: [].} =
      f.now += advanceBy
    let shown = liveSink(fakeLive(f), "/x/nch.log",
      proc(s: string) {.closure, raises: [].} = f.outs.add(s),
      proc(s: string) {.closure, raises: [].} = f.errs.add(s))
    importPaths(st, @[d], ImportOptions(), fanOut(@[ticker, shown]))

  test "a short run draws only the last frame, which stays, and the done line":
    let d = fresh("short")
    bytesToFile(d / "a.fit", tiny(base + 1))
    writeFile(d / "bad.fit", "junk")
    let f = Fake()
    let sum = f.run(d, 0)                 # the clock never moves
    check sum.imported == 1
    check sum.failed == 1
    let drawn = f.live.join
    check f.live.len == 1                 # one write: the last frame
    check drawn.contains("importing 2 / 2\n")
    check drawn.contains("imported 1 · skipped 0 · failed 1 (bad format 1)")
    check drawn.endsWith("\e[?25h")       # the cursor is back
    check not drawn.contains("bad.fit")   # no line per failure
    check f.outs == @["done: 2 files: 1 imported, 0 skipped, 1 failed (bad format 1); " &
                      "details in /x/nch.log\n"]

  test "a longer run draws frames that follow it, and the last one stays":
    let d = fresh("long")
    for i in 1 .. 5: bytesToFile(d / ("r" & $i & ".fit"), tiny(base + i))
    writeFile(d / "r6-bad.fit", "junk")
    let f = Fake()
    discard f.run(d, 200)                 # every event takes 200 ms
    let drawn = f.live.join
    check drawn.startsWith("\e[?25l")
    check drawn.contains("importing ")
    check drawn.contains("imported 5")
    check not drawn.contains("r6-bad.fit: ")      # failures are not printed
    check drawn.endsWith("failed 1 (bad format 1)\n\e[J\e[?25h")
    check f.outs.len == 1
