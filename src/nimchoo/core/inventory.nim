## What the packages are, as a program can tell about itself: who depends on whom, which tables each owns and may read,
## which commands it provides, which extension points it defines and what each contributes.  Made from the registry
## (`inventoryOf`), then drawn as lists, trees, layers or a Graphviz graph for `nch packages`.  Pure: no database, no
## terminal, so every view is tested with made-up packages.

import std/[algorithm, options, sequtils, sets, strformat, strutils, tables]
import
  ./[access, errors, extension, fragment, manifest, line, names, ownership, ruled, wrap]

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
  var declared: Table[string, seq[string]]
  for p in packages:
    declared[p.name] = p.package.depends
  let access = newAccess(amEnforce, owners, declared)
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
      # (who may read it is the access model's to say: the one rule, which `nch db` shows too)
      let readers = access.readersOf(t)
      for p in packages:
        if p.name.normalised in readers:
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
    items.join(", ")

func countOf(items: seq[string]): string =
  $items.len

type PackageFilter* = object
  ## What narrows the list of packages (`nch packages -U NAME -B NAME -T TABLE`): each given is one more test.
  uses*: Option[string] ## that use this package (it is in their `depends`)
  usedBy*: Option[string] ## that this package uses (they are in its `depends`)
  table*: Option[string] ## that own this table or may read it

func keeps*(inv: Inventory, f: PackageFilter, p: PackageInfo): bool =
  ## Whether the package passes every test of the filter.  The names are those of a package and a table (checked before).
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

func pkg(name: string): Line =
  ## The name of a package, in its style.
  @[span(name, "code")]

func pkgList(names: seq[string], between = ", "): Line =
  ## Names of packages, each in its style; "-" for none.
  if names.len == 0:
    return plain("-")
  for k, n in names:
    if k > 0:
      result.add span(between)
    result.add span(n, "code")

func counted(items: seq[tuple[name: string, priority: int]]): seq[string] =
  ## Each name once, in the order first given, with how many times it is there ("map/frames ×2") and its priorities when
  ## any is not 0 (the order of the contributions: `core/extension.nim`); each kept on one line when wrapped.
  var names: seq[string]
  var priorities: seq[seq[int]]
  for it in items:
    let at = names.find(it.name)
    if at < 0:
      names.add it.name
      priorities.add @[it.priority]
    else:
      priorities[at].add it.priority
  for k, n in names:
    var text = n
    if priorities[k].len > 1:
      text.add fmt" ×{priorities[k].len}"
    if priorities[k].anyIt(it != 0):
      text.add " (priority " & priorities[k].mapIt($it).join(", ") & ")"
    result.add unbroken(text)

func namedList(items: seq[string], style: StyleName, between = ", "): Line =
  ## Items of `counted()` (or plain names), the name of each in `style` and what follows it ("×2", the priorities) not.
  for k, it in items:
    if k > 0:
      result.add span(between)
    let name = it.split(noBreak)[0]
    result.add span(name, style)
    if name.len < it.len:
      result.add span(it[name.len .. ^1])

type DocState = object
  ## Where a line of documentation starts: inside `**` or backticks (a phrase can be wrapped over lines).
  strong, code: bool

func docLine(text: string, state: var DocState): Line =
  ## A line of documentation (RST): what is between backticks (`map`, `nch climbs`) as literal text (`code`, without the
  ## backticks: they are the mark only without colour), and what is between `**` in `em`, without them.  `state` says
  ## where the line starts, and is left saying where it ends.
  var plainText = ""
  template flush() =
    if plainText.len > 0:
      var styles: seq[string]
      if state.strong:
        styles.add "em"
      if state.code:
        styles.add "code"
      result.add Span(text: plainText, styles: styles.mapIt(anyStyle(it)))
      plainText = ""

  var i = 0
  while i < text.len:
    if not state.code and text.continuesWith("**", i):
      flush()
      state.strong = not state.strong
      i += 2
    elif text[i] == '`':
      flush()
      state.code = not state.code
      inc i
    else:
      plainText.add text[i]
      inc i
  flush()

