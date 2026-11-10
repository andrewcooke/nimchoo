## `nch log`: show the log, filtered, with the events coloured as on the screen.
## The file itself stays plain text (an escape next to a word would stop
## `grep -w` matching).  Newer than the commands whose lines it reads, but it
## knows them only by name (the log's command column).

import std/[options, os, sequtils, strutils]
import ../../core/globals
import ../util/args/[args, usage]
import ../../core/logfile
import ../ui/live
import ../ui/style
import ./[lines, params]

{.push raises: [].}

const commandName* = "log" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch log`, described (for tab completion).
  logSpec().docs

const
  synopsis = "usage: nch log [COMMAND...] [EVENT...] [--last] [-n N]"
  intro =
    """Show the log (see NCH_LOG).  Names say what to show: a COMMAND (import, activities, climbs, cache ...) shows the
lines of those commands, an EVENT (failed, advisory, duplicate ...) shows those events; both together show the events
of those commands.  Several of one kind mean "any of them".  With no names, everything."""
  notes =
    """On a terminal the event words have the colours they have in `nch import` (imported green, failed red, advisory
yellow, duplicate grey)."""

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(logSpec().docs, width).join("\n") & "\n\n" & prose(notes, width) & "\n"

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
  let parsed = parseArgs(args, g.commandNames)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch log", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
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
