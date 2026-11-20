## The packages of nch as a Graphviz graph (a tool for looking at the design: no part of nch).
##
##     nim c -d:release --hints:off -o:build/dot tools/dot.nim
##     build/dot | dot -Tsvg > packages.svg

import std/[sequtils, sets, strformat, strutils, tables]
import nimchoo/core/[inventory, names]

func reducedDepends(inv: Inventory): Table[string, seq[string]] =
  ## For each package the packages it depends on directly and not through another it depends on (the edges that
  ## carry information; the rest are implied).
  var reach: Table[string, HashSet[string]]
    # every package a package depends on, directly or not (the packages are in dependency order)
  for p in inv.packages:
    var all = initHashSet[string]()
    for d in p.depends:
      all.incl d.normalised
      all.incl reach.getOrDefault(d.normalised)
    reach[p.name.normalised] = all
  for p in inv.packages:
    var kept: seq[string]
    for d in p.depends:
      var implied = false
      for other in p.depends:
        if other.normalised != d.normalised and
            d.normalised in reach.getOrDefault(other.normalised):
          implied = true
      if not implied:
        kept.add d
    result[p.name.normalised] = kept

func dotText*(inv: Inventory): string =
  ## The dependencies as a Graphviz graph: an arrow from a package to each it depends on directly and not through another
  ## (the implied ones are left out: the picture would be a tangle), the packages of a layer on one rank.
  let reduced = reducedDepends(inv)
  result =
    "digraph packages {\n  rankdir=BT;\n  node [shape=box, fontname=\"monospace\"];\n"
  var top = 0
  for p in inv.packages:
    top = max(top, p.layer)
  for l in 0 .. top:
    let here = inv.packages.filterIt(it.layer == l).mapIt("\"" & it.name & "\"")
    if here.len > 0:
      result.add "  { rank=same; " & here.join("; ") & "; }\n"
  for p in inv.packages:
    for d in reduced.getOrDefault(p.name.normalised):
      result.add fmt"  ""{p.name}"" -> ""{d}"";" & "\n"
  result.add "}\n"

when isMainModule:
  import nimchoo/registry as generated

  stdout.write dotText(
    inventoryOf(
      generated.packages, generated.extensions, generated.points, generated.schema
    )
  )