func summaryLines*(inv: Inventory, width: int, filter = PackageFilter()): seq[Line] =
  ## One line for each package, those that use fewest first and, of those, the most used first (the more fundamental
  ## first): how many packages it uses and is used by (`U/B`, explained under the table), and what it is for, then what it provides (commands, in `code`; the extension points it defines; those it contributes to).  Only those
  ## the filter keeps.  As styled lines.
  var order = inv.packages.filterIt(inv.keeps(filter, it))
  order.sort(
    proc(a, b: PackageInfo): int =
      result = cmp(a.depends.len, b.depends.len)
      if result == 0:
        result = cmp(b.dependents.len, a.dependents.len)
      if result == 0:
        result = cmp(a.name.normalised, b.name.normalised)
  )
  var rows: seq[seq[Line]]
  for p in order:
    # what it provides follows what it is for: "Defines users and the extension point user/has.  Contributes to web/pages.", the names of
    # commands in the style of commands
    var state: DocState
    var what: Line = docLine(p.summary, state)
    var defines: seq[Line]
    for c in p.commands:
      defines.add @[span("nch " & c.name, "code")] # (a command is never named alone)
    let points = p.defines.mapIt(it.name)
    if points.len > 0:
      defines.add @[
        span(if points.len == 1: "the extension point " else: "the extension points ")
      ] & namedList(points, styleName"code")
    if defines.len > 0:
      what.add span("  Defines ")
      for k, d in defines:
        if k > 0:
          what.add span((if k == defines.high: " and " else: ", "))
        what.add d
      what.add span(".")
    if p.contributes.len > 0:
      let adds = counted(p.contributes.mapIt((it.point, it.priority)))
      what.add span("  Contributes to ")
      what.add namedList(adds, styleName"code")
      what.add span(".")
    rows.add @[pkg(p.name), plain(fmt"{p.depends.len}/{p.dependents.len}"), what]
  result = ruled(@["package", "U/B", "what it is for"], rows, width, right = {1})
  result.add plain("")
  for l in wrap("U/B: how many packages the package uses / is used by.", width):
    result.add plain(l)

func detailLines*(inv: Inventory, name: string, width: int): seq[Line] =
  ## Everything about one package, as styled lines: the title, the documentation, and the fields in two columns (what each
  ## is, wrapped narrow, and what it holds).  `name` must be that of a package.
  let at = inv.find(name)
  doAssert at >= 0
  let p = inv.packages[at]
  var fields: seq[seq[Line]] # (label, value: a table without headings)
  func field(label: string, value: Line): seq[Line] =
    @[plain(label), value]
  result.add @[
    span("package ", "em"),
    span(p.name, "code"),
    span("  "),
    span(fmt"layer {p.layer}", "hide"),
  ]
  if p.doc.len > 0:
    result.add plain("")
    var state: DocState
    for l in rst(p.doc, width).split('\n'):
      result.add docLine(l, state)
    result.add plain("")
  fields.add field("source", @[span(p.path, "file")])
  fields.add field("depends on", pkgList(p.depends))
  fields.add field("used by", pkgList(p.dependents))
  fields.add field("fragments", plain(listOf(p.fragments)))
  fields.add field(
    "own tables",
    (if p.tables.len == 0: plain("-")
    else: namedList(p.tables, styleName"code")),
  )
  var owners: seq[string]
    # (the tables of others it may read, by their owner, in the order of the tables)
  var byOwner: seq[seq[string]]
  for t in inv.tables:
    if t.owner.normalised != p.name.normalised and (t.everyone or p.name in t.readers):
      let k = owners.find(t.owner)
      if k < 0:
        owners.add t.owner
        byOwner.add @[t.name]
      else:
        byOwner[k].add t.name
  var reads: Line
  for k, o in owners:
    if k > 0:
      reads.add span("; ")
    reads.add span(o, "code")
    reads.add span(": ")
    reads.add namedList(byOwner[k], styleName"code")
  fields.add field(
    "access to external tables", (if reads.len == 0: plain("-") else: reads)
  )
  if p.commands.len == 0:
    fields.add field("commands", plain("-"))
  for c in p.commands:
    fields.add field(
      "command", @[span("nch " & c.name, "code"), span(" - " & c.summary)]
    )
  if p.defines.len == 0:
    fields.add field("defines extension points", plain("-"))
  for d in p.defines:
    var holds = ""
    var added: seq[tuple[name: string, priority: int]]
      # (who contributes to it, in the order the contributions are used)
    for pt in inv.points:
      if pt.name == d.name:
        holds = pt.typeName
        for c in pt.contributors:
          added.add (c.package, c.priority)
    var by: Line
    for k, c in counted(added):
      if k > 0:
        by.add span(", ")
      let n = c.split(noBreak)[0]
      by.add span(n, "code")
      by.add span(c[n.len .. ^1])
    let what = (if holds.len > 0: fmt"{d.name}[{holds}]" else: d.name)
    var state: DocState
    fields.add field(
      "defines extension points",
      @[span(unbroken(what), "code"), span(" - ")] & docLine(d.summary, state) &
        @[span("; contributed to by ")] & (if by.len == 0: plain("nothing")
      else: by),
    )
  let adds = counted(p.contributes.mapIt((it.point, it.priority)))
  fields.add field(
    "contributes to extension points",
    (if adds.len == 0: plain("-") else: namedList(adds, styleName"code")),
  )
  result.add ruled(@["", ""], fields, width, narrow = 20)

