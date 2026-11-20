## `nch packages`: the program describing itself: its packages, their dependencies, tables, commands and extension points.
## It is built into `nch` and not a package, because it needs the whole registry (which a package cannot import).  What
## the views are made of is `core/inventory.nim`; here are the command line and the printing.

import std/[algorithm, editdistance, options, sequtils, strformat, strutils]
import ./core/[errors, globals, inventory, manifest]
import ./packages/ui/[live, style]
import ./packages/util/args/[args, usage]
import ./registry as generated

{.push raises: [].}

type
  View* = enum
    vList
    vDetail
    vPoints
    vTree

  Params* = object ## what `nch packages` is asked to show
    case view*: View
    of vDetail:
      package*: string
    of vTree:
      root*: string
      reverse*: bool ## what depends on `root`, not what it depends on
    of vList:
      filter*: PackageFilter ## `-U`, `-B`, `-T`: which packages
    of vPoints:
      discard

  Raw = object ## what the options fill in
    help, points, graph, reverse: bool
    name: string
    filter: PackageFilter

proc inventory(): Inventory =
  try:
    inventoryOf(
      generated.packages, generated.extensions, generated.points, generated.schema
    )
  except PackageError as e:
    raiseAssert e.msg # (the registry has already been checked when it was compiled)

proc completePackages(g: Globals, typed: string): seq[string] {.nimcall, raises: [].} =
  ## The names of the packages that start with what is typed.
  for p in inventory().packages:
    if p.name.startsWith(typed):
      result.add p.name

proc completeTables(g: Globals, typed: string): seq[string] {.nimcall, raises: [].} =
  ## The names of the tables that start with what is typed.
  for t in inventory().tables:
    if t.name.startsWith(typed):
      result.add t.name

func packagesSpec*(): Spec[Raw] =
  ## The options of `nch packages`, each with its help.
  Spec[Raw](
    opts: @[
      custom(
        Raw,
        ["-U"],
        true,
        "NAME",
        ~"only the packages that use package NAME (one of those counted by U in their U/B)",
        completion = completesFrom(completePackages),
        body = (p.filter.uses = some(value); fine),
      ),
      custom(
        Raw,
        ["-B"],
        true,
        "NAME",
        ~"only the packages that package NAME uses (one of those counted by B in their U/B)",
        completion = completesFrom(completePackages),
        body = (p.filter.usedBy = some(value); fine),
      ),
      custom(
        Raw,
        ["-T"],
        true,
        "TABLE",
        ~"only the packages that own TABLE or may read it (`-U`, `-B` and `-T` go together, each narrowing the list further)",
        completion = completesFrom(completeTables),
        body = (p.filter.table = some(value); fine),
      ),
      flag(
        Raw,
        ["--points"],
        points,
        ~"the extension points: who defines each, and who contributes to it, in the order the contributions are used",
      ),
      flag(
        Raw,
        ["--graph"],
        graph,
        ~"the tree of what package NAME depends on, breadth first: what it uses itself, then what those add, and so on",
      ),
      flag(
        Raw,
        ["--reverse"],
        reverse,
        ~"(with `--graph NAME`) the tree of what depends on NAME instead",
        level = 1,
      ),
      helpFlag(Raw),
    ],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      if p.name.len > 0:
        return refuse(~"only one package can be asked about")
      p.name = arg
      fine,
  )

func finish(raw: Raw): Parsed[Params] =
  let chosen = [raw.points, raw.graph]
  if chosen.countIt(it) > 1:
    return problemWith[Params](~"choose one of `--points` and `--graph`")
  if raw.name.len > 0 and raw.points:
    return problemWith[Params](~"a package name goes with nothing but `--graph`")
  if raw.reverse and not (raw.graph and raw.name.len > 0):
    return problemWith[Params](~"`--reverse` goes with `--graph` and a package name")
  if raw.graph and raw.name.len == 0:
    return problemWith[Params](~"`--graph` draws the tree of a package: give its name")
  let filtered =
    raw.filter.uses.isSome or raw.filter.usedBy.isSome or raw.filter.table.isSome
  if filtered and (chosen.anyIt(it) or raw.name.len > 0):
    return problemWith[Params](
      ~"`-U`, `-B` and `-T` narrow the list of packages: they go with no package name and no other view"
    )
  if raw.points:
    parsedOk(Params(view: vPoints))
  elif raw.graph:
    parsedOk(Params(view: vTree, root: raw.name, reverse: raw.reverse))
  elif raw.name.len > 0:
    parsedOk(Params(view: vDetail, package: raw.name))
  else:
    parsedOk(Params(view: vList, filter: raw.filter))

