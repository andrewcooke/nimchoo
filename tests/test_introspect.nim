## `nch packages` (src/nimchoo/introspect.nim): its command line and its views.

import std/[options, sequtils, strutils, unittest]
from std/unicode import runeLen
import nimchoo/core/registry
import nimchoo/introspect
import nimchoo/packages/util/args/args
from nimchoo/registry import allAccess, commands, schema
import ./support/styles
from nimchoo/registry import allFragments

suite "nch packages: the command line":
  test "no arguments is the list; a name is the detail":
    check parseArgs(@[]).params.view == vList
    let f = parseArgs(@["-L", "2", "-U", "db", "-B", "climbs", "-T", "effort"]).params
    check f.view == vList and f.filter.layer == some(2) and f.filter.uses == some("db") and
      f.filter.usedBy == some("climbs") and f.filter.table == some("effort")
    check parseArgs(@["-L", "x"]).problem.contains("is a layer")
    check parseArgs(@["-L", "1", "--points"]).problem.contains("narrow the list")
    check parseArgs(@["-U", "db", "climbs"]).problem.contains("narrow the list")
    let p = parseArgs(@["importer"])
    check p.problem == "" and p.params.view == vDetail and p.params.package == "importer"

  test "the other views":
    check parseArgs(@["--points"]).params.view == vPoints
    check parseArgs(@["--dot"]).params.view == vDot
    check parseArgs(@["--graph"]).params.view == vLayers
    check parseArgs(@["--graph", "db"]).params.view == vTree
    check parseArgs(@["db", "--graph"]).params.root == "db"
    check parseArgs(@["--graph", "--reverse", "db"]).params.reverse

  test "combinations that mean nothing are refused":
    check parseArgs(@["--points", "--dot"]).problem.contains("choose one")
    check parseArgs(@["importer", "--points"]).problem.contains(
      "goes with nothing but `--graph`"
    )
    check parseArgs(@["--reverse"]).problem.contains("`--reverse` goes with")
    check parseArgs(@["--graph", "--reverse"]).problem.contains("`--reverse` goes with")
    check parseArgs(@["a", "b"]).problem.len > 0
    check parseArgs(@["--nonesuch"]).problem.len > 0

  test "every option has help and is in the usage, at any width":
    for width in [50, 80, 120]:
      let text = usageText(width).plainText
      for line in text.splitLines:
        if not (line.startsWith("usage: ") or line.startsWith("       nch ")):
          check line.runeLen <= width
      for d in packagesSpec().docs:
        for n in d.names:
          check n in text

suite "nch packages: the commands":
  test "nch provides the command itself; no package may take its name":
    check "packages" in builtinCommands
    check "packages" notin commands.mapIt(it.name)

  test "a misspelt package name is answered with the names it may be, the closest first":
    let names = @["climbs", "calendar", "cache", "names", "naming"]
    check closeNames("clims", names) == @["climbs"]
    check closeNames("Climb", names) ==
      @["climbs"] # (case does not matter; it holds what was typed)
    check closeNames("nme", names)[0] == "names"
    check closeNames("zzz", names).len == 0
