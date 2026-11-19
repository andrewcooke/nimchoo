## What the packages are, as a program can tell about itself: who depends on whom, which tables each owns and may read,
## which commands it provides, which extension points it defines and what each contributes.  Made from the registry
## (`inventoryOf`), then drawn as lists, trees, layers or a Graphviz graph for `nch packages`.  Pure: no database, no
## terminal, so every view is tested with made-up packages.

import std/[algorithm, options, sequtils, sets, strformat, strutils, tables]
import
  ./[
    access, errors, extension, fragment, manifest, names, ownership, ruled, theme, wrap
  ]

{.push raises: [].}

type
  Addition* = tuple[point: string, priority: int]

  PackageInfo* = object
    name*: string
    summary*, doc*: string
      ## what the package is for: its `##` documentation, and the first line of it
    path*: string
      ## its directory, from the top of the project ("src/nimchoo/packages/fit/")
    layer*: int
      ## 0 for a package that depends on nothing, else one more than the highest of those it depends on
    depends*, dependents*: seq[string]
    tables*: seq[string] ## the tables it owns
    fragments*: seq[string]
    commands*: seq[tuple[name, summary: string]]
    defines*: seq[PointDecl]
    contributes*: seq[Addition]

  PointInfo* = object
    name*, owner*, summary*, typeName*: string
    contributors*: seq[tuple[package: string, priority: int]]
      ## in the order they are used

  TableInfo* = object
    name*, owner*: string
    readers*: seq[string]
      ## the packages that may read it besides its owner; empty with `everyone`
    everyone*: bool ## every package may read it (the tables of `db`)

  Inventory* = object
    packages*: seq[PackageInfo] ## in dependency order
    points*: seq[PointInfo]
    tables*: seq[TableInfo]

func find*(inv: Inventory, name: string): int =
  ## The index of a package, named as Nim compares names; -1 if there is none.
  for i, p in inv.packages:
    if p.name.normalised == name.normalised:
      return i
  -1

func inventoryOf*(
    packages: seq[Registered],
    extensions: Extensions,
    points: seq[tuple[owner: string, point: PointDecl]],
    fragments: seq[Fragment],
): Inventory {.raises: [PackageError].} =
  ## The inventory of packages given in dependency order.  `fragments` are all of them, the database's own first.
  var layer: Table[string, int]
  var dependents: Table[string, seq[string]]
  for p in packages:
    var l = 0
    for d in p.package.depends:
      l = max(l, layer.getOrDefault(d.normalised) + 1)
      dependents.mgetOrPut(d.normalised, @[]).add p.name
    layer[p.name.normalised] = l
  let owners = tableOwners(fragments)
  for p in packages:
    var info = PackageInfo(
      name: p.name,
      summary: p.summary,
      doc: p.doc,
      path: p.path,
      layer: layer.getOrDefault(p.name.normalised),
      depends: p.package.depends.sortedByIt(it.normalised),
      dependents: dependents.getOrDefault(p.name.normalised).sortedByIt(it.normalised),
      defines: p.package.defines,
    )
    for t, o in owners:
      if o.normalised == p.name.normalised:
        info.tables.add t
    info.tables.sort
    for f in fragments:
      if f.ownerName.normalised == p.name.normalised:
        info.fragments.add f.name
    for c in p.package.commands:
      info.commands.add (c.name, c.summary)
    for point in extensions.points:
      for c in extensions.contributions(point):
        if c.source.normalised == p.name.normalised:
          info.contributes.add (point, c.priority)
    result.packages.add info
  for (owner, d) in points:
    var info = PointInfo(name: d.name, owner: owner, summary: d.summary)
    for c in extensions.contributions(d.name):
      info.typeName = c.typeName
      info.contributors.add (c.source, c.priority)
    result.points.add info
  result.points.sort(
    proc(a, b: PointInfo): int =
      cmp(a.name, b.name)
  )
  for t, o in owners:
    var info = TableInfo(name: t, owner: o, everyone: o == sharedOwner)
    if not info.everyone:
      for p in packages:
        if p.package.depends.anyIt(it.normalised == o.normalised):
          info.readers.add p.name
      info.readers.sort
    result.tables.add info
  result.tables.sort(
    proc(a, b: TableInfo): int =
      cmp(a.name, b.name)
  )

# --- the views ---------------------------------------------------------------------------------------------------------

func listOf(items: seq[string]): string =
  if items.len == 0:
    "-"
  else:
    items.join(" ")

func countOf(items: seq[string]): string =
  $items.len

