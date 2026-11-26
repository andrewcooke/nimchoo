## nch: the nimchoo command line tool.  A thin dispatcher: each command is declared by the package that provides it
## (in its `package.nim`: its name, a summary and `run(globals, args): int`; see core/globals.nim for
## the exit codes), and the generated registry lists them all.  Options that every
## command can use (which database, which user) come before the command name
## and are parsed here.

import std/[algorithm, options, os, sequtils, strformat, strutils, terminal]
import nimchoo/core/[globals, manifest, registry as packageRegistry]
import nimchoo/[completion, introspect, settings]
import nimchoo/packages/cache/cache
import nimchoo/packages/themes/choose
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
  help, version, config: bool
  theme: Option[string] ## `--theme`
  install: Option[Shell] ## `--install-completion`

func takeShell(p: var Head, value: string): Problem =
  ## `--install-completion [SHELL]`.
  let shell = parseShell(value)
  if shell.isNone:
    return refuse(
      ~"no completion for '{value}' (the shells are {shellNames().join(\", \")})"
    )
  p.install = shell
  fine

proc completeThemes(g: Globals, typed: string): seq[string] {.nimcall, raises: [].} =
  ## The themes whose names start with what is typed.
  themeNames(cacheDir()).filterIt(it.startsWith(typed))

func headSpec(): Spec[Head] =
  ## The options every command takes, given before its name.
  Spec[Head](
    noYes: true,
    opts: @[
      custom(
        Head,
        ["--db"],
        true,
        "PATH",
        ~"the database file (default: `$NCH_DB`, or `nch/nch.db` in the user's data directory (see `nch --config`))",
        completion = Completion(kind: ckFile),
        body = (p.g.dbPath = some(value); fine),
      ),
      custom(
        Head,
        ["--user"],
        true,
        "NAME",
        ~"whose data to work with (default: `$NCH_USER`, or the default user)",
        completion = completesFrom(completeUsers),
        body = (p.g.user = some(value); fine),
      ),
      custom(
        Head,
        ["--offline"],
        false,
        "",
        ~"do not use the network (already cached data are used where possible)",
        body = (p.g.offline = true; fine),
      ),
      custom(
        Head,
        ["--theme"],
        true,
        "NAME",
        ~"text styling: the theme in the file `NAME.theme` of `nch/system/themes/` in the cache directory (see `nch --config`) (default: `$NCH_THEME`, or the link `.current` there, or light or dark from `$COLORFGBG`, or dark)",
        completion = completesFrom(completeThemes),
        body = (p.theme = some(value); fine),
      ),
      optionalValue(
        Head,
        ["--install-completion"],
        "SHELL",
        ~"write the script for shell completion at the appropriate location (default: bash); run once to install, then start a new shell",
        completion = Completion(kind: ckWords, words: shellNames()),
        body = takeShell(p, value),
      ),
      flag(Head, ["--version"], version, ~"show the version and git commit built"),
      flag(
        Head,
        ["--config"],
        config,
        ~"show the current settings and related environment variables, with descriptions",
      ),
      helpFlag(Head),
    ],
  )

proc usageText(width: int): seq[Line] =
  ## The usage: the options every command takes, and the commands.
  usageOf(
    "usage: nch [--db PATH] [--user NAME] [--offline] [--theme NAME] COMMAND [ARGS]",
    width,
    options = headSpec().docs,
    notes = @[~"for help on a specific command: `nch COMMAND --help`"],
    sections = @[("commands", optionLines(commandDocs(allCommands), width))],
  )

proc withRegistry(g: Globals): Globals =
  ## `g` with what the whole program has: the extensions and the access model of the registry.
  result = g
  result.extensions = registry.extensions
  result.access = allAccess

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
    var g = before.g.withRegistry
    g.offline = true
    g.readOnly = true
    return completeMain(headSpec().docs, allCommands, g, line)
  var head = Head(g: Globals(fragments: allFragments))
  var i = 0
  let why = parseLeading(args, headSpec(), head, i)
  # (the theme and the colours first, so that everything said is in them, even a bad command line)
  var g = head.g.withRegistry
  g.terminal = [isatty(stdout), isatty(stderr)]
  g.colour = [canColourStdout(), canColour()]
  g.width = [helpWidth(stdout), helpWidth(stderr)]
  let chosen = loadTheme(cacheDir(), head.theme)
  g.theme = chosen.theme
  if chosen.warning.isSome:
    g.warn chosen.warning.get
  if why.isSome:
    return usageError(g, "nch", usageText(g.textWidth(osErr)), why.get)
  if head.help:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  if head.version:
    g.show(osOut, plain(versionString))
    return exitOk
  if head.config:
    g.showAll osOut, configLines(g, g.textWidth(osOut), allCommands.mapIt(it.name))
    return exitOk
  if head.install.isSome:
    return installMain(g, head.install.get)
  if i >= args.len:
    g.showAll osErr, usageText(g.textWidth(osErr))
    return exitUsage
  let rest = args[i + 1 .. ^1]
  let name = args[i]
  let provided = allCommands.filterIt(it.name == name)
  if provided.len == 0:
    return
      usageError(g, "nch", usageText(g.textWidth(osErr)), ~"unknown command {name}")
  g.leading = args[0 ..< i]
  g.commandNames = allCommands.mapIt(it.name)
  if name != "log": # (reading the log is not logged)
    let path = envLogPath()
    if path.isSome:
      g.log = openLog(path.get)
      if g.log.problem.isSome:
        g.warn ~"{g.log.problem.get} (continuing without a log)"
  g.log.log(lvInfo, name, leRun, fmt"[{nchCommit}] {rest.join("" "")}")
  result = provided[0].run(g, rest)
  g.log.log(lvInfo, name, leExit, $result)
  g.log.close()

when isMainModule:
  quit main()
