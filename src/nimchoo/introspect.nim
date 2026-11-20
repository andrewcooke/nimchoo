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
    vLayers
    vTree
    vDot

  Params* = object ## what `nch packages` is asked to show
    case view*: View
    of vDetail:
      package*: string
    of vTree:
      root*: string
      reverse*: bool ## what depends on `root`, not what it depends on
      repeats*: bool ## `-v`: the packages drawn above too, hidden
    of vLayers:
      implied*: bool ## `-v`: the dependencies implied by others too, hidden
    of vList:
      filter*: PackageFilter ## `-L`, `-U`, `-B`, `-T`: which packages
    of vPoints, vDot:
      discard

  Raw = object ## what the options fill in
    help, points, graph, reverse, verbose, dot: bool
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
        ["-L"],
        true,
        "N",
        "only the packages on layer N (the column L)",
        body = (
          block:
            var n = 0
            if not parseIntIn(value, 0, 1000, n):
              return refuse(fmt"`-L` is a layer, a number from 0 (not '{value}')")
            p.filter.layer = some(n)
            fine
        ),
      ),
      custom(
        Raw,
        ["-U"],
        true,
        "NAME",
        "only the packages that use package NAME (it is one of those counted in their column U)",
        completion = completesFrom(completePackages),
        body = (p.filter.uses = some(value); fine),
      ),
      custom(
        Raw,
        ["-B"],
        true,
        "NAME",
        "only the packages that package NAME uses (it is one of those counted in their column B)",
        completion = completesFrom(completePackages),
        body = (p.filter.usedBy = some(value); fine),
      ),
      custom(
        Raw,
        ["-T"],
        true,
        "TABLE",
        "only the packages that own TABLE or may read it (`-L`, `-U`, `-B` and `-T` go together, each narrowing the list further)",
        completion = completesFrom(completeTables),
        body = (p.filter.table = some(value); fine),
      ),
      flag(
        Raw,
        ["--points"],
        points,
        "the extension points: who defines each, and who contributes to it, in the order the contributions are used",
      ),
      flag(
        Raw,
        ["--graph"],
        graph,
        "the dependencies as a picture: with NAME, the tree of what that package depends on; without, all the packages by layer",
      ),
      flag(
        Raw,
        ["--reverse"],
        reverse,
        "(with `--graph NAME`) the tree of what depends on NAME instead",
        level = 1,
      ),
      flag(
        Raw,
        ["-v", "--verbose"],
        verbose,
        "(with `--graph`) everything: with NAME each package again wherever it is needed, besides where it is drawn in full (else once, at the shallowest place); without, the dependencies implied by others too, dimmed (else only those that are not)",
        level = 1,
      ),
      flag(
        Raw,
        ["--dot"],
        dot,
        "the dependencies as a Graphviz graph: `nch packages --dot | dot -Tsvg > packages.svg`",
      ),
      helpFlag(Raw),
    ],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      if p.name.len > 0:
        return refuse("only one package can be asked about")
      p.name = arg
      fine,
  )

func finish(raw: Raw): Parsed[Params] =
  let chosen = [raw.points, raw.graph, raw.dot]
  if chosen.countIt(it) > 1:
    return problemWith[Params]("choose one of `--points`, `--graph` and `--dot`")
  if raw.name.len > 0 and (raw.points or raw.dot):
    return problemWith[Params]("a package name goes with nothing but `--graph`")
  if raw.reverse and not (raw.graph and raw.name.len > 0):
    return problemWith[Params]("`--reverse` goes with `--graph` and a package name")
  if raw.verbose and not raw.graph:
    return problemWith[Params]("`-v` goes with `--graph`")
  let filtered =
    raw.filter.layer.isSome or raw.filter.uses.isSome or raw.filter.usedBy.isSome or
    raw.filter.table.isSome
  if filtered and (chosen.anyIt(it) or raw.name.len > 0):
    return problemWith[Params](
      "`-L`, `-U`, `-B` and `-T` narrow the list of packages: they go with no package name and no other view"
    )
  if raw.points:
    parsedOk(Params(view: vPoints))
  elif raw.dot:
    parsedOk(Params(view: vDot))
  elif raw.graph and raw.name.len > 0:
    parsedOk(
      Params(view: vTree, root: raw.name, reverse: raw.reverse, repeats: raw.verbose)
    )
  elif raw.graph:
    parsedOk(Params(view: vLayers, implied: raw.verbose))
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
  ## `nch packages [NAME] [--points | --graph [--reverse] | --dot]`.
  parseCommand(args, packagesSpec(), Raw(), finish)

