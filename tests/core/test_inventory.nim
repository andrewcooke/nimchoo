## What `nch packages` shows (core/inventory.nim), on made-up packages and on the real registry.

import std/[sequtils, strutils, unittest]
import nimchoo/core/[errors, extension, fragment, inventory, manifest, registry]
import nimchoo/registry as generated

const pointP = ExtensionPoint[int](name: "b/p")

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(pointP, 7, priority = 2), contribute(pointP, 8)]

func frag(name, sql: string): Fragment =
  Fragment(name: name, sql: sql)

proc world(): Inventory {.raises: [].} =
  ## db <- a <- b <- c, with c also naming a (which b implies); b defines a point that c contributes to.
  let packages = @[
    Registered(name: "db", package: Package()),
    Registered(name: "a", package: Package(depends: @["db"])),
    Registered(
      name: "b",
      package: Package(
        depends: @["a", "db"],
        defines: @[PointDecl(name: "b/p", summary: "a number")],
        commands: @[CommandDecl(name: "bee", summary: "does b things")],
      ),
    ),
    Registered(
      name: "c",
      package: Package(depends: @["b", "a", "db"], contributes: contributions),
    ),
  ]
  let fragments = @[
    frag("db/001-x.sql", "create table dbt (x)"),
    frag("a/001-x.sql", "create table ta (x)"),
    frag("b/001-x.sql", "create table tb (x)"),
  ]
  try:
    result = inventoryOf(
      packages, collectExtensions(packages), collectPoints(packages), fragments
    )
  except PackageError as e:
    raiseAssert e.msg

suite "the inventory of packages":
  test "layers, dependents, tables, fragments and commands":
    let inv = world()
    check inv.packages.mapIt(it.name) == @["db", "a", "b", "c"]
    check inv.packages.mapIt(it.layer) == @[0, 1, 2, 3]
    check inv.packages[inv.find("db")].dependents == @["a", "b", "c"]
    check inv.packages[inv.find("a")].tables == @["ta"]
    check inv.packages[inv.find("b")].fragments == @["b/001-x.sql"]
    check inv.packages[inv.find("b")].commands[0].name == "bee"
    check inv.find("b") == 2
    check inv.find("nope") == -1

  test "who may read a table: the packages that depend on its owner; every package for the tables of db":
    let inv = world()
    let ta = inv.tables.filterIt(it.name == "ta")[0]
    check ta.owner == "a" and ta.readers == @["b", "c"] and not ta.everyone
    check inv.tables.filterIt(it.name == "dbt")[0].everyone

  test "the points: who defines them, and who contributes, in the order used":
    let inv = world()
    check inv.points.len == 1
    let p = inv.points[0]
    check p.name == "b/p" and p.owner == "b" and p.typeName == "int"
    check p.contributors == @[("c", 0), ("c", 2)]
    check inv.packages[inv.find("c")].contributes == @[("b/p", 2), ("b/p", 0)] or
      inv.packages[inv.find("c")].contributes.len == 2

suite "the views":
  test "the summary has a line for each package, with what it provides":
    let lines = summaryLines(world())
    check lines.len == 5 and lines[0].startsWith("package")
    check "command bee" in lines[3] and "defines b/p" in lines[3]
    check "adds to b/p" in lines[4]

  test "the detail of a package":
    let text = detailLines(world(), "b", 80).join("\n")
    check "package b  (layer 2)" in text
    check "depends on" in text and "a db" in text
    check "used by" in text and "tb" in text
    check "ta (a)" in text # (it may read the tables of a)
    check "bee - does b things" in text
    check "added to by" in text and "c" in text

  test "the points":
    let text = pointLines(world(), 80).join("\n")
    check "b/p   defined by b   holds int" in text
    check "1. c (priority 0)" in text and "2. c (priority 2)" in text

  test "the tables":
    let lines = tableLines(world())
    check lines[0].startsWith("table")
    check lines.anyIt(it.startsWith("dbt") and it.endsWith("every package"))
    check lines.anyIt(it.startsWith("ta") and it.endsWith("b c"))

suite "the graphs":
  test "the tree of what a package depends on; a package drawn above is not drawn again":
    check treeLines(world(), "c") ==
      @[
        "c", "├── a", "│   └── db", "├── b",
        "│   ├── a (above)", "│   └── db (above)",
        "└── db (above)",
      ]

  test "the tree of what depends on a package":
    check treeLines(world(), "a", reverse = true) ==
      @["a", "├── b", "│   └── c", "└── c (above)"]

  test "a package with nothing under it is a single line":
    check treeLines(world(), "db") == @["db"]

  test "the layers: highest first, each package with the dependencies that are not implied by others":
    let lines = layerLines(world(), 80)
    check lines[0] == "layer 3"
    check lines[1].startsWith("  c") and lines[1].endsWith("← b")
      # (c names a and db too, but b implies them)
    check "layer 0  (depend on nothing)" in lines
    check lines.anyIt(it == "  db")

  test "Graphviz text: one rank for each layer, an arrow for each dependency that carries information":
    let dot = dotText(world())
    check dot.startsWith("digraph packages {")
    check "\"c\" -> \"b\";" in dot
    check "\"c\" -> \"a\";" notin dot
    check "{ rank=same; \"db\"; }" in dot

suite "the real registry":
  let inv = inventoryOf(
    generated.packages, generated.extensions, generated.points, generated.schema
  )

  test "every package is there, after the packages it depends on, in a higher layer":
    check inv.packages.len == generated.packages.len
    for p in inv.packages:
      for d in p.depends:
        check inv.packages[inv.find(d)].layer < p.layer
        check p.name in inv.packages[inv.find(d)].dependents

  test "a tree has no package twice except marked":
    for p in inv.packages:
      var drawn: seq[string]
      for l in treeLines(inv, p.name):
        let name = l.splitWhitespace.filterIt(it[0].isAlphaAscii)[0]
        if "(above)" notin l:
          check name notin drawn
          drawn.add name

  test "every table has an owner that is a package, and the layers print without error":
    for t in inv.tables:
      check inv.find(t.owner) >= 0
    check layerLines(inv, 100).len > inv.packages.len
    check dotText(inv).endsWith("}\n")

  test "the points of the registry are all listed, with their contributors":
    check inv.points.len == 5
    check inv.points.anyIt(
      it.name == "importer/after" and it.contributors[0].package == "selection"
    )