type PackageFilter* = object
  ## What narrows the list of packages (`nch packages -L N -U NAME -B NAME -T TABLE`): each given is one more test.
  layer*: Option[int] ## on this layer
  uses*: Option[string] ## that use this package (it is in their `depends`)
  usedBy*: Option[string] ## that this package uses (they are in its `depends`)
  table*: Option[string] ## that own this table or may read it

func keeps*(inv: Inventory, f: PackageFilter, p: PackageInfo): bool =
  ## Whether the package passes every test of the filter.  The names are those of a package and a table (checked before).
  if f.layer.isSome and p.layer != f.layer.get:
    return false
  if f.uses.isSome and f.uses.get.normalised notin p.depends.mapIt(it.normalised):
    return false
  if f.usedBy.isSome:
    let at = inv.find(f.usedBy.get)
    if at < 0 or p.name.normalised notin inv.packages[at].depends.mapIt(it.normalised):
      return false
  if f.table.isSome:
    var ok = false
    for t in inv.tables:
      if t.name == f.table.get:
        ok =
          t.owner.normalised == p.name.normalised or t.everyone or
          p.name.normalised in t.readers.mapIt(it.normalised)
    if not ok:
      return false
  true

const packageStyle* = "pkg"
  ## the style of the name of a package (of the theme), in the views of the packages

func pkg(name: string): Cell =
  ## The name of a package, in its style.
  @[(name, packageStyle)]

func pkgList(names: seq[string], between = " "): Cell =
  ## Names of packages, each in its style; "-" for none.
  if names.len == 0:
    return plainCell("-")
  for k, n in names:
    if k > 0:
      result.add (between, "")
    result.add (n, packageStyle)

func summaryLines*(inv: Inventory, width: int, filter = PackageFilter()): seq[Cell] =
  ## One line for each package, the lowest layer first and, in a layer, the most used first: its layer, how many packages
  ## it uses and is used by, how many tables it owns (in narrow columns headed by a letter, explained under the table), and
  ## what it is for, then what it provides (commands, in `theme.typedStyle`; points it defines; points it adds to).  Only those
  ## the filter keeps.  As styled pieces (`ruled.Cell`).
  var order = inv.packages.filterIt(inv.keeps(filter, it))
  order.sort(
    proc(a, b: PackageInfo): int =
      result = cmp(a.layer, b.layer)
      if result == 0:
        result = cmp(b.dependents.len, a.dependents.len)
      if result == 0:
        result = cmp(a.name.normalised, b.name.normalised)
  )
  var rows: seq[seq[Cell]]
  for p in order:
    # what it provides follows what it is for: "Defines users and the point user/has.  Adds to web/pages.", the names of
    # commands in the style of commands
    var what: Cell = @[(p.summary, "")]
    var defines: seq[Cell]
    for c in p.commands:
      defines.add @[("nch " & c.name, typedStyle)] # (a command is never named alone)
    let points = p.defines.mapIt(it.name)
    if points.len > 0:
      defines.add plainCell(
        (if points.len == 1: "the point " else: "the points ") & points.join(", ")
      )
    if defines.len > 0:
      what.add ("  Defines ", "")
      for k, d in defines:
        if k > 0:
          what.add ((if k == defines.high: " and " else: ", "), "")
        what.add d
      what.add (".", "")
    if p.contributes.len > 0:
      what.add ("  Adds to " & p.contributes.mapIt(it.point).join(", ") & ".", "")
    rows.add @[
      pkg(p.name),
      plainCell($p.layer),
      plainCell($p.depends.len),
      plainCell($p.dependents.len),
      plainCell($p.tables.len),
      what,
    ]
  result = ruledCells(
    @["package", "L", "U", "B", "T", "what it is for"],
    rows,
    width,
    right = {1, 2, 3, 4},
    together = {1, 2, 3},
  )
  result.add plainCell("")
  for l in wrap(
    "L: the layer (0 depends on nothing; each package is one above the highest it uses); U: how many packages it uses " &
      "directly; B: how many use it directly; T: how many tables it owns.  Lowest layer first, the most used first in a layer.",
    width,
  ):
    result.add plainCell(l)

func withPackages(inv: Inventory, text: string): Cell =
  ## `text` with each name of a package between backticks (`map`) in the style of packages, without the backticks (what
  ## else is between backticks stays as it is: drawn as what is typed).
  var rest = text
  while rest.len > 0:
    let a = rest.find('`')
    let b =
      if a < 0:
        -1
      else:
        rest.find('`', a + 1)
    if a < 0 or b < 0:
      result.add (rest, "")
      break
    let inside = rest[a + 1 ..< b]
    if inv.find(inside) >= 0:
      result.add (rest[0 ..< a], "")
      result.add (inside, packageStyle)
    else:
      result.add (rest[0 .. b], "")
    rest = rest[b + 1 .. ^1]

