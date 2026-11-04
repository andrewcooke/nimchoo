## With NCH_TEST_TIMES set, the slowest tests are listed when the run ends (to see where the
## time goes).  Imported by tests/all.nim.

import std/[algorithm, exitprocs, monotimes, os, strutils, times, unittest]

type Timing = ref object of OutputFormatter
  names: seq[string]
  started: MonoTime
  current: string
  suite: string
  taken: seq[(int64, string)]    # (nanoseconds, suite: test)

method suiteStarted*(f: Timing, suiteName: string) = f.suite = suiteName
method testStarted*(f: Timing, testName: string) =
  f.current = testName
  f.started = getMonoTime()
method testEnded*(f: Timing, r: TestResult) =
  f.taken.add ((getMonoTime() - f.started).inNanoseconds, f.suite & ": " & f.current)
method suiteEnded*(f: Timing) = discard

if existsEnv("NCH_TEST_TIMES"):
  let f = Timing()
  addOutputFormatter(f)
  addExitProc(proc() =
    f.taken.sort(order = SortOrder.Descending)
    var total = 0'i64
    for (n, _) in f.taken: total += n
    stderr.write "\nslowest tests (of " & $f.taken.len & ", " & $(total div 1_000_000) & " ms in all):\n"
    for (n, name) in f.taken[0 ..< min(15, f.taken.len)]:
      stderr.write align($(n div 1_000_000), 7) & " ms  " & name & "\n")
