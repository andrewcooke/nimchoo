## nch: the nimchoo command line tool.  A thin dispatcher: each command lives
## in its own module under nimchoo/<module>/command.nim and exposes `run(globals, args):
## int` (see cli/common.nim for the exit codes).  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[options, os, strutils]
import nimchoo/cli/[args, catalog, common]
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
""" & commandList() & """
For more about a command: `nch COMMAND --help`.
"""

proc dispatch(g: Globals, command: Command, rest: seq[string]): int {.raises: [].} =
  ## (no `else`: a command in `Command` that is not run here does not compile)
  case command
  of cmFit:
    fitCommand.run(g, rest)
  of cmActivities:
    activitiesCommand.run(g, rest)
  of cmMap:
    mapCommand.run(g, rest)
  of cmLog:
    logCommand.run(g, rest)
  of cmUsers:
    userCommand.run(g, rest)
  of cmModels:
    modelCommand.run(g, rest)
  of cmFf:
    ffCommand.run(g, rest)
  of cmCache:
    cacheCommand.run(g, rest)
  of cmDb:
    dbCommand.run(g, rest)
  of cmClimbs:
    climbsCommand.run(g, rest)
  of cmLandmarks:
    landmarkCommand.run(g, rest)

type Head = object ## The options before the command name.
  g: Globals
  help, version, offline: bool

proc main(): int {.raises: [].} =
  let args = commandLineParams()
  var head = Head(g: Globals(fragments: allFragments, importSteps: allImportSteps))
  let spec = Spec[Head](
    opts: @[
      flag(Head, ["-h", "--help"], help),
      flag(Head, ["--version"], version),
      custom(Head, ["--offline"], false, (p.g.offline = true; "")),
      custom(Head, ["--db"], true, (p.g.dbPath = value; "")),
      custom(Head, ["--user"], true, (p.g.user = value; "")),
    ]
  )
  var i = 0
  let why = parseLeading(args, spec, head, i)
  if why.len > 0:
    return usageError("nch", usage, why)
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
  if args[i] == "help":
    stdout.say usage
    return exitOk
  let parsed = parseCommand(args[i])
  if parsed.isNone:
    return usageError("nch", usage, "unknown command " & args[i])
  let command = parsed.get
  if command != cmLog: # (reading the log is not logged)
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
