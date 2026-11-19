## `nch packages`: the program describing itself: its packages, their dependencies, tables, commands and extension points,
## and the settings in force.  It is built into `nch` and not a package, because it needs the whole registry (which a
## package cannot import).  What the views are made of is `core/inventory.nim`; here are the command line, the facts about
## the running program (`--config`) and the printing.

import std/[algorithm, editdistance, options, os, sequtils, strformat, strutils]
import ./core/[access, errors, globals, inventory, logfile, manifest, ruled]
import ./packages/cache/cache
import ./packages/db/[fragment, store]
import ./packages/ui/[live, style, units]
import ./packages/util/args/[args, usage]
import ./packages/util/version/version
import ./registry as generated

{.push raises: [].}

type
  View* = enum
    vList
    vDetail
    vPoints
    vTables
    vLayers
    vTree
    vDot
    vConfig

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
    of vPoints, vTables, vDot, vConfig:
      discard

  Raw = object ## what the options fill in
    help, points, tables, graph, reverse, verbose, dot, config: bool
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
        ["--tables"],
        tables,
        "the tables: who owns each, and which packages may read it",
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
        "(with `--graph`) everything, the rest dimmed: with NAME the packages already drawn higher in the tree (else each is drawn once); without, the dependencies implied by others (else only those that are not)",
        level = 1,
      ),
      flag(
        Raw,
        ["--dot"],
        dot,
        "the dependencies as a Graphviz graph: `nch packages --dot | dot -Tsvg > packages.svg`",
      ),
      flag(
        Raw,
        ["--config"],
        config,
        "the settings in force: the database, the user, the log, the cache, the version, the environment, and whether the database was made by this version",
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
  let chosen = [raw.points, raw.tables, raw.graph, raw.dot, raw.config]
  if chosen.countIt(it) > 1:
    return problemWith[Params](
      "choose one of `--points`, `--tables`, `--graph`, `--dot` and `--config`"
    )
  if raw.name.len > 0 and (raw.points or raw.tables or raw.dot or raw.config):
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
  elif raw.tables:
    parsedOk(Params(view: vTables))
  elif raw.dot:
    parsedOk(Params(view: vDot))
  elif raw.config:
    parsedOk(Params(view: vConfig))
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
  ## `nch packages [NAME] [--points | --tables | --graph [--reverse] | --dot | --config]`.
  parseCommand(args, packagesSpec(), Raw(), finish)

const
  synopsis = """usage: nch packages [-L N] [-U NAME] [-B NAME] [-T TABLE]
       nch packages NAME
       nch packages --points | --tables | --dot | --config
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

proc setIn(name: string): string =
  ## "NAME=value" for a variable of the environment that is set, "NAME (not set)" if not.
  let v = getEnv(name)
  if v.len > 0:
    fmt"{name}={v}"
  else:
    fmt"{name} (not set)"

proc fragmentLines*(path: string): seq[string] =
  ## What the database file has had applied, against what this program has.
  let program = generated.schema
  if not fileExists(path):
    return
      @[fmt"fragments: the program has {program.len}; there is no database file yet"]
  var have: seq[(string, string)]
  try:
    have = appliedFragments(path)
  except StoreError as e:
    return @[fmt"fragments: the program has {program.len}; the database: {e.msg}"]
  result.add fmt"fragments: the program has {program.len}; the database has had {have.len}"
  var differences: seq[string]
  for (name, sum) in have:
    let known = program.filterIt(it.name == name)
    if known.len == 0:
      differences.add fmt"  {name}: only in the database (from a newer version: it will be refused)"
    elif known[0].checksum != sum:
      differences.add fmt"  {name}: not the SQL this version has (made by a different version: it will be refused)"
  for f in program:
    if have.allIt(it[0] != f.name):
      differences.add fmt"  {f.name}: not applied yet (it will be, when the database is opened)"
  if differences.len == 0:
    result.add "  all of them match"
  result.add differences

proc configLines*(g: Globals, width: int): seq[Line] =
  ## The settings in force, and where each came from (a path in `file`), as a table without headings; then the fragments.
  var rows: seq[seq[Line]]
  func row(label: string, value: Line): seq[Line] =
    @[plain(label), value]

  func row(label, value: string): seq[Line] =
    row(label, plain(value))

  func pathOr(path: Option[string], otherwise: string): Line =
    if path.isSome:
      @[span(path.get, "file")]
    else:
      plain(otherwise)
  rows.add row("version", versionString)
  let path = resolveDbPath(g.dbPath)
  let source =
    if g.dbPath.len > 0:
      "--db"
    elif getEnv("NCH_DB").len > 0:
      "$NCH_DB"
    else:
      "the default"
  var state = "not made yet"
  try:
    if fileExists(path):
      state = humanBytes(getFileSize(path))
  except OSError:
    state = "cannot be read"
  rows.add row("database", @[span(path, "file"), span(fmt"  ({source}; {state})")])
  rows.add row(
    "user",
    if g.user.len > 0:
      fmt"{g.user}  (`--user`)"
    else:
      "the default user of the database",
  )
  rows.add row("offline", if g.offline: "yes (`--offline`)" else: "no")
  rows.add row(
    "theme",
    if g.theme.name.len > 0:
      fmt"{g.theme.name}  ({g.theme.origin})"
    else:
      "none: the terminal's own text",
  )
  let log = envLogPath()
  rows.add row("log", pathOr(log, "off (NCH_LOG is empty)"))
  let cache = cacheDir()
  rows.add row("cache", pathOr(cache, "none (no HOME)"))
  rows.add row(
    "access",
    case g.access.mode
    of amEnforce: "enforced: a package that touches the table of another is refused"
    of amOff: "off"
    ,
  )
  rows.add row("commands", generated.commands.mapIt(it.name).join(" ") & " packages")
  let variables = [
    "NCH_DB", "NCH_LOG", "NCH_CACHE", "XDG_STATE_HOME", "XDG_CACHE_HOME",
    "XDG_DATA_HOME", "NO_COLOR", "NCH_THEME", "COLORFGBG",
  ].mapIt(setIn(it))
  for i, v in variables:
    rows.add row((if i == 0: "environment" else: ""), v)
  result = ruled(@["", ""], rows, width)
  result.add plain("")
  for l in fragmentLines(path):
    result.add plain(l)

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
  of vTables:
    g.showAll tableLines(inv, width)
  of vLayers:
    let paint = paintOf(g, osOut)
    for l in layerLines(inv, width, p.implied):
      # (a dependency implied by another is hidden)
      g.sayRendered osOut,
        render(
          l.mapIt(
            if it.implied:
              span(it.text, "hide")
            elif inv.find(it.text.strip) >= 0:
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
      # (what was drawn above is hidden)
      g.sayRendered osOut,
        render(
          (
            if l.again:
              @[span(l.text, "hide")]
            else:
              namedInTree(l.text)
          ),
          paint,
        ) & "\n"
    if tree.anyIt(it.text.endsWith("...")):
      g.showAll(@["", treeNote])
  of vDot:
    g.say osOut, dotText(inv)
  of vConfig:
    g.showAll configLines(g, helpWidth(stdout))
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
