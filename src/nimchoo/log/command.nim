## `nch log`: show the log, filtered, with the events coloured as on the screen.
## The file itself stays plain text (an escape next to a word would stop
## `grep -w` matching).  Newer than the commands whose lines it reads, but it
## knows them only by name (the log's command column).

import std/[options, os, sequtils, strutils]
from std/terminal import isatty
import ../cli/common
import ../ui/[logfile, style, vocabulary]
import ./lines

{.push raises: [].}

const usage* = """usage: nch log [COMMAND...] [EVENT...] [--last] [-n N]

Show the log (see NCH_LOG).  Names say what to show: a COMMAND (import, select,
destroy ...) shows the lines of those commands, an EVENT (failed, advisory,
duplicate ...) shows those events; both together show the events of those
commands.  Several of one kind mean "any of them".  With no names, everything.

  --last       only the latest run of the commands (or of any command): from
               its "run" line to the end
  -n N         only the last N lines
  -h, --help   show this help

On a terminal the event words have the colours they have in `nch import`
(imported green, failed red, advisory yellow, duplicate grey).
"""

type Parsed* = object
  filter*: Filter
  help*: bool
  problem*: string

proc names(): string =
  var cs: seq[string]
  for c in commandNames: cs.add c
  var es: seq[string]
  for e in LogEvent: es.add $e
  "commands: " & cs.join(" ") & "; events: " & es.join(" ")

proc parseArgs*(args: seq[string]): Parsed =
  var i = 0
  while i < args.len:
    let a = args[i]
    case a
    of "-h", "--help": result.help = true
    of "--last": result.filter.last = true
    of "-n":
      inc i
      var n = 0
      try:
        if i < args.len: n = parseInt(args[i])
      except ValueError:
        discard
      if n < 1:
        result.problem = "-n needs a number of lines, 1 or more"
        return
      result.filter.count = n
    else:
      if a.startsWith("-"):
        result.problem = "unexpected option " & a
        return
      let e = parseEvent(a)
      if e.isSome:
        result.filter.events.incl e.get
      elif a in commandNames:
        result.filter.commands.add a
      else:
        result.problem = "'" & a & "' is neither a command nor an event (" & names() & ")"
        return
    inc i

proc show*(path: string, f: Filter, colour: bool): tuple[lines: seq[string], problem: string] =
  ## The lines to print for the log at `path`, or what is wrong.
  if not fileExists(path):
    result.problem = "no log at " & path & " yet"
    return
  var all: seq[LogLine]
  try:
    for l in lines(path): all.add parseLine(l)
  except IOError as e:
    result.problem = "cannot read " & path & ": " & e.msg
    return
  let s = select(all, f)
  if s.noRun:
    result.problem = "no run of " & (if f.commands.len > 0: f.commands.join(" or ") else: "any command") &
      " in the log" & (if all.anyIt(it.event.isNone): " (lines from before the log's current format are not recognised)" else: "")
    return
  for l in s.lines: result.lines.add render(styled(l), colour)

proc stdoutColour(): bool =
  ## Colour only on a terminal that is not "dumb", and if NO_COLOR is not set.
  isatty(stdout) and getEnv("TERM") != "dumb" and getEnv("NO_COLOR").len == 0

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch log ARGS`; returns the exit status.
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch log", usage, p.problem)
  let path = envLogPath()
  if path.isNone:
    return failure("nch log", "logging is switched off (NCH_LOG is empty, or there is no home directory)")
  let r = show(path.get, p.filter, stdoutColour())
  if r.problem.len > 0:
    return failure("nch log", r.problem)
  for l in r.lines: stdout.say l & "\n"
  exitOk
