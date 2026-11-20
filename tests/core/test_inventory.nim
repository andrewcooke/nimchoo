## What `nch packages` shows (core/inventory.nim), on made-up packages and on the real registry.

import std/[algorithm, options, sequtils, strutils, unittest]
import nimchoo/core/[errors, extension, fragment, inventory, line, manifest, registry]
import nimchoo/registry as generated
import ../support/styles

const pointP = ExtensionPoint[int](name: "b/p")

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(pointP, 7, priority = 2), contribute(pointP, 8)]

func frag(name, sql: string): Fragment =
  Fragment(name: name, sql: sql)

proc world(): Inventory {.raises: [].} =
  ## db <- a <- b <- c, with c also naming a (which b implies); b defines a point that c contributes to.
  let packages = @[
    Registered(name: "db", package: Package(), summary: "Package db is the base."),
    Registered(name: "a", package: Package(depends: @["db"]), summary: "Package a."),
    Registered(
      name: "b",
      path: "src/nimchoo/packages/b/",
      summary: "Package b is for b things.",
      doc: "Package b is for b things.\n\nIt has a **paragraph** more.",
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

suite "the filters of the list":
  # (db on layer 0; a uses db; b uses a and db; c uses b, a and db.  Tables: dbt of db, every package reads it; ta of a,
  # which b and c may read; tb of b, which c may read)
  proc kept(f: PackageFilter): seq[string] =
    let inv = world()
    inv.packages.filterIt(inv.keeps(f, it)).mapIt(it.name)

  test "-L: a layer; -U: those that use a package; -B: those a package uses":
    check kept(PackageFilter()) == @["db", "a", "b", "c"]
    check kept(PackageFilter(layer: some(1))) == @["a"]
    check kept(PackageFilter(uses: some("a"))) == @["b", "c"]
    check kept(PackageFilter(usedBy: some("c"))) == @["db", "a", "b"]
    check kept(PackageFilter(usedBy: some("a"))) == @["db"]
    check kept(PackageFilter(uses: some("c"))).len == 0

  test "-T: those that own the table or may read it":
    check kept(PackageFilter(table: some("ta"))) == @["a", "b", "c"]
    check kept(PackageFilter(table: some("tb"))) == @["b", "c"]
    check kept(PackageFilter(table: some("dbt"))) == @["db", "a", "b", "c"]

  test "together, each narrows the list further":
    check kept(PackageFilter(uses: some("a"), layer: some(3))) == @["c"]
    check kept(PackageFilter(table: some("tb"), usedBy: some("c"))) == @["b"]
    let lines = summaryLines(world(), 80, PackageFilter(layer: some(1))).texts
    check lines.anyIt(it.startsWith("a ")) and not lines.anyIt(it.startsWith("b "))

suite "the views":
  test "the summary has a line for each package with what it is for, then what it provides":
    let cells = summaryLines(world(), 200)
    let lines = cells.texts
    check lines[0].startsWith("package") and "what it is for" in lines[0] and
      " │ L  U  B  T │ " in lines[0]
    check lines[1].startsWith("────") and "┼" in lines[1]
      # (the rule under the headings)
    check lines[^1].startsWith("L: the layer") or
      lines.anyIt(it.startsWith("L: the layer"))
    let named = lines.filterIt(
      it.len > 0 and it[0].isAlphaAscii and not it.startsWith("package") and
        ":" notin it[0 .. min(2, it.high)] and "│" in it
    )
    check named.len > 0 and named[0].startsWith("db ")
      # (the lowest layer first: db depends on nothing)
    check lines.anyIt(
      it.startsWith("b ") and
        it.endsWith(
          "Package b is for b things.  Defines nch bee and the extension point b/p."
        )
    )
    check lines.anyIt(
      it.startsWith("c ") and it.endsWith("Contributes to b/p ×2 (priority 0, 2).")
    )
    # (the name of a command is in the style of commands, the rest is not)
    let b = cells.filterIt(it.text.startsWith("b "))[0]
    check b.filterIt(it.styles == @[styleName"cmd"]).mapIt(it.text) == @["nch bee"]
    check lines.anyIt(it.startsWith("db ") and it.endsWith("Package db is the base."))

  test "the detail of a package":
    let cells = detailLines(world(), "b", 200)
    let text = cells.texts.join("\n")
    check cells[0] ==
      @[span("package ", "em"), span("b", "pkg"), span("  "), span("layer 2", "hide")]
    check "It has a paragraph more." in text
      # (what is between ** is in em, without them)
    check cells.anyIt(span("paragraph", "em") in it)
    check "depends on" in text and "a db" in text
    check "used by" in text and "tb" in text
    check "db: dbt; a: ta" in text # (it may read the tables of a, and of db: by owner)
    check "nch bee - does b things" in text
    check cells.anyIt(span("nch bee", "cmd") in it)
    check cells.anyIt(span("src/nimchoo/packages/b/", "file") in it)
      # (the source path in the style of paths)
      # (the command in the style of commands)
    check cells.anyIt(span("a", "alt-pkg") in it and span("db", "alt-pkg") in it)
      # (the second field: on an alternate row, in the alt version of the style)
      # (depends on: the names of packages in their style)
    check "contributed to by" in text and "c ×2 (priority 0, 2)" in text
    check cells.anyIt(
      it.anyIt(
        it.text == unbroken("b/p[int]") and $it.styles[^1] in ["extn", "alt-extn"]
      )
    ) # (an extension point in its style)
    check "b/p[int] - " in text # (what --points no longer shows: the detail has it)

  test "the points":
    let cells = pointLines(world(), 80)
    let lines = cells.texts
    check cells.anyIt(span("c", "pkg") in it)
    check cells.anyIt(span("b/p", "extn") in it) # (the name of the point in its style)
    check cells.anyIt(span("b/p", "extn") in it)
    check lines[0].startsWith("extension point") and
      "contributed to by (in order)" in lines[0]
    check lines[1].startsWith("─") and "┼" in lines[1]
    check lines.anyIt(it.startsWith("b/p") and " │ b " in it and " │ c ×2 " in it)
      # (c adds twice: named once)

suite "the graphs":
  test "the tree of what a package depends on, breadth first: each package in full where it is first needed, ... where something is left out":
    let tree = treeLines(world(), "c")
    check tree.mapIt(it.text) ==
      @[
        "c", "├── a", "│   └── db", "├── b", "│   ├── a...",
        "│   └── db", "└── db",
      ]
        # (c uses a, b and db itself: all three are drawn in full under it; under a and b they are repeats, and a has
        # db under it, so it is followed by ...)
    check tree.mapIt(it.again) == @[false, false, true, false, true, true, false]

  test "without the repeats each package is drawn once, and the lines join up":
    check treeLines(world(), "c", repeats = false).mapIt(it.text) ==
      @["c", "├── a", "├── b", "└── db"]

  test "the tree of what depends on a package":
    check treeLines(world(), "a", reverse = true).mapIt(it.text) ==
      @["a", "├── b", "│   └── c", "└── c"]

  test "a package with nothing under it is a single line":
    check treeLines(world(), "db").mapIt(it.text) == @["db"]

  test "with the implied ones, every dependency is there, the implied ones marked":
    let lines = layerLines(world(), 80, implied = true)
    let c = lines.filterIt(it.mapIt(it.text).join("").startsWith("  c "))[0]
    check c[1].text == "c"
      # (the name a piece of its own: drawn in pkg, without the spaces)
    check c.filterIt(not it.implied and it.text == "b").len == 1
    check c.filterIt(it.implied).mapIt(it.text).sorted == @["a", "db"]

  test "the layers: highest first, each package with the dependencies that are not implied by others":
    let lines = layerLines(world(), 80).mapIt(it.mapIt(it.text).join(""))
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

  test "a tree draws each package in full once; a repeat is marked ..., or has nothing under it":
    for p in inv.packages:
      var full: seq[string]
      for line in treeLines(inv, p.name):
        let l = line.text
        let name =
          l.splitWhitespace.filterIt(it[0].isAlphaAscii)[0].strip(chars = {'.'})
        if line.again:
          check l.endsWith("...") or inv.packages[inv.find(name)].depends.len == 0
        else:
          check name notin full
          full.add name

  test "every table has an owner that is a package, and the layers print without error":
    for t in inv.tables:
      check inv.find(t.owner) >= 0
    check layerLines(inv, 100).len > inv.packages.len
    check layerLines(inv, 100, implied = true).len >= layerLines(inv, 100).len
    check dotText(inv).endsWith("}\n")

  test "the points of the registry are all listed, with their contributors":
    check inv.points.len == generated.points.len
    check inv.points.anyIt(
      it.name == "importer/after" and it.contributors[0].package == "selection"
    )
