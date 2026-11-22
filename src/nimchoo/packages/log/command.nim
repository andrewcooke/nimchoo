## `nch log`: show the log, filtered, with the events coloured as on the screen.
## The file itself stays plain text (an escape next to a word would stop
## `grep -w` matching).  Newer than the commands whose lines it reads, but it
## knows them only by name (the log's command column).

import std/[options, os, sequtils, strutils]
import ../../core/globals
import ../util/args/[args, usage]
import ../../core/logfile
import ../ui/style
import ./[lines, params]

{.push raises: [].}

const commandName* = "log" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch log`, described (for tab completion).
  logSpec().docs

const
  synopsis = "usage: nch log [COMMAND...] [EVENT...] [--last] [-n N]"
  intro = @[
    ~"Show the log (see NCH_LOG).  Names say what to show: a COMMAND (import, activities, climbs, cache ...) shows the lines of those commands, an EVENT (failed, advisory, duplicate ...) shows those events; both together show the events of those commands.  Several of one kind mean \"any of them\".  With no names, everything."
  ]
  notes = @[
    ~"On a terminal the event words have the styles they have in `nch import` (imported good, failed bad, advisory a warning, duplicate dimmed: their colours are the theme's, see `nch --theme`)."
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  usageOf(synopsis, width, intro, logSpec().docs, notes)

proc show*(path: string, f: Filter): tuple[lines: seq[Line], problem: string] =
  ## The lines to print for the log at `path` (the level and event words in their styles), or what is wrong.
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
    result.lines.add styled(l)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch log ARGS`; returns the exit status.
  let parsed = parseArgs(args, g.commandNames)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch log", usageText(g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch log", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  let path = envLogPath()
  if path.isNone:
    return failure(
      g,
      "nch log",
      ~"logging is switched off (NCH_LOG is empty, or there is no home directory)",
    )
  let r = show(path.get, p.filter)
  if r.problem.len > 0:
    return failure(g, "nch log", r.problem)
  g.showAll(osOut, r.lines)
  exitOk
