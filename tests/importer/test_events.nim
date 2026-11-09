import std/[os, sequtils, strutils, unittest]
import nimchoo/packages/commands/activitiescmd/sinks
import nimchoo/packages/importer/batch
import nimchoo/packages/importer/events
import nimchoo/packages/importer/failure
import nimchoo/packages/db/store
import nimchoo/modules
import nimchoo/packages/util/warnings/warnings
import ../support/fitbuilder

const base = 900_000_000

let dir = getTempDir() / "nch-test-import-events"

type Events = ref object
  all: seq[ImportEvent]

proc sink(e: Events): Sink =
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    e.all.add ev

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

proc run(
    st: Store, targets: seq[string], opts = ImportOptions()
): (seq[ImportEvent], Summary) =
  let e = Events()
  let s = importPaths(st, targets, opts, e.sink)
  (e.all, s)

func dones(evs: seq[ImportEvent]): seq[ImportEvent] =
  evs.filterIt(it.kind == evFileDone)

suite "import events: a run":
  test "start, then each file starts and is done, then the end":
    let d = fresh("order")
    bytesToFile(d / "a.fit", tiny(base + 1))
    bytesToFile(d / "b.fit", tiny(base + 2))
    let st = openStore(d / "x.db", allFragments)
    defer:
      st.close()
    let (evs, sum) = run(st, @[d])
    check evs.mapIt(it.kind) ==
      @[evStart, evFileStart, evFileDone, evFileStart, evFileDone, evFinish]
    check evs[0].total == 2
    check evs[1].startIndex == 1
    check evs[1].startPath == d / "a.fit"
    check evs[2].index == 1
    check evs[2].outcome == oImported
    check evs[2].counts == Counts(activities: 1, segments: 1, coords: 1)
    check evs[4].index == 2
    check evs[5].summary == sum
    check sum.total == 2
    check sum.done == 2
    check sum.imported == 2

  test "unchanged, duplicate, and known failure":
    let d = fresh("outcomes")
    bytesToFile(d / "a.fit", tiny(base + 1))
    writeFile(d / "bad.fit", "junk")
    let st = openStore(d / "x.db", allFragments)
    defer:
      st.close()
    discard run(st, @[d])
    let (again, s1) = run(st, @[d])
    check again.dones.mapIt(it.outcome) == @[oUnchanged, oKnownFailure]
    check again.dones[1].failure == fkBadFormat
    check s1.unchanged == 1
    check s1.known == 1
    check s1.failed == 0
    let (slow, s2) = run(st, @[d], ImportOptions(slow: true))
    check slow.dones.mapIt(it.outcome) == @[oDuplicate, oFailed]
    check s2.failures[fkBadFormat] == 1

  test "a path that is not there is a failure with no start event":
    let d = fresh("missing")
    let st = openStore(d / "x.db", allFragments)
    defer:
      st.close()
    let (evs, sum) = run(st, @[d / "nonesuch"])
    check evs.mapIt(it.kind) == @[evStart, evFileDone, evFinish]
    check evs[1].outcome == oFailed
    check evs[1].failure == fkNotFound
    check sum.failures[fkNotFound] == 1

suite "import events: failures by kind":
  test "no activity, bad format, bad time":
    let d = fresh("kinds")
    bytesToFile(
      d / "1-nosession.fit",
      fitFile(defn(0, 20, @[(253, 4, uint32T)]) & b(0) & le32(base)),
    )
    writeFile(d / "2-junk.fit", "this is not a fit file at all")
    bytesToFile(
      d / "3-badtime.fit",
      fitFile(
        defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T)]) & b(1) & le32(100) & le32(
          100
        )
      ),
    )
    let st = openStore(d / "x.db", allFragments)
    defer:
      st.close()
    let (evs, sum) = run(st, @[d])
    check evs.dones.mapIt(it.failure) == @[fkNoActivity, fkBadFormat, fkBadTime]
    check evs.dones.allIt(it.outcome == oFailed and it.message.len > 0)
    check sum.failed == 3
    check sum.failures[fkNoActivity] == 1
    check sum.failures[fkBadFormat] == 1
    check sum.failures[fkBadTime] == 1

  test "monitor files are counted apart, are not failures, and are not read again":
    let d = fresh("monitor")
    bytesToFile(
      d / "1-monitor.fit",
      fitFile(
        defn(4, 0, @[(0, 1, enumT)]) & b(4, 32) & defn(0, 20, @[(253, 4, uint32T)]) &
          b(0) & le32(base)
      ),
    )
    bytesToFile(
      d / "2-nosession.fit",
      fitFile(defn(0, 20, @[(253, 4, uint32T)]) & b(0) & le32(base)),
    )
    let st = openStore(d / "x.db", allFragments)
    defer:
      st.close()
    let (evs, sum) = run(st, @[d])
    check evs.dones.mapIt(it.outcome) == @[oMonitor, oFailed]
    check sum.monitor == 1 and sum.failed == 1 and sum.failures[fkMonitor] == 0
    check summaryLine(sum).contains(", 1 monitor, 1 failed")
    check plainLines(evs.dones[0], quiet = false).stdout.len == 0
      # (nothing printed for it)
    let (again, sum2) = run(st, @[d])
    check again.dones.mapIt(it.outcome) ==
      @[oMonitor, oKnownFailure] # (remembered: not read)
    check sum2.monitor == 1 and sum2.known == 1 and sum2.failed == 0

  test "a file that cannot be read":
    let d = fresh("unreadable")
    let path = d / "a.fit"
    bytesToFile(path, tiny(base + 1))
    setFilePermissions(path, {})
    defer:
      setFilePermissions(path, {fpUserRead, fpUserWrite})
    let st = openStore(d / "x.db", allFragments)
    defer:
      st.close()
    let (evs, _) = run(st, @[d])
    if evs.dones[0].outcome == oFailed: # (a superuser can read anything)
      check evs.dones[0].failure == fkUnreadable

