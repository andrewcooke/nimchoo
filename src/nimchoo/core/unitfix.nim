## A number typed without its unit, and the question that follows (`nch activities: --radius 3 has no unit; did you mean`).
##
## Units are required in input (`3km`, `90s`: `ui/units`), but a bare number is not a mistake to be lost in a message: the
## parser (`util/args`) reads it as if the option's default unit were there and says so, as the fourth outcome of a
## command's `parseArgs` (`pkUnit`, beside valid, help and a problem), carrying the **corrected arguments**.  What to do
## about it is the same for every command, so it is written once, here: `unitRetry` is what a command's `run` calls for
## that outcome (as it calls `usageError` for a problem).  It asks (`core/ask`: default yes, `-y` and `--no` answer at once), and on yes the command runs
## again with the corrected arguments; on no (`--no`, or no terminal and no `-y`), it gives the usage exit code, the corrected line
## having been shown.
##
## `askUnit` takes whether there is a terminal and where an answer comes from, so that a test can drive it.

import std/[options, os, strformat, strutils, terminal]
import ./[ask, globals, line]

{.push raises: [].}

type
  Unitless* = object ## one option given a bare number
    option*: string ## as it was spelt, `--radius`
    value*: string ## as it was typed, `3`
    unit*: string ## what the option's default unit is, `km`

  UnitFix* = object
    ## What a command line needs: the options that were given bare numbers, and the arguments with each default unit added.
    missing*: seq[Unitless]
    original*: seq[string] ## the arguments as they were typed
    args*: seq[string] ## the same, with the unit added where it was missing
    yOrN*: YesOrNo ## what `-y` or `--no` says to the question

func insertedIn(typed, corrected: string): seq[bool] =
  ## For each character of `corrected`, whether it was added to `typed` (which is a subsequence of it: only text was inserted).
  var at = 0
  for c in corrected:
    if at < typed.len and typed[at] == c:
      result.add false
      inc at
    else:
      result.add true

func argument(typed, corrected: string): Line =
  ## One argument as a shell wants it back: quoted as a whole if need be, with the characters that were added in `em`.
  let added = insertedIn(typed, corrected)
  let quoted = quoteShell(corrected) != corrected
  var parts: Line
  proc put(parts: var Line, text: string, em: bool) =
    if text.len == 0:
      return
    if parts.len > 0 and (parts[^1].styles.len > 0) == em:
      parts[^1].text.add text
    elif em:
      parts.add span(text, "em")
    else:
      parts.add span(text)

  if quoted:
    parts.put("'", false)
  for k, c in corrected:
    if quoted and c == '\'':
      parts.put("'\"'\"'", false)
    else:
      parts.put($c, added[k])
  if quoted:
    parts.put("'", false)
  parts

func commandLine*(leading: seq[string], command: string, fix: UnitFix): Line =
  ## `nch --offline activities --radius 3km`: the program, the arguments before the command (`leading`), the command (`nch
  ## activities`: the program's name and the command's) and its arguments, each quoted again as a shell wants them.  What was
  ## added to an argument (the unit) is in `em`, so that a person sees what was changed.
  let words = command.splitWhitespace
  var text = words[0 .. 0]
  for a in leading:
    text.add quoteShell(a)
  text.add words[1 .. ^1]
  result = plain(text.join(" "))
  let known = fix.original.len == fix.args.len
  for k, a in fix.args:
    result.add span(" ")
    result.add argument(
      if known:
        fix.original[k]
      else:
        a,
      a,
    )

func questionLines*(leading: seq[string], command: string, fix: UnitFix): seq[Line] =
  ## The question, in two lines: what is missing (`warn`), then the command line with the unit added (default, the unit
  ## itself in `em`); on a terminal `[Yn]` (`warn`) follows it on the same line (`askUnit`).
  var named: seq[string]
  for m in fix.missing:
    named.add m.option & " " & m.value
  let what = named.join(", ")
  let tail = if fix.missing.len == 1: "is missing a unit" else: "are missing units"
  @[
    @[span(fmt"{command}: {what} {tail}; did you mean", "warn")],
    @[span(">", "warn"), span(" ")] & commandLine(leading, command, fix),
  ]

proc askUnit*(
    g: Globals, command: string, fix: UnitFix, terminal: bool, key: KeyReader
): Option[seq[string]] =
  ## Say what is missing and what was meant (`questionLines`) and `ask` (default yes, `[Yn]` after the command line): the
  ## corrected arguments if the answer is yes (with `-y` at once), none otherwise (`--no`: at once).  `terminal` and `key` are for tests.
  if ask(g, questionLines(g.leading, command, fix), true, fix.yOrN, terminal, key):
    some(fix.args)
  else:
    none(seq[string])

proc unitRetry*(
    g: Globals,
    command: string,
    fix: UnitFix,
    run: proc(g: Globals, args: seq[string]): int {.nimcall, raises: [].},
): int =
  ## What a command's `run` does for `pkUnit`: ask (`askUnit`, on the real terminal), then run again with the corrected
  ## arguments, or give the usage exit code.
  let again = askUnit(g, command, fix, isatty(stdin) and isatty(stderr), readKey)
  if again.isSome:
    run(g, again.get)
  else:
    exitUsage