func pointLines*(inv: Inventory, width: int): seq[Line] =
  ## Each extension point as a row: who defines it, who contributes to it (in the order the contributions are used; a package that
  ## adds more than one is named once, "c ×2"), and what it is.  The type it holds and the priorities are in the detail of
  ## the package that defines it (`detailLines()`).
  var rows: seq[seq[Line]]
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
    var added: Line
    for k, n in names:
      if k > 0:
        added.add span(", ")
      added.add span(n, "code")
      if counts[k] > 1:
        added.add span(fmt" ×{counts[k]}")
    rows.add @[
      @[span(pt.name, "code")],
      pkg(pt.owner),
      (if added.len == 0: plain("-") else: added),
      (
        block:
          var state: DocState
          docLine(pt.summary, state)
      ),
    ]
  ruled(
    @["extension point", "defined by", "contributed to by (in order)", "what it is"],
    rows,
    width,
  )

func neighbours(inv: Inventory, name: string, reverse: bool): seq[string] =
  let at = inv.find(name)
  if at < 0:
    return
  if reverse:
    inv.packages[at].dependents
  else:
    inv.packages[at].depends

func treeLines*(inv: Inventory, root: string, reverse = false): seq[string] =
  ## The tree of what `root` depends on (or, with `reverse`, of what depends on it), as far as it goes, breadth first:
  ## each package is drawn once, at the shallowest place it is needed (the first a breadth-first walk from `root` meets
  ## it), so what `root` uses itself is all directly under it, what those use that is not already there under them, and
  ## so on.
  let start = inv.packages[inv.find(root)].name
  var home: Table[string, string] # package -> the package it is drawn under
  var met = toHashSet([start.normalised])
  var queue = @[start]
  var at = 0
  while at < queue.len:
    let u = queue[at]
    inc at
    for k in neighbours(inv, u, reverse):
      if k.normalised notin met:
        met.incl k.normalised
        home[k.normalised] = u.normalised
        queue.add k

  type Node = tuple[depth: int, name: string]
  var nodes: seq[Node]
  func draw(
      inv: Inventory,
      name: string,
      depth: int,
      home: Table[string, string],
      nodes: var seq[Node],
      reverse: bool,
  ) =
    nodes.add (depth, name)
    for k in neighbours(inv, name, reverse):
      if home.getOrDefault(k.normalised) == name.normalised:
        draw(inv, k, depth + 1, home, nodes, reverse)

  draw(inv, start, 0, home, nodes, reverse)
  # the connectors: a package is the last under its parent if no later one has its depth before one that is less deep
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
      result.add n.name
      open = @[false]
      continue
    let more = later(nodes, i, n.depth)
    var prefix = ""
    for d in 1 ..< n.depth:
      prefix.add(if open[d]: "│   " else: "    ")
    open.setLen(n.depth + 1)
    open[n.depth] = more
    result.add prefix & (if more: "├── " else: "└── ") & n.name
