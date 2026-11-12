## nch: the nimchoo command line tool.  A thin dispatcher: each command is declared by the package that provides it
## (in its `package.nim`: its name, a summary and `run(globals, args): int`; see core/globals.nim for
## the exit codes), and the generated registry lists them all.  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[algorithm, options, os, sequtils, strformat, strutils]
import nimchoo/core/[globals, manifest, registry as packageRegistry]
import nimchoo/[completion, introspect]
import nimchoo/packages/ui/live
import nimchoo/packages/user/completion as userCompletion
import nimchoo/packages/util/args/[args, usage]
import nimchoo/registry
import nimchoo/core/logfile
import nimchoo/packages/util/version/version
import nimchoo/packages/util/zip/zipchild

{.push raises: [].}

const allCommands = (registry.commands & @[packagesCommand]).sortedByIt(it.name)
  ## the commands of the packages, and those `nch` provides itself

type Head = object ## The options before the command name.
  g: Globals
  help, version, offline: bool
  job: Option[Job] ## `--install-completion` or `--show-completion`

func takeJob(p: var Head, action: Action, value: string): Problem =
  ## `--install-completion [SHELL]`, `--show-completion [SHELL]`.
  if p.job.isSome:
    return refuse("only one of --install-completion and --show-completion may be given")
  let shell = parseShell(value)
  if shell.isNone:
    return refuse(
      fmt"no completion for '{value}' (the shells are {shellNames().join("", "")})"
    )
  p.job = some(Job(action: action, shell: shell.get))
  fine

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
        completion = completesFrom(completeUsers),
        body = (p.g.user = value; fine),
      ),
      custom(
        Head,
        ["--offline"],
        false,
        "",
        "do not use the network (names are made from the places already loaded; the others are left for a run that may use the network)",
        body = (p.g.offline = true; fine),
      ),
      optionalValue(
        Head,
        ["--install-completion"],
        "SHELL",
        "write the script that makes the shell complete `nch` (default: bash) where the shell finds it, so that new shells have it",
        completion = Completion(kind: ckWords, words: shellNames()),
        body = takeJob(p, acInstall, value),
      ),
      optionalValue(
        Head,
        ["--show-completion"],
        "SHELL",
        "print that script instead of writing it (to read it, or `eval \"$(nch --show-completion)\"`)",
        completion = Completion(kind: ckWords, words: shellNames()),
        body = takeJob(p, acShow, value),
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
    # (the shell asking what may be typed next.  The options before the command that are already typed say which database
    # and user the values come from; if they are incomplete or wrong, what was read before the fault stands.  Offline and
    # read-only, whatever was typed: completion changes nothing and uses no network.  See completion.nim)
    let line = args[1 ..^ 1]
    var before = Head(g: Globals(fragments: allFragments))
    var next = 0
    discard parseLeading(line[0 ..< max(0, line.high)], headSpec(), before, next)
    var g = before.g
    g.extensions = registry.extensions
    g.access = allAccess
    g.offline = true
    g.readOnly = true
    return completeMain(headSpec().docs, allCommands, g, line)
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
  if head.job.isSome:
    let job = head.job.get
    case job.action
    of acInstall:
      return installMain(job.shell)
    of acShow:
      return showMain(job.shell)
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
    return usageError("nch", usageText(helpWidth(stderr)), fmt"unknown command {name}")
  g.commandNames = allCommands.mapIt(it.name)
  if name != "log": # (reading the log is not logged)
    let path = envLogPath()
    if path.isSome:
      g.log = openLog(path.get)
      if g.log.problem.len > 0:
        stderr.say fmt"warning: {g.log.problem} (continuing without a log)\n"
  g.log.log(lvInfo, name, leRun, fmt"[{nchCommit}] {rest.join("" "")}")
  result = provided[0].run(g, rest)
  g.log.log(lvInfo, name, leExit, $result)
  g.log.close()

when isMainModule:
  quit main()
