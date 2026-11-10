## `nch packages`: the program describing itself: its packages, their dependencies, tables, commands and extension points,
## and the settings in force.  It is built into `nch` and not a package, because it needs the whole registry (which a
## package cannot import).  What the views are made of is `core/inventory.nim`; here are the command line, the facts about
## the running program (`--config`) and the printing.

import std/[algorithm, options, os, sequtils, strformat, strutils]
import ./core/[access, errors, globals, inventory, logfile, manifest]
import ./packages/cache/cache
import ./packages/db/[fragment, store]
import ./packages/ui/[live, units]
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
    of vList, vPoints, vTables, vLayers, vDot, vConfig:
      discard

  Raw = object ## what the options fill in
    help, points, tables, graph, reverse, dot, config: bool
    name: string

func packagesSpec*(): Spec[Raw] =
  ## The options of `nch packages`, each with its help.
  Spec[Raw](
    opts: @[
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
        "(with --graph NAME) the tree of what depends on NAME instead",
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
      "choose one of --points, --tables, --graph, --dot and --config"
    )
  if raw.name.len > 0 and (raw.points or raw.tables or raw.dot or raw.config):
    return problemWith[Params]("a package name goes with nothing but --graph")
  if raw.reverse and not (raw.graph and raw.name.len > 0):
    return problemWith[Params]("--reverse goes with --graph and a package name")
  if raw.points:
    parsedOk(Params(view: vPoints))
  elif raw.tables:
    parsedOk(Params(view: vTables))
  elif raw.dot:
    parsedOk(Params(view: vDot))
  elif raw.config:
    parsedOk(Params(view: vConfig))
  elif raw.graph and raw.name.len > 0:
    parsedOk(Params(view: vTree, root: raw.name, reverse: raw.reverse))
  elif raw.graph:
    parsedOk(Params(view: vLayers))
  elif raw.name.len > 0:
    parsedOk(Params(view: vDetail, package: raw.name))
  else:
    parsedOk(Params(view: vList))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch packages [NAME] [--points | --tables | --graph [--reverse] | --dot | --config]`.
  parseCommand(args, packagesSpec(), Raw(), finish)

const
  synopsis = """usage: nch packages
       nch packages NAME
       nch packages --points | --tables | --dot | --config
       nch packages --graph [--reverse] [NAME]"""
  intro =
    """The program describing itself: its packages in dependency order, each with what it is for, its layer (0 for a
package that depends on nothing), how many packages it uses and is used by, how many tables it owns, and what it
provides: commands, extension points it defines, and the points it adds to.  With the name of a package, its documentation
and everything else about it."""

proc usageText*(width: int): string =
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(packagesSpec().docs, width).join("\n") & "\n"

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

proc configLines*(g: Globals): seq[string] =
  ## The settings in force, and where each came from.
  func row(label, value: string): string =
    label.alignLeft(10) & "  " & value
  result.add row("version", versionString)
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
  result.add row("database", fmt"{path}  ({source}; {state})")
  result.add row(
    "user",
    if g.user.len > 0:
      fmt"{g.user}  (--user)"
    else:
      "the default user of the database",
  )
  result.add row("offline", if g.offline: "yes (--offline)" else: "no")
  let log = envLogPath()
  result.add row("log", if log.isSome: log.get else: "off (NCH_LOG is empty)")
  let cache = cacheDir()
  result.add row("cache", if cache.isSome: cache.get else: "none (no HOME)")
  result.add row(
    "access",
    case g.access.mode
    of amEnforce: "enforced: a package that touches the table of another is refused"
    of amOff: "off"
    ,
  )
  result.add row("commands", generated.commands.mapIt(it.name).join(" ") & " packages")
  let variables = [
    "NCH_DB", "NCH_LOG", "NCH_CACHE", "XDG_STATE_HOME", "XDG_CACHE_HOME",
    "XDG_DATA_HOME", "NO_COLOR",
  ].mapIt(setIn(it))
  for i, v in variables:
    result.add row((if i == 0: "environment" else: ""), v)
  result.add fragmentLines(path)

# --- the command -------------------------------------------------------------------------------------------------------

proc inventory(): Inventory =
  try:
    inventoryOf(
      generated.packages, generated.extensions, generated.points, generated.schema
    )
  except PackageError as e:
    raiseAssert e.msg # (the registry has already been checked when it was compiled)

proc show(lines: seq[string]) =
  for l in lines:
    stdout.say l & "\n"

proc packagesMain*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch packages ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch packages", usageText(helpWidth(stderr)), parsed.problem)
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
    return failure(
      "nch packages",
      fmt"no package is called '{asked}' (they are: {inv.packages.mapIt(it.name).sorted.join("" "")})",
    )
  case p.view
  of vList:
    show summaryLines(inv, width)
  of vDetail:
    show detailLines(inv, p.package, width)
  of vPoints:
    show pointLines(inv, width)
  of vTables:
    show tableLines(inv)
  of vLayers:
    show layerLines(inv, width)
  of vTree:
    show treeLines(inv, p.root, p.reverse)
  of vDot:
    stdout.say dotText(inv)
  of vConfig:
    show configLines(g)
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