func detailLines*(inv: Inventory, name: string, width: int): seq[Cell] =
  ## Everything about one package, as styled pieces: the title, the documentation, and the fields in two columns.  `name`
  ## must be that of a package.
  let at = inv.find(name)
  doAssert at >= 0
  let p = inv.packages[at]
  func field(label: string, value: Cell): seq[Cell] =
    ## a row of the fields: the label, a line (drawn in the line style), the value wrapped beside it
    for i, l in wrapCell(value, max(30, width - 17)):
      result.add @[
        ((if i == 0: label.alignLeft(13) else: " ".repeat(13)) & " │ ", "")
      ] & l
  result.add @[
    ("package ", "em"),
    (p.name, packageStyle),
    ("  ", ""),
    (fmt"layer {p.layer}", lineStyle),
  ]
  if p.doc.len > 0:
    result.add plainCell("")
    for l in rst(p.doc, width).split('\n'):
      result.add inv.withPackages(l)
    result.add plainCell("")
  result.add field("source", plainCell(p.path))
  result.add field("depends on", pkgList(p.depends))
  result.add field("used by", pkgList(p.dependents))
  result.add field("fragments", plainCell(listOf(p.fragments)))
  result.add field("tables", plainCell(listOf(p.tables)))
  var reads: Cell
  for t in inv.tables:
    if t.owner.normalised != p.name.normalised and (t.everyone or p.name in t.readers):
      if reads.len > 0:
        reads.add (" ", "")
      reads.add (t.name & " (", "")
      reads.add (t.owner, packageStyle)
      reads.add (")", "")
  result.add field("may also read", (if reads.len == 0: plainCell("-")
    else: reads))
  if p.commands.len == 0:
    result.add field("commands", plainCell("-"))
  for c in p.commands:
    result.add field(
      "command", @[("nch " & c.name, typedStyle), (" - " & c.summary, "")]
    )
  if p.defines.len == 0:
    result.add field("defines", plainCell("-"))
  for d in p.defines:
    var holds = ""
    var added: Cell # (who adds to it, in the order the contributions are used)
    for pt in inv.points:
      if pt.name == d.name:
        holds = pt.typeName
        for k, c in pt.contributors:
          if k > 0:
            added.add (", ", "")
          added.add (c.package, packageStyle)
          added.add (fmt" (priority {c.priority})", "")
    let what =
      if holds.len > 0:
        fmt"{d.name} (holds {holds})"
      else:
        d.name
    result.add field(
      "defines",
      @[(fmt"{what} - ", "")] & inv.withPackages(d.summary) & @[("; added to by ", "")] &
        (if added.len == 0: plainCell("nothing") else: added),
    )
  var adds: seq[string]
  for c in p.contributes:
    adds.add fmt"{c.point} (priority {c.priority})"
  result.add field("adds to", plainCell(listOf(adds)))

func pointLines*(inv: Inventory, width: int): seq[Cell] =
  ## Each extension point as a row: who defines it, who adds to it (in the order the contributions are used; a package that
  ## adds more than one is named once, "c ×2"), and what it is.  The type it holds and the priorities are in the detail of
  ## the package that defines it (`detailLines()`).
  var rows: seq[seq[Cell]]
  for pt in inv.points:
    var names: seq[string]
    var counts: seq[int]
    for c in pt.contributors:
      let at = names.find(c.package)
      if at < 0:
        names.add c.package
        counts.add 1
      else:
        inc counts[at]
    var added: Cell
    for k, n in names:
      if k > 0:
        added.add (", ", "")
      added.add (n, packageStyle)
      if counts[k] > 1:
        added.add (fmt" ×{counts[k]}", "")
    rows.add @[
      plainCell(pt.name),
      pkg(pt.owner),
      (if added.len == 0: plainCell("-") else: added),
      plainCell(pt.summary),
    ]
  ruledCells(
    @["point", "defined by", "added to by (in order)", "what it is"], rows, width
  )

func tableLines*(inv: Inventory, width: int): seq[Cell] =
  ## Each table, its owner and the packages that may read it.
  var rows: seq[seq[Cell]]
  for t in inv.tables:
    rows.add @[
      plainCell(t.name),
      pkg(t.owner),
      (if t.everyone: plainCell("every package") else: pkgList(t.readers)),
    ]
  ruledCells(@["table", "owner", "may read"], rows, width)

# --- the graphs --------------------------------------------------------------------------------------------------------

func neighbours(inv: Inventory, name: string, reverse: bool): seq[string] =
  let at = inv.find(name)
  if at < 0:
    return
  if reverse:
    inv.packages[at].dependents
  else:
    inv.packages[at].depends

type TreeLine* = object ## A line of a tree of packages.
  text*: string
  again*: bool ## the package was drawn above (drawn hidden: `nch packages`)

