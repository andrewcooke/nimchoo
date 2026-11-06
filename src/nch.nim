## nch: the nimchoo command line tool.  A thin dispatcher: each command lives
## in its own module under nimchoo/<module>/command.nim and exposes `run(globals, args):
## int` (see cli/common.nim for the exit codes).  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[options, os, strutils]
import nimchoo/cli/[args, common]
import nimchoo/climbs/command as climbsCommand
import nimchoo/cache/command as cacheCommand
import nimchoo/db/command as dbCommand
import nimchoo/selection/command as activitiesCommand
import nimchoo/map/command as mapCommand
import nimchoo/log/command as logCommand
import nimchoo/landmark/command as landmarkCommand
import nimchoo/user/command as userCommand
import nimchoo/model/command as modelCommand
import nimchoo/ff/command as ffCommand
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
  activities  the activities: show them, choose the ones other commands use
  climbs      the climbs of the selected activities, with times and ranks
  users       the users: make, rename, set the threshold heart rate
  models      the models: sets of variables for the training impulse
  landmarks   places of your own, named: they come before every other name
  map         the routes of the selected activities and their climbs, on a map
  ff          the fitness and fatigue curves, as CSV for plotting
  fit         read a FIT file and print it
  log         show the log, filtered, with the events coloured
  cache       the files outside the database (downloads, generated files): show them, delete them
  db          the database file: where it is and how big, or delete it

For more about a command: `nch COMMAND --help`.
"""

proc dispatch(g: Globals, command: string, rest: seq[string]): int {.raises: [].} =
  case command
  of "help":
    stdout.say usage
    exitOk
  of "fit":
    fitCommand.run(g, rest)
  of "activities":
    activitiesCommand.run(g, rest)
  of "map":
    mapCommand.run(g, rest)
  of "log":
    logCommand.run(g, rest)
  of "users":
    userCommand.run(g, rest)
  of "models":
    modelCommand.run(g, rest)
  of "ff":
    ffCommand.run(g, rest)
  of "cache":
    cacheCommand.run(g, rest)
  of "db":
    dbCommand.run(g, rest)
  of "climbs":
    climbsCommand.run(g, rest)
  of "landmarks":
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
