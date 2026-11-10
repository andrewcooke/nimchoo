import std/[strutils, unittest]
import nimchoo/packages/importer/params

suite "nch import: the command line":
  test "several paths, and the options that go with them":
    let p = parseArgs(@["a", "b", "-q", "--slow", "-j", "3"])
    check p.problem == "" and p.paths == @["a", "b"] and p.quiet and p.slow and
      p.jobs == 3
  test "the options may come first":
    let p = parseArgs(@["--quiet", "--jobs", "2", "a"])
    check p.problem == "" and p.paths == @["a"] and p.quiet and p.jobs == 2
  test "it needs a path":
    check parseArgs(@[]).problem.contains("at least one path")
    check parseArgs(@["-q"]).problem.contains("at least one path")
  test "help needs no path":
    check parseArgs(@["-h"]).help
  test "bad options":
    check parseArgs(@["a", "--nonesuch"]).problem.len > 0
    check parseArgs(@["a", "-j", "0"]).problem.len > 0
    check parseArgs(@["a", "-j", "x"]).problem.len > 0
    check parseArgs(@["a", "-j"]).problem.len > 0
