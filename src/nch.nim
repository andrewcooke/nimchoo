## nch: the nimchoo command line tool.  A thin dispatcher: each command is declared by the package that provides it
## (in its `package.nim`: its name, a summary and `run(globals, args): int`; see core/globals.nim for
## the exit codes), and the generated registry lists them all.  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[algorithm, options, os, sequtils, strutils]
import nimchoo/core/[globals, manifest, registry as packageRegistry]
import nimchoo/[completion, introspect]
import nimchoo/packages/ui/live
import nimchoo/packages/util/args/[args, usage]
import nimchoo/registry
import nimchoo/core/logfile
import nimchoo/packages/util/version/version
import nimchoo/packages/util/zip/zipchild

{.push raises: [].}

const allCommands =
  (registry.commands & @[packagesCommand, completionCommand]).sortedByIt(it.name)
  ## the commands of the packages, and those `nch` provides itself

type Head = object ## The options before the command name.
  g: Globals
  help, version, offline: bool

func headSpec(): Spec[Head] =
  ## The options every command takes, given before its name.
  Spec[Head](
    opts: @[
      custom(
        Head,
        ["--db"],
        true,
        "PATH",
        "the database file (default: $NCH_DB, else nch/nch.db in the user's data directory)",
        completion = Completion(kind: ckFile),
        body = (p.g.dbPath = value; fine),
      ),
      custom(
        Head,
        ["--user"],
        true,
        "NAME",
        "whose data to work with (default: the default user)",
        completion = Completion(kind: ckDynamic, source: "user"),
        body = (p.g.user = value; fine),
      ),
      custom(
        Head,
        ["--offline"],
        false,
        "",
        "do not use the network (no names are looked up: climbs are \"unnamed\", and stay so)",
        body = (p.g.offline = true; fine),
      ),
      flag(
        Head,
        ["--version"],
        version,
        "print the version and the git commit it was built from",
      ),
      helpFlag(Head),
    ]
  )

proc usageText(width: int): string =
  ## The usage: the options every command takes, and the commands.
  "usage: nch [--db PATH] [--user NAME] COMMAND [ARGS]\n\n" &
    optionLines(headSpec().docs, width).join("\n") & "\n\ncommands:\n" &
    commandList(allCommands) & "\nFor more about a command: `nch COMMAND --help`.\n"

proc main(): int {.raises: [].} =
  let args = commandLineParams()
  if args.len > 0 and args[0] == inflateFlag:
    # (a child of the downloads: see zipchild.nim)
    return inflateChildMain(args[1 ..^ 1])
  if args.len > 0 and args[0] == completeFlag:
    # (the shell asking what may be typed next: offline, and all the packages' options are known: completion.nim)
    let g = Globals(
      fragments: allFragments,
      extensions: registry.extensions,
      access: allAccess,
      offline: true,
    )
    return completeMain(headSpec().docs, allCommands, g, args[1 ..^ 1])
  var head = Head(g: Globals(fragments: allFragments))
  var i = 0
  let why = parseLeading(args, headSpec(), head, i)
  if why.isSome:
    return usageError("nch", usageText(helpWidth(stderr)), why.get)
  if head.help:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  if head.version:
    stdout.say versionString & "\n"
    return exitOk
  var g = head.g
  g.extensions = registry.extensions
  g.access = allAccess
  if i >= args.len:
    stderr.say usageText(helpWidth(stderr))
    return exitUsage
  let rest = args[i + 1 .. ^1]
  if args[i] == "help":
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  let name = args[i]
  let provided = allCommands.filterIt(it.name == name)
  if provided.len == 0:
    return usageError("nch", usageText(helpWidth(stderr)), "unknown command " & name)
  g.commandNames = allCommands.mapIt(it.name)
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
