## The command line of `nch log`, parsed.  Pure.

import std/[options, strutils]
import ../../core/logfile
import ../ui/vocabulary
import ../util/args/args
import ./lines

{.push raises: [].}

type
  Params* = object
    filter*: Filter ## the commands and events to show, the last run, how many lines

  Raw = object ## what the options and words fill in
    help: bool
    known: seq[string] ## the names of the commands there are
    filter: Filter

proc names(commands: seq[string]): string =
  var es: seq[string]
  for e in LogEvent:
    es.add $e
  "commands: " & commands.join(" ") & "; events: " & es.join(" ")

proc takeLogName(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
  ## A word that names an event or a command to show.
  let e = parseEvent(arg)
  if e.isSome:
    p.filter.events.incl e.get
  elif arg in p.known:
    p.filter.commands.add arg
  else:
    return
      refuse("'" & arg & "' is neither a command nor an event (" & names(p.known) & ")")
  fine

func logSpec*(): Spec[Raw] =
  ## The options of `nch log`; the words that name commands and events are the positional arguments.
  Spec[Raw](
    opts: @[
      custom(
        Raw,
        ["--last"],
        false,
        "",
        "only the latest run of the commands (or of any command): from its \"run\" line to the end",
        body = (p.filter.last = true; fine),
      ),
      custom(
        Raw,
        ["-n"],
        true,
        "N",
        "only the last N lines",
        body = (
          block:
            var n = 0
            if not parseIntIn(value, 1, high(int), n):
              return refuse("-n needs a number of lines, 1 or more")
            p.filter.count = n
            fine
        ),
      ),
      helpFlag(Raw),
    ],
    positional: takeLogName,
  )

func finish(raw: Raw): Parsed[Params] =
  parsedOk(Params(filter: raw.filter))

proc parseArgs*(args: seq[string], commands: seq[string]): Parsed[Params] =
  ## The words and options of `nch log`; `commands` are the names of the commands there are, which can be used as
  ## filters.
  parseCommand(args, logSpec(), Raw(known: commands), finish)
