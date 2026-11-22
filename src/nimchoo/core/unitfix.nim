## A number typed without its unit, and the question that follows (`nch activities: --radius 3 has no unit; did you mean`).
##
## Units are required in input (`3km`, `90s`: `ui/units`), but a bare number is not a mistake to be lost in a message: the
## parser (`util/args`) reads it as if the option's default unit were there and says so, as the fourth outcome of a
## command's `parseArgs` (`pkUnit`, beside valid, help and a problem), carrying the **corrected arguments**.  What to do
## about it is the same for every command, so it is written once, here: `unitRetry` is what a command's `run` calls for
## that outcome (as it calls `usageError` for a problem).  On a terminal it asks, and on yes the command runs again with the
## corrected arguments; anywhere else it fails with the usage exit code and prints the corrected line, which can be run as it is.
##
## `askUnit` takes whether there is a terminal and where an answer comes from, so that a test can drive it.

import std/[options, os, strformat, strutils, terminal]
import ./[globals, line]

{.push raises: [].}

type
  Unitless* = object ## one option given a bare number
    option*: string ## as it was spelt, `--radius`
    value*: string ## as it was typed, `3`
    unit*: string ## what the option's default unit is, `km`

  UnitFix* = object
    ## What a command line needs: the options that were given bare numbers, and the arguments with each default unit added.
    missing*: seq[Unitless]
    args*: seq[string]

func commandLine*(command: string, args: seq[string]): string =
  ## `nch activities --radius 3km`: the command and its arguments, each quoted again as a shell wants them.
  var parts = @[command]
  for a in args:
    parts.add quoteShell(a)
  parts.join(" ")

func questionLines*(command: string, fix: UnitFix): seq[Line] =
  ## The question, in three styles, one line each: what is missing (`warn`), the command line with the default unit added
  ## (default), and the choice (`em`; the third has no end of line: the answer follows it).
  var named: seq[string]
  for m in fix.missing:
    named.add m.option & " " & m.value
  let what = named.join(", ")
  let tail = if fix.missing.len == 1: "has no unit" else: "have no unit"
  @[
    @[span(fmt"{command}: {what} {tail}; did you mean", "warn")],
    plain(fmt"  {commandLine(command, fix.args)}"),
    @[span("[Yn]", "em"), span(" ")],
  ]

proc askUnit*(
    g: Globals,
    command: string,
    fix: UnitFix,
    terminal: bool,
    answer: proc(): Option[string] {.raises: [].},
): Option[seq[string]] =
  ## Say what is missing and what was meant (`questionLines`).  On a `terminal` ask, and read the answer with `answer` (none:
  ## the input ended): Enter or `y` means yes, and the corrected arguments are given back; anything else, and no terminal,
  ## gives none.
  let lines = questionLines(command, fix)
  g.show(osErr, lines[0])
  g.show(osErr, lines[1])
  if not terminal:
    return none(seq[string])
  g.prompt(osErr, lines[2])
  let reply = answer()
  if reply.isSome and reply.get.strip.toLowerAscii in ["", "y", "yes"]:
    some(fix.args)
  else:
    none(seq[string])

proc readAnswer(): Option[string] =
  try:
    some(stdin.readLine)
  except IOError, EOFError:
    none(string)

proc unitRetry*(
    g: Globals,
    command: string,
    fix: UnitFix,
    run: proc(g: Globals, args: seq[string]): int {.nimcall, raises: [].},
): int =
  ## What a command's `run` does for `pkUnit`: ask (`askUnit`, on the real terminal), then run again with the corrected
  ## arguments, or give the usage exit code.
  let again = askUnit(g, command, fix, isatty(stdin) and isatty(stderr), readAnswer)
  if again.isSome:
    run(g, again.get)
  else:
    exitUsage
