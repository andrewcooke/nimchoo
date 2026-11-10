## `nch log`: show the log, filtered, with the events coloured as on the screen.
## The file itself stays plain text (an escape next to a word would stop
## `grep -w` matching).  Newer than the commands whose lines it reads, but it
## knows them only by name (the log's command column).

import std/[options, os, sequtils, strutils]
import ../../core/globals
import ../util/args/args
import ../../core/logfile
import ../ui/live
import ../ui/style
import ../ui/vocabulary
import ./lines

{.push raises: [].}

const commandName* = "log" ## what the user types after `nch`

const usage* = """usage: nch log [COMMAND...] [EVENT...] [--last] [-n N]

Show the log (see NCH_LOG).  Names say what to show: a COMMAND (activities, climbs,
cache ...) shows the lines of those commands, an EVENT (failed, advisory,
duplicate ...) shows those events; both together show the events of those
commands.  Several of one kind mean "any of them".  With no names, everything.

  --last       only the latest run of the commands (or of any command): from
               its "run" line to the end
  -n N         only the last N lines
  -h, --help   show this help

On a terminal the event words have the colours they have in `nch activities --import`
(imported green, failed red, advisory yellow, duplicate grey).
"""

type Parsed* = object
  known: seq[string] ## the names of the commands there are
  filter*: Filter
  help*: bool
  problem*: string

proc names(commands: seq[string]): string =
  var es: seq[string]
  for e in LogEvent:
    es.add $e
  "commands: " & commands.join(" ") & "; events: " & es.join(" ")

proc takeLogName(p: var Parsed, arg: string): string {.nimcall, raises: [].} =
  ## A word that names an event or a command to show.
  let e = parseEvent(arg)
  if e.isSome:
    p.filter.events.incl e.get
  elif arg in p.known:
    p.filter.commands.add arg
  else:
    return "'" & arg & "' is neither a command nor an event (" & names(p.known) & ")"
  ""

proc parseArgs*(args: seq[string], commands: seq[string]): Parsed =
  ## The options of `nch log`; `problem` says what is wrong with them, if anything.  `commands` are the names
  ## of the commands there are, which can be used as filters.
  let lastOption = custom(Parsed, ["--last"], false, (p.filter.last = true; ""))
  let countOption = custom(Parsed, ["-n"], true):
    var n = 0
    if not parseIntIn(value, 1, high(int), n):
      return "-n needs a number of lines, 1 or more"
    p.filter.count = n
    ""
  let spec = Spec[Parsed](
    opts: @[flag(Parsed, ["-h", "--help"], help), lastOption, countOption],
    positional: takeLogName,
  )
  result.known = commands
  result.problem = parseOptions(args, spec, result)

proc show*(
    path: string, f: Filter, colour: bool
): tuple[lines: seq[string], problem: string] =
  ## The lines to print for the log at `path`, or what is wrong.
  if not fileExists(path):
    result.problem = "no log at " & path & " yet"
    return
  var all: seq[LogLine]
  try:
    for l in lines(path):
      all.add parseLine(l)
  except IOError as e:
    result.problem = "cannot read " & path & ": " & e.msg
    return
  let s = select(all, f)
  if s.noRun:
    result.problem =
      "no run of " & (
        if f.commands.len > 0: f.commands.join(" or ")
        else: "any command"
      ) & " in the log" & (
        if all.anyIt(it.event.isNone):
        " (lines from before the log's current format are not recognised)"
        else: ""
      )
    return
  for l in s.lines:
    result.lines.add render(styled(l), colour)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch log ARGS`; returns the exit status.
  let p = parseArgs(args, g.commandNames)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch log", usage, p.problem)
  let path = envLogPath()
  if path.isNone:
    return failure(
      "nch log",
      "logging is switched off (NCH_LOG is empty, or there is no home directory)",
    )
  let r = show(path.get, p.filter, canColourStdout())
  if r.problem.len > 0:
    return failure("nch log", r.problem)
  for l in r.lines:
    stdout.say l & "\n"
  exitOk
