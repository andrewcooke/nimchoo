import std/[options, os, sequtils, strutils, times, unittest]
import nimchoo/ui/logfile

let dir = getTempDir() / "nch-test-logfile"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

proc fixed(): Time {.raises: [].} =
  fromUnix(1_793_000_000) # 2026-10-26T07:33:20Z

proc lines(path: string): seq[string] =
  readFile(path).splitLines.filterIt(it.len > 0)

suite "log: where it goes":
  test "NCH_LOG wins, and empty switches logging off":
    check logPath(some "/x/my.log", some "/s", some "/h") == some "/x/my.log"
    check logPath(some "", some "/s", some "/h").isNone
  test "XDG_STATE_HOME, if absolute; else the home directory":
    check logPath(none string, some "/s", some "/h") == some "/s/nch/nch.log"
    check logPath(none string, some "rel", some "/h") ==
      some "/h/.local/state/nch/nch.log"
    check logPath(none string, none string, some "/h") ==
      some "/h/.local/state/nch/nch.log"
  test "no home, nothing":
    check logPath(none string, none string, none string).isNone
    check logPath(none string, none string, some "").isNone

suite "log: lines":
  test "time, level, topic, text":
    check logLine(fixed(), lvInfo, "import", leDuplicate, "hello") ==
      "2026-10-26T07:33:20Z INFO  import    duplicate  hello"
    check logLine(fixed(), lvError, "x", leFailed, "bad") ==
      "2026-10-26T07:33:20Z ERROR x         failed     bad"
    check logLine(fixed(), lvInfo, "a-longer-command", leDone, "t") ==
      "2026-10-26T07:33:20Z INFO  a-longer-command  done       t"
  test "one line whatever the text":
    check '\n' notin logLine(fixed(), lvWarn, "t", leNote, "a\nb\r\nc")

suite "log: files":
  test "lines are appended, across opens":
    let d = fresh("append")
    let path = d / "sub" / "nch.log" # directory is created
    let a = openLog(path, now = fixed)
    check a.problem == ""
    a.log(lvInfo, cmMap, leNote, "one")
    a.close()
    let b = openLog(path, now = fixed)
    b.log(lvInfo, cmMap, leNote, "two")
    b.close()
    check lines(path).len == 2
    check lines(path)[1].endsWith("two")

  test "warnings and errors are on disk before the log is closed":
    let d = fresh("flush")
    let l = openLog(d / "nch.log", now = fixed)
    defer:
      l.close()
    l.log(lvWarn, cmMap, leNote, "careful")
    check lines(d / "nch.log").len == 1
    l.log(lvError, cmMap, leNote, "bad")
    check lines(d / "nch.log").len == 2

  test "a nil or closed log ignores everything":
    var none: Log
    none.log(lvInfo, cmMap, leNote, "x")
    none.close()
    check not none.enabled
    let l = openLog(fresh("closed") / "nch.log")
    l.close()
    l.log(lvInfo, cmMap, leNote, "x")
    check not l.enabled

  test "a log that cannot be opened is disabled, with the reason":
    let d = fresh("blocked")
    writeFile(d / "file", "")
    let l = openLog(d / "file" / "nch.log") # parent is a file
    check not l.enabled
    check l.problem.startsWith("cannot open")
    l.log(lvInfo, cmMap, leNote, "x") # and nothing happens
    l.close()

suite "log: rotation":
  test "over the limit: .1, .2, .3, and the oldest goes":
    let d = fresh("rotate")
    let path = d / "nch.log"
    for round in 1 .. 5:
      writeFile(path, $round & " " & "x".repeat(200))
      rotate(path, maxBytes = 100, keep = 3)
      check not fileExists(path)
    check readFile(path & ".1").startsWith("5 ")
    check readFile(path & ".2").startsWith("4 ")
    check readFile(path & ".3").startsWith("3 ")
    check not fileExists(path & ".4")

  test "under the limit nothing happens":
    let d = fresh("small")
    let path = d / "nch.log"
    writeFile(path, "short")
    rotate(path, maxBytes = 100)
    check readFile(path) == "short"
    check not fileExists(path & ".1")

  test "opening rotates":
    let d = fresh("openrotate")
    let path = d / "nch.log"
    writeFile(path, "x".repeat(300))
    let l = openLog(path, maxBytes = 100, now = fixed)
    l.log(lvInfo, cmMap, leNote, "fresh")
    l.close()
    check lines(path).len == 1
    check readFile(path & ".1").len == 300