suite "import events: advisories":
  test "advisories travel with the file, and are counted":
    let d = fresh("warnings")
    bytesToFile(
      d / "dup.fit",
      fitFile(
        defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)]) & b(0) &
          le32(base) & le32(1) & le32(1) & b(0) & le32(base) & le32(2) & le32(2) &
          defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T)]) & b(1) & le32(base) &
          le32(base)
      ),
    )
    let st = openStore(d / "x.db", allFragments)
    defer:
      st.close()
    let (evs, sum) = run(st, @[d])
    check evs.dones[0].advisories.mapIt(it.kind) == @[wkDuplicateTime]
    check sum.advisories == 1

suite "import events: sinks":
  test "fanOut gives every sink every event, in order":
    let a = Events()
    let b = Events()
    let both = fanOut(@[a.sink, b.sink])
    both(ImportEvent(kind: evStart, total: 3))
    both(ImportEvent(kind: evFinish, summary: Summary(total: 3)))
    check a.all.mapIt(it.kind) == @[evStart, evFinish]
    check b.all.mapIt(it.kind) == @[evStart, evFinish]

  test "plain lines for each outcome":
    func done(o: Outcome, msg = ""): ImportEvent =
      ImportEvent(
        kind: evFileDone,
        index: 1,
        path: "p.fit",
        outcome: o,
        counts: Counts(activities: 1, segments: 2, coords: 3),
        failure: fkBadFormat,
        message: msg,
      )
    check plainLines(done(oImported), false).stdout ==
      @["imported  p.fit  (1 activity, 2 segments, 3 coordinates)"]
    check plainLines(done(oDuplicate), false).stdout ==
      @["duplicate p.fit  (already imported)"]
    var same = done(oDuplicate)
    same.sameAs = "q/p.fit"
    check plainLines(same, false).stdout ==
      @["duplicate p.fit  (same content as q/p.fit)"]
    check plainLines(done(oUnchanged), false).stdout == @["unchanged p.fit"]
    check plainLines(done(oKnownFailure, "why"), false).stdout ==
      @["known     p.fit  (failed before: why)"]
    check plainLines(done(oFailed, "why"), false).stdout == @["failed    p.fit: why"]

  test "quiet keeps only failures and the summary":
    func done(o: Outcome): ImportEvent =
      ImportEvent(kind: evFileDone, index: 1, path: "p.fit", outcome: o)
    for o in [oImported, oDuplicate, oUnchanged, oKnownFailure]:
      check plainLines(done(o), true).stdout.len == 0
    check plainLines(done(oFailed), true).stdout.len == 1
    check plainLines(
      ImportEvent(
        kind: evFinish, summary: Summary(done: 3, imported: 1, duplicates: 1, failed: 1)
      ),
      true,
    ).stdout == @["read: 3 files, 1 imported, 1 duplicate, 1 failed"]

  test "the summary mentions known failures":
    check summaryLine(Summary(done: 5, unchanged: 3, known: 2)) ==
      "5 files, 0 imported, 3 unchanged, 0 failed, 2 known failures (use --slow to retry)"
    check summaryLine(Summary(done: 1, known: 1)).contains("1 known failure (")

  test "notes about the run go to stderr at the end":
    let lines = plainLines(
      ImportEvent(kind: evFinish, summary: Summary(notes: @["something odd"])), false
    )
    check lines.stderr == @["note: something odd"]