const
  synopsis = """usage: nch packages [-L N] [-U NAME] [-B NAME] [-T TABLE]
       nch packages NAME
       nch packages --points | --dot
       nch packages --graph [--reverse] [-v] [NAME]"""
  intro =
    """The program describing itself: its packages in dependency order, each with what it is for, its layer (0 for a
package that depends on nothing), how many packages it uses and is used by, how many tables it owns, and what it
provides: commands, the extension points it defines, and those it contributes to.  With the name of a package, its documentation
and everything else about it."""

proc usageText*(width: int): seq[Line] =
  usageOf(
    synopsisLines(synopsis),
    proseLines(intro, width),
    optionLines(packagesSpec().docs, width),
  )

# --- the settings ------------------------------------------------------------------------------------------------------

# --- the command -------------------------------------------------------------------------------------------------------

func namedInTree(text: string): Line =
  ## A line of a tree ("├── activities", "│   └── climbs ..."): the name of the package in its style.
  var start = 0
  for k, c in text:
    if c in Letters:
      start = k
      break
  var finish = text.len
  if text.endsWith(" ..."):
    finish = text.len - 4
  @[span(text[0 ..< start]), span(text[start ..< finish], styleName"pkg")] &
    (if finish < text.len: @[span(text[finish .. ^1])] else: @[])

proc showAll(g: Globals, lines: seq[string]) =
  for l in lines:
    g.say osOut, l & "\n"

proc showAll(g: Globals, lines: seq[Line]) =
  for l in lines:
    g.show(osOut, l)

proc packagesMain*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch packages ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError(g, "nch packages", usageText(helpWidth(stderr)), parsed.problem)
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
        fmt"no package is called '{asked}': did you mean {close.join("" or "")}?",
      )
    return failure(
      g,
      "nch packages",
      fmt"no package is called '{asked}' (they are: {inv.packages.mapIt(it.name).sorted.join("" "")})",
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
          g, "nch packages", fmt"{option}: no package is called '{name.get}'{hint}"
        )
    if f.table.isSome and inv.tables.allIt(it.name != f.table.get):
      let close = closeNames(f.table.get, inv.tables.mapIt(it.name))
      let hint =
        if close.len > 0:
          fmt": did you mean {close.join("" or "")}?"
        else:
          ""
      return
        failure(g, "nch packages", fmt"`-T`: no table is called '{f.table.get}'{hint}")
    if inv.packages.allIt(not inv.keeps(f, it)):
      g.say osOut, "no package is kept by those filters\n"
    else:
      g.showAll summaryLines(inv, width, f)
  of vDetail:
    g.showAll detailLines(inv, p.package, width)
  of vPoints:
    g.showAll pointLines(inv, width)
  of vLayers:
    let paint = paintOf(g, osOut)
    for l in layerLines(inv, width, p.implied):
      # (a dependency implied by another is hidden)
      g.sayRendered osOut,
        render(
          l.mapIt(
            if it.implied:
              span(it.text, "hide")
            elif inv.find(it.text) >= 0:
              span(it.text, styleName"pkg") # (the name of a package)
            else:
              span(it.text)
          ),
          paint,
        ) & "\n"
    if p.implied:
      g.showAll(@["", "(dimmed: a dependency also reached through another one)"])
  of vTree:
    let tree = treeLines(inv, p.root, p.reverse, p.repeats)
    let paint = paintOf(g, osOut)
    for l in tree:
      g.show(osOut, namedInTree(l.text))
  of vDot:
    g.say osOut, dotText(inv)
  exitOk

proc packagesOptions(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch packages`, described (for tab completion).
  packagesSpec().docs

const packagesCommand* = CommandDecl(
  name: "packages",
  summary:
    "the packages, their dependencies, tables and extension points; the settings in force",
  run: packagesMain,
  options: packagesOptions,
)
