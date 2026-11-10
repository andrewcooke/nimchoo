## nch: the nimchoo command line tool.  A thin dispatcher: each command is declared by the package that provides it
## (in its `package.nim`: its name, a summary and `run(globals, args): int`; see core/globals.nim for
## the exit codes), and the generated registry lists them all.  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[options, os, sequtils, strutils]
import nimchoo/core/[globals, registry as packageRegistry]
import nimchoo/packages/util/args/args
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
  commandList(registry.commands) & """
For more about a command: `nch COMMAND --help`.
"""

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
  g.extensions = registry.extensions
  g.access = allAccess
  if i >= args.len:
    stderr.say usage
    return exitUsage
  let rest = args[i + 1 .. ^1]
  if args[i] == "help":
    stdout.say usage
    return exitOk
  let name = args[i]
  let provided = registry.commands.filterIt(it.name == name)
  if provided.len == 0:
    return usageError("nch", usage, "unknown command " & name)
  g.commandNames = registry.commands.mapIt(it.name)
  if name != "log": # (reading the log is not logged)
    let path = envLogPath()
    if path.isSome:
      g.log = openLog(path.get)
      if g.log.problem.len > 0:
        stderr.say "warning: " & g.log.problem & " (continuing without a log)\n"
  g.log.log(lvInfo, name, leRun, "[" & nchCommit & "] " & rest.join(" "))
  result = provided[0].run(g, rest)
  g.log.log(lvInfo, name, leExit, $result)
  g.log.close()

when isMainModule:
  quit main()