func closeNames*(asked: string, names: seq[string]): seq[string] =
  ## The names that `asked` may be a misspelling of: those within two edits of it (ignoring case), or that hold it, the
  ## closest first.
  let a = asked.toLowerAscii
  var scored: seq[(int, string)]
  for n in names:
    let d = editDistanceAscii(a, n.toLowerAscii)
    if d <= 2 or (a.len >= 3 and a in n.toLowerAscii):
      scored.add (d, n)
  scored.sort()
  scored.mapIt(it[1])

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch packages [NAME] [--points | --graph [--reverse]]`.
  parseCommand(args, packagesSpec(), Raw(), finish)

const
  synopsis = """usage: nch packages [-U NAME] [-B NAME] [-T TABLE]
       nch packages NAME
       nch packages --points
       nch packages NAME --graph [--reverse]"""
  intro = @[
    ~"The program describing itself: its packages in dependency order, each with what it is for, its layer (0 for a package that depends on nothing), how many packages it uses and is used by, how many tables it owns, and what it provides: commands, the extension points it defines, and those it contributes to.  With the name of a package, its documentation and everything else about it."
  ]

proc usageText*(width: int): seq[Line] =
  usageOf(synopsis, width, intro, packagesSpec().docs)

# --- the settings ------------------------------------------------------------------------------------------------------

# --- the command -------------------------------------------------------------------------------------------------------

func namedInTree(text: string): Line =
  ## A line of a tree ("├── activities", "│   └── climbs"): the name of the package in its style.
  var start = 0
  for k, c in text:
    if c in Letters:
      start = k
      break
  @[span(text[0 ..< start]), span(text[start .. ^1], styleName"code")]

proc packagesMain*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch packages ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError(g, "nch packages", usageText(helpWidth(stderr)), parsed.why)
  of pkOk:
    discard
  let p = parsed.params
  let inv = inventory()
  let width = helpWidth(stdout)
  let asked =
    case p.view
    of vDetail: p.package
    of vTree: p.root
    else: ""
  if p.view in {vDetail, vTree} and inv.find(asked) < 0:
    let close = closeNames(asked, inv.packages.mapIt(it.name))
    if close.len > 0:
      return failure(
        g,
        "nch packages",
        ~"no package is called '{asked}': did you mean {close.join(\" or \")}?",
      )
    return failure(
      g,
      "nch packages",
      ~"no package is called '{asked}' (they are: {inv.packages.mapIt(it.name).sorted.join(\" \")})",
    )
  case p.view
  of vList:
    let f = p.filter
    for (option, name) in [("-U", f.uses), ("-B", f.usedBy)]:
      if name.isSome and inv.find(name.get) < 0:
        let close = closeNames(name.get, inv.packages.mapIt(it.name))
        let hint =
          if close.len > 0:
            fmt": did you mean {close.join("" or "")}?"
          else:
            ""
        return failure(
          g, "nch packages", ~"{option}: no package is called '{name.get}'{hint}"
        )
    if f.table.isSome and inv.tables.allIt(it.name != f.table.get):
      let close = closeNames(f.table.get, inv.tables.mapIt(it.name))
      let hint =
        if close.len > 0:
          fmt": did you mean {close.join("" or "")}?"
        else:
          ""
      return
        failure(g, "nch packages", ~"`-T`: no table is called '{f.table.get}'{hint}")
    if inv.packages.allIt(not inv.keeps(f, it)):
      g.show(osOut, ~"no package is kept by those filters")
    else:
      g.showAll(osOut, summaryLines(inv, width, f))
  of vDetail:
    g.showAll(osOut, detailLines(inv, p.package, width))
  of vPoints:
    g.showAll(osOut, pointLines(inv, width))
  of vTree:
    for l in treeLines(inv, p.root, p.reverse):
      g.show(osOut, namedInTree(l))
  exitOk

proc packagesOptions(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch packages`, described (for tab completion).
  packagesSpec().docs

const packagesCommand* = CommandDecl(
  name: "packages",
  summary: "the packages: what each is for, their dependencies and extension points",
  run: packagesMain,
  options: packagesOptions,
)
