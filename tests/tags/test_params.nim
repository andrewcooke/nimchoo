## `nch tags`: the command line (src/nimchoo/packages/tags/params.nim).

import std/[sequtils, strutils, unittest]
import nimchoo/packages/tags/[params, tag]
import nimchoo/packages/util/args/args

suite "nch tags: the command line":
  test "no criteria: the selection; --all: everything; --names: a criterion, --within narrows it":
    check parseArgs(@[]).params.scope.kind == tsSelection
    check parseArgs(@["--all"]).params.scope.kind == tsAll
    let m = parseArgs(@["--names", "bike:*", "Sport:*", "--within"]).params.scope
    check m.kind == tsMatching and m.within and
      m.patterns.mapIt($it) == @["bike:*", "Sport:*"]
    check parseArgs(@["--within"]).problem.contains("narrows `--names`")
    check parseArgs(@["--all", "--names", "x"]).problem.contains("every tag")

  test "one action: --add, --delete or --rename":
    check parseArgs(@["--add", "hard", "bike:x"]).params.action.tags.mapIt($it) ==
      @["hard", "bike:x"]
    check parseArgs(@["--names", "x", "--delete"]).params.action.kind == taDelete
    check parseArgs(@["--add", "a", "--delete"]).problem.contains("together")
    check parseArgs(@["--add", "a b"]).problem.contains("' '")

  test "--rename renames one tag, named whole":
    let r = parseArgs(@["--names", "bike:uk", "--rename", "bike:hybrid"]).params.action
    check r.kind == taRename and $r.old == "bike:uk" and $r.new == "bike:hybrid"
    check parseArgs(@["--rename", "x"]).problem.contains("renames one tag")
    check parseArgs(@["--names", "bike:*", "--rename", "x"]).problem.contains("one tag")
    check parseArgs(@["--names", "a", "b", "--rename", "x"]).problem.contains("one tag")
