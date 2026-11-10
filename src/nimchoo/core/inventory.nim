## What the packages are, as a program can tell about itself: who depends on whom, which tables each owns and may read,
## which commands it provides, which extension points it defines and what each contributes.  Made from the registry
## (`inventoryOf`), then drawn as lists, trees, layers or a Graphviz graph for `nch packages`.  Pure: no database, no
## terminal, so every view is tested with made-up packages.

import std/[algorithm, sequtils, sets, strformat, strutils, tables]
import ./[access, errors, extension, fragment, manifest, names, ownership, wrap]

{.push raises: [].}

type
  Addition* = tuple[point: string, priority: int]

  PackageInfo* = object
    name*: string
    summary*, doc*: string
      ## what the package is for: its `##` documentation, and the first line of it
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

func summaryLines*(inv: Inventory, width: int): seq[string] =
  ## One line for each package, in dependency order: its layer, how many packages it uses and is used by, how many
  ## tables it owns, and what it is for; and under that, what it provides.
  var nameWidth = "package".len
  for p in inv.packages:
    nameWidth = max(nameWidth, p.name.len)
  let head = nameWidth + 2 + 5 + 2 + 4 + 2 + 7 + 2 + 6 + 2
    # (the columns before the text)
  result.add (
    "package".alignLeft(nameWidth) & "  layer  uses  used by  tables  what it is for"
  )
  for p in inv.packages:
    let what = wrap(p.summary, max(30, width - head))
    result.add (
      p.name.alignLeft(nameWidth) & "  " & align($p.layer, 5) & "  " &
      align($p.depends.len, 4) & "  " & align($p.dependents.len, 7) & "  " &
      align($p.tables.len, 6) & "  " & what[0]
    ).strip(leading = false)
    for l in what[1 ..^ 1]:
      result.add " ".repeat(head) & l
    var provides: seq[string]
    for c in p.commands:
      provides.add "command " & c.name
    for d in p.defines:
      provides.add "defines " & d.name
    for c in p.contributes:
      provides.add "adds to " & c.point
    if provides.len > 0:
      for l in wrap(provides.join(", "), max(30, width - head)):
        result.add " ".repeat(head) & l

func detailLines*(inv: Inventory, name: string, width: int): seq[string] =
  ## Everything about one package.  `name` must be that of a package.
  let at = inv.find(name)
  doAssert at >= 0
  let p = inv.packages[at]
  func field(label, text: string): seq[string] =
    let lines = wrap(text, max(30, width - 16))
    for i, l in lines:
      result.add (if i == 0: label.alignLeft(14) & "  " else: " ".repeat(16)) & l
  result.add fmt"package {p.name}  (layer {p.layer})"
  if p.doc.len > 0:
    result.add ""
    result.add rst(p.doc, width)
    result.add ""
  result.add field("depends on", listOf(p.depends))
  result.add field("used by", listOf(p.dependents))
  result.add field("fragments", listOf(p.fragments))
  result.add field("tables", listOf(p.tables))
  var reads: seq[string]
  for t in inv.tables:
    if t.owner.normalised != p.name.normalised and (t.everyone or p.name in t.readers):
      reads.add fmt"{t.name} ({t.owner})"
  result.add field("may also read", listOf(reads))
  if p.commands.len == 0:
    result.add field("commands", "-")
  for c in p.commands:
    result.add field("command", c.name & " - " & c.summary)
  if p.defines.len == 0:
    result.add field("defines", "-")
  for d in p.defines:
    var users: seq[string]
    for pt in inv.points:
      if pt.name == d.name:
        for c in pt.contributors:
          users.add c.package
    result.add field("defines", d.name & " - " & d.summary)
    result.add field("  added to by", listOf(users))
  var adds: seq[string]
  for c in p.contributes:
    adds.add fmt"{c.point} (priority {c.priority})"
  result.add field("adds to", listOf(adds))

func pointLines*(inv: Inventory, width: int): seq[string] =
  ## Each extension point: who defines it, what it holds, and who contributes, in the order the contributions are used.
  for pt in inv.points:
    if result.len > 0:
      result.add ""
    result.add fmt"{pt.name}   defined by {pt.owner}" &
      (if pt.typeName.len > 0: fmt"   holds {pt.typeName}" else: "")
    for l in wrap(pt.summary, max(30, width - 4)):
      result.add "    " & l
    if pt.contributors.len == 0:
      result.add "    (nothing is contributed)"
    for i, c in pt.contributors:
      result.add fmt"    {i + 1}. {c.package} (priority {c.priority})"

func tableLines*(inv: Inventory): seq[string] =
  ## Each table, its owner and the packages that may read it.
  var tw = "table".len
  var ow = "owner".len
  for t in inv.tables:
    tw = max(tw, t.name.len)
    ow = max(ow, t.owner.len)
  result.add "table".alignLeft(tw) & "  " & "owner".alignLeft(ow) & "  may read"
  for t in inv.tables:
    result.add (
      t.name.alignLeft(tw) & "  " & t.owner.alignLeft(ow) & "  " &
      (if t.everyone: "every package" else: listOf(t.readers))
    ).strip(leading = false)

# --- the graphs --------------------------------------------------------------------------------------------------------

func neighbours(inv: Inventory, name: string, reverse: bool): seq[string] =
  let at = inv.find(name)
  if at < 0:
    return
  if reverse:
    inv.packages[at].dependents
  else:
    inv.packages[at].depends

func treeLines*(inv: Inventory, root: string, reverse = false): seq[string] =
  ## The tree of what `root` depends on (or, with `reverse`, of what depends on it), as far as it goes.  A package that
  ## was drawn above is marked "(above)" and not drawn again, so the tree stays short.
  var seen = initHashSet[string]()
  func walk(
      inv: Inventory,
      name, prefix: string,
      last: bool,
      top: bool,
      seen: var HashSet[string],
      lines: var seq[string],
      reverse: bool,
  ) =
    let again = name.normalised in seen
    seen.incl name.normalised
    let branch =
      if top:
        ""
      elif last:
        "└── "
      else:
        "├── "
    lines.add prefix & branch & name & (if again: " (above)" else: "")
    if again:
      return
    let kids = neighbours(inv, name, reverse)
    let below =
      if top:
        ""
      elif last:
        prefix & "    "
      else:
        prefix & "│   "
    for i, k in kids:
      walk(inv, k, below, i == kids.high, false, seen, lines, reverse)
  walk(inv, inv.packages[inv.find(root)].name, "", true, true, seen, result, reverse)

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

func layerLines*(inv: Inventory, width: int): seq[string] =
  ## The packages by layer, the highest first, each with the packages it depends on directly (not those implied by
  ## another dependency): the picture of how the program is built up.
  let reduced = reducedDepends(inv)
  var top = 0
  var nameWidth = 0
  for p in inv.packages:
    top = max(top, p.layer)
    nameWidth = max(nameWidth, p.name.len)
  for l in countdown(top, 0):
    let here = inv.packages.filterIt(it.layer == l).sortedByIt(it.name.normalised)
    if here.len == 0:
      continue
    result.add fmt"layer {l}" & (if l == 0: "  (depend on nothing)" else: "")
    for p in here:
      let deps = reduced.getOrDefault(p.name.normalised)
      if deps.len == 0:
        result.add "  " & p.name
        continue
      let lines = wrap(deps.join(" "), max(20, width - nameWidth - 8))
      for i, line in lines:
        result.add (
          "  " & (
            if i == 0: p.name.alignLeft(nameWidth) & "  ← "
            else: " ".repeat(nameWidth + 5)
          ) & line
        )

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
