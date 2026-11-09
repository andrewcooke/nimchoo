import std/[os, strutils, unittest]
import nimchoo/log/command as logCommand
import nimchoo/core/logfile
import nimchoo/packages/ui/vocabulary
import nimchoo/log/lines

let dir = getTempDir() / "nch-test-log-command"

proc logWith(name: string, lines: varargs[string]): string =
  removeDir(dir / name)
  createDir(dir / name)
  result = dir / name / "nch.log"
  writeFile(result, lines.join("\n") & "\n")

const
  run1 = "2026-11-02T10:00:00Z INFO  activities run        /a"
  fail1 =
    "2026-11-02T10:00:01Z ERROR activities failed     /a/bad.fit  (bad format) why"
  run2 = "2026-11-02T11:00:00Z INFO  activities run        /b"
  dup2 =
    "2026-11-02T11:00:01Z INFO  activities duplicate  /b/x.fit  same content as /b/y.fit"

suite "nch log: the command line":
  test "commands and events are told apart":
    let p = parseArgs(@["activities", "failed", "map", "advisory", "--last", "-n", "5"])
    check p.problem == ""
    check p.filter.commands == @["activities", "map"]
    check p.filter.events == {leFailed, leAdvisory}
    check p.filter.last and p.filter.count == 5
  test "no arguments: no filter":
    check parseArgs(@[]).filter == Filter()
  test "problems":
    check parseArgs(@["bogus"]).problem.contains("neither a command nor an event")
    check parseArgs(@["bogus"]).problem.contains("advisory") # the known names are listed
    check parseArgs(@["bogus"]).problem.contains("map")
    check parseArgs(@["-n"]).problem.contains("needs a value")
    check parseArgs(@["-n", "0"]).problem.contains("number of lines")
    check parseArgs(@["-n", "x"]).problem.contains("number of lines")
    check parseArgs(@["--bogus"]).problem.contains("unexpected option")
    check parseArgs(@["-h"]).help

suite "nch log: showing":
  test "the lines, plain without colour":
    let p = logWith("plain", run1, fail1, run2, dup2)
    check show(p, Filter(commands: @["activities"], last: true), false).lines ==
      @[run2, dup2]
    check show(p, Filter(events: {leFailed}), false).lines == @[fail1]
  test "with colour the level word and the event word are coloured":
    let p = logWith("colour", fail1)
    let r = show(p, Filter(), true)
    check r.lines[0].contains("\e[31m\e[1mfailed\e[0m")
    check r.lines[0].startsWith(
      "2026-11-02T10:00:01Z \e[31m\e[1mERROR\e[0m activities "
    ) # (the level too)
  test "no log yet":
    check show(dir / "nonesuch" / "nch.log", Filter(), false).problem.contains("no log")
  test "no run to show, and why it may be":
    let p = logWith("norun", "2026-11-01T15:58:42Z INFO  activities start: 3 files")
    let r = show(p, Filter(commands: @["activities"], last: true), false)
    check r.problem.contains("no run of activities")
    check r.problem.contains("not recognised")
    let q = logWith("norun2", run1)
    check not show(q, Filter(commands: @["heatmap"], last: true), false).problem
      .contains("not recognised")
