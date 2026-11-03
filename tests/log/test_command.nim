import std/[os, strutils, unittest]
import nimchoo/log/command as logCommand
import nimchoo/ui/logfile
import nimchoo/ui/vocabulary
import nimchoo/log/lines

let dir = getTempDir() / "nch-test-log-command"

proc logWith(name: string, lines: varargs[string]): string =
  removeDir(dir / name)
  createDir(dir / name)
  result = dir / name / "nch.log"
  writeFile(result, lines.join("\n") & "\n")

const
  run1 = "2026-11-02T10:00:00Z INFO  import    run        /a"
  fail1 = "2026-11-02T10:00:01Z ERROR import    failed     /a/bad.fit  (bad format) why"
  run2 = "2026-11-02T11:00:00Z INFO  import    run        /b"
  dup2 = "2026-11-02T11:00:01Z INFO  import    duplicate  /b/x.fit  same content as /b/y.fit"

suite "nch log: the command line":
  test "commands and events are told apart":
    let p = parseArgs(@["import", "failed", "list", "advisory", "--last", "-n", "5"])
    check p.problem == ""
    check p.filter.commands == @["import", "list"]
    check p.filter.events == {leFailed, leAdvisory}
    check p.filter.last and p.filter.count == 5
  test "no arguments: no filter":
    check parseArgs(@[]).filter == Filter()
  test "problems":
    check parseArgs(@["bogus"]).problem.contains("neither a command nor an event")
    check parseArgs(@["bogus"]).problem.contains("advisory")        # the known names are listed
    check parseArgs(@["bogus"]).problem.contains("heatmap")
    check parseArgs(@["-n"]).problem.contains("number of lines")
    check parseArgs(@["-n", "0"]).problem.contains("number of lines")
    check parseArgs(@["-n", "x"]).problem.contains("number of lines")
    check parseArgs(@["--bogus"]).problem.contains("unexpected option")
    check parseArgs(@["-h"]).help

suite "nch log: showing":
  test "the lines, plain without colour":
    let p = logWith("plain", run1, fail1, run2, dup2)
    check show(p, Filter(commands: @["import"], last: true), false).lines == @[run2, dup2]
    check show(p, Filter(events: {leFailed}), false).lines == @[fail1]
  test "with colour the event word is coloured":
    let p = logWith("colour", fail1)
    let r = show(p, Filter(), true)
    check r.lines[0].contains("\e[31m\e[1mfailed\e[0m")
    check r.lines[0].startsWith("2026-11-02T10:00:01Z ERROR import    ")
  test "no log yet":
    check show(dir / "nonesuch" / "nch.log", Filter(), false).problem.contains("no log")
  test "no run to show, and why it may be":
    let p = logWith("norun", "2026-11-01T15:58:42Z INFO  import  start: 3 files")
    let r = show(p, Filter(commands: @["import"], last: true), false)
    check r.problem.contains("no run of import")
    check r.problem.contains("not recognised")
    let q = logWith("norun2", run1)
    check not show(q, Filter(commands: @["heatmap"], last: true), false).problem.contains("not recognised")
