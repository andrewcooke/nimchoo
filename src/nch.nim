## nch: the nimchoo command line tool.  A thin dispatcher: each command lives
## in its own module under nimchoo/<module>/command.nim and exposes `run(globals, args):
## int` (see cli/common.nim for the exit codes).  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[options, os, strutils]
import nimchoo/cli/[args, common]
import nimchoo/climbs/command as climbsCommand
import nimchoo/empty/command as emptyCommand
import nimchoo/selection/command as listCommand
import nimchoo/heatmap/command as heatmapCommand
import nimchoo/log/command as logCommand
import nimchoo/landmark/command as landmarkCommand
import nimchoo/sector/command as sectorCommand
import nimchoo/user/command as userCommand
import nimchoo/model/command as modelCommand
import nimchoo/ff/command as ffCommand
import nimchoo/importer/command as importCommand
import nimchoo/fit/command as fitCommand
import nimchoo/modules
import nimchoo/ui/logfile
import nimchoo/version

{.push raises: [].}

const usage = """usage: nch [--db PATH] [--user NAME] COMMAND [ARGS]

  --db PATH      the database file (default: $NCH_DB, else nch/nch.db in the
                 user's data directory)
  --user NAME    whose data to work with (default: the default user)
  --offline      do not use the network (no names are looked up: climbs are "unnamed", and stay so)
  --version      print the version and the git commit it was built from

commands:
  fit      read a FIT file and print it
  import   put the activities of FIT files in the database
  list     list activities, and choose the ones other commands use
  heatmap  write the routes of the selected activities as GeoJSON
  log      show the log, filtered, with the events coloured
  user     the users: make, rename, set the threshold heart rate
  model    the models: sets of variables for the training impulse
  ff       the fitness and fatigue curves, as CSV for plotting
  climbs   the climbs of the selected activities, with times and ranks
  sector   the climbs everyone shares: list them, give one a name
  landmark places of your own, named: they come before every other name
  empty    delete a user's data, the whole database, or the cache files

For more about a command: `nch COMMAND --help`.
"""

proc dispatch(g: Globals, command: string, rest: seq[string]): int {.raises: [].} =
  case command
  of "help":
    stdout.say usage
    exitOk
  of "fit":
    fitCommand.run(g, rest)
  of "import":
    importCommand.run(g, rest)
  of "list":
    listCommand.run(g, rest)
  of "heatmap":
    heatmapCommand.run(g, rest)
  of "log":
    logCommand.run(g, rest)
  of "user":
    userCommand.run(g, rest)
  of "model":
    modelCommand.run(g, rest)
  of "ff":
    ffCommand.run(g, rest)
  of "empty":
    emptyCommand.run(g, rest)
  of "climbs":
    climbsCommand.run(g, rest)
  of "sector":
    sectorCommand.run(g, rest)
  of "landmark":
    landmarkCommand.run(g, rest)
  else:
    usageError("nch", usage, "unknown command " & command)

type Head = object
  ## The options before the command name.
  g: Globals
  help, version, offline: bool

proc main(): int {.raises: [].} =
  let args = commandLineParams()
  var head = Head(g: Globals(fragments: allFragments, importSteps: allImportSteps))
  let spec = Spec[Head](opts: @[
    flag(Head, ["-h", "--help"], help),
    flag(Head, ["--version"], version),
    custom(Head, ["--offline"], false, (p.g.offline = true; "")),
    custom(Head, ["--db"], true, (p.g.dbPath = value; "")),
    custom(Head, ["--user"], true, (p.g.user = value; ""))])
  var i = 0
  let why = parseLeading(args, spec, head, i)
  if why.len > 0: return usageError("nch", usage, why)
  if head.help:
    stdout.say usage
    return exitOk
  if head.version:
    stdout.say versionString & "\n"
    return exitOk
  var g = head.g
  if i >= args.len:
    stderr.say usage
    return exitUsage
  let rest = args[i + 1 .. ^1]
  let command = args[i]
  if command in commandNames and command != "log":      # (reading the log is not logged)
    let path = envLogPath()
    if path.isSome:
      g.log = openLog(path.get)
      if g.log.problem.len > 0:
        stderr.say "warning: " & g.log.problem & " (continuing without a log)\n"
  g.log.log(lvInfo, command, leRun, "[" & nchCommit & "] " & rest.join(" "))
  result = dispatch(g, command, rest)
  g.log.log(lvInfo, command, leExit, $result)
  g.log.close()

when isMainModule:
  quit main()
