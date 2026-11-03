## nch: the nimchoo command line tool.  A thin dispatcher: each command lives
## in its own module under nimchoo/<module>/command.nim and exposes `run(globals, args):
## int` (see cli/common.nim for the exit codes).  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[options, os, strutils]
import nimchoo/cli/common
import nimchoo/destroy/command as destroyCommand
import nimchoo/selection/command as listCommand
import nimchoo/heatmap/command as heatmapCommand
import nimchoo/log/command as logCommand
import nimchoo/importer/command as importCommand
import nimchoo/fit/command as fitCommand
import nimchoo/modules
import nimchoo/ui/logfile

{.push raises: [].}

const usage = """usage: nch [--db PATH] [--user NAME] COMMAND [ARGS]

  --db PATH      the database file (default: $NCH_DB, else nch/nch.db in the
                 user's data directory)
  --user NAME    whose data to work with (default: the default user)

commands:
  fit      read a FIT file and print it (see `nch fit --help`)
  import   put the activities of FIT files in the database
           (see `nch import --help`)
  list     list activities, and choose the ones other commands use
           (see `nch list --help`)
  heatmap  write the routes of the selected activities as GeoJSON
           (see `nch heatmap --help`)
  log      show the log, filtered, with the events coloured
           (see `nch log --help`)
  destroy  delete the database, or one user and their data
           (see `nch destroy --help`)
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
  of "destroy":
    destroyCommand.run(g, rest)
  else:
    usageError("nch", usage, "unknown command " & command)

proc main(): int {.raises: [].} =
  let args = commandLineParams()
  var g = Globals(fragments: allFragments)
  var i = 0
  while i < args.len and args[i].startsWith("-"):
    let a = args[i]
    if a in ["-h", "--help"]:
      stdout.say usage
      return exitOk
    elif a in ["--db", "--user"]:
      inc i
      if i >= args.len: return usageError("nch", usage, a & " needs a value")
      if a == "--db": g.dbPath = args[i] else: g.user = args[i]
    elif a.startsWith("--db="):
      g.dbPath = a["--db=".len .. ^1]
    elif a.startsWith("--user="):
      g.user = a["--user=".len .. ^1]
    else:
      return usageError("nch", usage, "unknown option " & a)
    inc i
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
  g.log.log(lvInfo, command, leRun, rest.join(" "))
  result = dispatch(g, command, rest)
  g.log.log(lvInfo, command, leExit, $result)
  g.log.close()

when isMainModule:
  quit main()
