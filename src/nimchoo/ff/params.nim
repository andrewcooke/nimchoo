## The command line of `nch ff`, parsed.  Pure.

import std/[options, strutils, times]
import ../cache
import ../serve/webopts

{.push raises: [].}

type Params* = object
  key*: string                   ## the key of the data to show ("": the current data)
  model*: string                 ## "": the default model
  fromDay*, toDay*: Option[int64]   ## a calendar date, as Unix seconds at its start in UTC (it is a day of the timezone used)
  hourly*: bool
  utc*: bool                     ## days and times in UTC, not the computer's timezone
  fitnessScale*, fatigueScale*: float
  stdout*: bool                  ## print the CSV, not write a file
  web*: WebArgs                  ## --worker, --web and what goes with it
  help*: bool
  problem*: string

proc parseDay*(s: string): Option[int64] =
  ## `2018-08-27`, as the start of that UTC day.
  if s.len != 10: return
  try:
    return some(parse(s, "yyyy-MM-dd", utc()).toTime.toUnix)
  except TimeParseError, ValueError:
    discard

proc parseArgs*(args: seq[string]): Params =
  result.web = initWebArgs()
  result.fitnessScale = 1
  result.fatigueScale = 1
  var i = 0
  template fail(msg: string) =
    result.problem = msg
    return
  template value(name: string): string =
    inc i
    if i >= args.len: fail(name & " needs a value")
    args[i]
  template scale(name: string, target: untyped) =
    let v = value(name)
    var x = 0.0
    try: x = parseFloat(v)
    except ValueError: fail(name & " is a number above 0 (not '" & v & "')")
    if not (x > 0 and x < 1.0e12): fail(name & " is a number above 0 (not '" & v & "')")
    target = x
  while i < args.len:
    let a = args[i]
    var issue = ""
    if takeWebOption(args, i, result.web, issue):
      if issue.len > 0: fail(issue)
      inc i
      continue
    case a
    of "-h", "--help": result.help = true
    of "--model": result.model = value(a)
    of "--from", "--to":
      let v = value(a)
      let d = parseDay(v)
      if d.isNone: fail(a & " is a day, like 2018-08-27 (not '" & v & "')")
      if a == "--from": result.fromDay = d else: result.toDay = d
    of "--hourly": result.hourly = true
    of "--utc": result.utc = true
    of "--stdout": result.stdout = true
    of "--key":
      let v = value(a)
      if not isOptionValue(v): fail("'" & v & "' is not a key of the data")
      result.key = v
    of "--fitness-scale": scale(a, result.fitnessScale)
    of "--fatigue-scale": scale(a, result.fatigueScale)
    else:
      if a.startsWith("-"): fail("unexpected option " & a)
      fail("unexpected argument " & a)
    inc i
  if result.fromDay.isSome and result.toDay.isSome and result.fromDay.get > result.toDay.get:
    fail("--from is after --to")
  if (result.web.enabled or result.web.worker) and result.stdout:
    fail("--stdout cannot be used with --web or --worker")
  let combination = webProblem(result.web)
  if combination.len > 0: fail(combination)
