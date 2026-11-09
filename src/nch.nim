## nch: the nimchoo command line tool.  A thin dispatcher: each command lives
## in its own module under nimchoo/<module>/command.nim and exposes `run(globals, args):
## int` (see core/globals.nim for the exit codes).  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[options, os, sequtils, strutils]
import nimchoo/cli/catalog
import nimchoo/core/globals
import nimchoo/packages/util/args/args
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
import nimchoo/modules
import nimchoo/registry
import nimchoo/core/logfile
import nimchoo/packages/util/version/version
import nimchoo/packages/util/zip/zipchild

{.push raises: [].}

const usage =
  """usage: nch [--db PATH] [--user NAME] COMMAND [ARGS]

  --db PATH      the database file (default: $NCH_DB, else nch/nch.db in the
                 user's data directory)
  --user NAME    whose data to work with (default: the default user)
  --offline      do not use the network (no names are looked up: climbs are "unnamed", and stay so)
  --version      print the version and the git commit it was built from

commands:
""" &
  commandList(registry.commands.mapIt((it.name, it.summary))) & """
For more about a command: `nch COMMAND --help`.
"""

proc dispatch(g: Globals, command: Command, rest: seq[string]): int {.raises: [].} =
  ## (no `else`: a command in `Command` that is not run here does not compile)
  case command
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
  if args.len > 0 and args[0] == inflateFlag:
    # (a child of the downloads: see zipchild.nim)
    return inflateChildMain(args[1 ..^ 1])
  var head = Head(g: Globals(fragments: allFragments))
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
  let name = args[i]
  let provided = registry.commands.filterIt(it.name == name)
  let parsed = parseCommand(name)
  if provided.len == 0 and parsed.isNone:
    return usageError("nch", usage, "unknown command " & name)
  g.commandNames = registry.commands.mapIt(it.name) & toSeq(Command).mapIt($it)
  if name != $cmLog: # (reading the log is not logged)
    let path = envLogPath()
    if path.isSome:
      g.log = openLog(path.get)
      if g.log.problem.len > 0:
        stderr.say "warning: " & g.log.problem & " (continuing without a log)\n"
  g.log.log(lvInfo, name, leRun, "[" & nchCommit & "] " & rest.join(" "))
  result =
    if provided.len > 0:
      provided[0].run(g, rest)
    else:
      dispatch(g, parsed.get, rest)
  g.log.log(lvInfo, name, leExit, $result)
  g.log.close()

when isMainModule:
  quit main()