func treeLines*(
    inv: Inventory, root: string, reverse = false, repeats = true
): seq[TreeLine] =
  ## The tree of what `root` depends on (or, with `reverse`, of what depends on it), as far as it goes.  A package drawn above
  ## is not drawn again: it is marked `again`, and followed by "..." if something under it is left out (a package with
  ## nothing under it is just its name), so the tree stays short (`treeNote` says so); without `repeats` it is left out
  ## altogether.  Under each package those not drawn yet come first, the ones drawn above after them.
  type Node = tuple[depth: int, name: string, again, cut: bool]
  var nodes: seq[Node]
  var seen = initHashSet[string]()
  func walk(
      inv: Inventory,
      name: string,
      depth: int,
      seen: var HashSet[string],
      nodes: var seq[Node],
      reverse: bool,
  ) =
    let again = name.normalised in seen
    seen.incl name.normalised
    let kids = neighbours(inv, name, reverse)
    nodes.add (depth, name, again, again and kids.len > 0)
    if again:
      return
    let ordered =
      kids.filterIt(it.normalised notin seen) & kids.filterIt(it.normalised in seen)
    for k in ordered:
      walk(inv, k, depth + 1, seen, nodes, reverse)

  walk(inv, inv.packages[inv.find(root)].name, 0, seen, nodes, reverse)
  if not repeats:
    nodes = nodes.filterIt(not it.again)
  # the connectors, from what is drawn: a package is the last under its parent if no later one has its depth before one that
  # is less deep
  func later(nodes: seq[Node], i, depth: int): bool =
    for j in i + 1 .. nodes.high:
      if nodes[j].depth < depth:
        return false
      if nodes[j].depth == depth:
        return true
    false

  var open: seq[bool]
    # for each depth: whether the package drawn there has a later sibling (a line goes on down)
  for i, n in nodes:
    if n.depth == 0:
      result.add TreeLine(text: n.name, again: n.again)
      open = @[false]
      continue
    let more = later(nodes, i, n.depth)
    var prefix = ""
    for d in 1 ..< n.depth:
      prefix.add(if open[d]: "│   " else: "    ")
    open.setLen(n.depth + 1)
    open[n.depth] = more
    result.add TreeLine(
      text:
        prefix & (if more: "├── " else: "└── ") & n.name &
        (if n.cut: "..." else: ""),
      again: n.again,
    )

const treeNote* = "(... after a package: what is under it is drawn in full above)"
  ## what a tree that left something out says under it

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

type LayerPiece* = tuple[text: string, implied: bool]
  ## a piece of a line of the layers: a dependency implied by another (drawn hidden: `nch packages --graph -v`), or not

func layerLines*(inv: Inventory, width: int, implied = false): seq[seq[LayerPiece]] =
  ## The packages by layer, the highest first, each with the packages it depends on directly and not through another
  ## dependency (and, with `implied`, those too, marked): the picture of how the program is built up.
  let reduced = reducedDepends(inv)
  var top = 0
  var nameWidth = 0
  for p in inv.packages:
    top = max(top, p.layer)
    nameWidth = max(nameWidth, p.name.len)
  let room = max(20, width - nameWidth - 8)
  for l in countdown(top, 0):
    let here = inv.packages.filterIt(it.layer == l).sortedByIt(it.name.normalised)
    if here.len == 0:
      continue
    result.add @[
      (fmt"layer {l}" & (if l == 0: "  (depend on nothing)" else: ""), false)
    ]
    for p in here:
      let kept = reduced.getOrDefault(p.name.normalised)
      var deps: seq[LayerPiece]
      for d in kept:
        deps.add (d, false)
      if implied:
        for d in p.depends:
          if kept.allIt(it.normalised != d.normalised):
            deps.add (d, true)
      if deps.len == 0:
        result.add @[("  " & p.name, false)]
        continue
      # the names, wrapped to the room after the arrow; each keeps its mark
      var line: seq[LayerPiece] =
        @[("  " & p.name.alignLeft(nameWidth) & "  ← ", false)]
      var used = 0
      for (d, imp) in deps:
        if used > 0 and used + 1 + d.len > room:
          result.add line
          line = @[(" ".repeat(nameWidth + 7), false)]
          used = 0
        if used > 0:
          line.add (" ", false)
          used += 1
        line.add (d, imp)
        used += d.len
      result.add line

func dotText*(inv: Inventory): string =
  ## The dependencies as a Graphviz graph (`nch packages --dot | dot -Tsvg > packages.svg`): an arrow from a package
  ## to each it depends on directly (the implied ones are left out, as in the layers), the packages of a layer on one
  ## rank.
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
