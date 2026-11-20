## The packages as a Graphviz graph (tools/dot.nim), on the real registry.

import std/[strutils, unittest]
import nimchoo/core/inventory
import nimchoo/registry as generated
import ../../tools/dot

suite "tools: the packages as a Graphviz graph":
  test "a rank for each layer, and an arrow only for a dependency that is not implied by another":
    let dot = dotText(
      inventoryOf(
        generated.packages, generated.extensions, generated.points, generated.schema
      )
    )
    check dot.startsWith("digraph packages {") and dot.endsWith("}\n")
    check "{ rank=same; " in dot
    check "\"climbs\" -> \"activities\";" in dot
    check "\"climbs\" -> \"args\";" notin dot # (climbs has args through activities)
