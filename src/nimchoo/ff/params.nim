## The command line of `nch ff`, parsed.  Pure.

import std/[options, strutils, times]

{.push raises: [].}

type Params* = object
  model*: string                 ## "": the default model
  fromDay*, toDay*: Option[int64]   ## Unix seconds at the start of the (UTC) day
  hourly*: bool
  fitnessScale*, fatigueScale*: float
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
    case a
    of "-h", "--help": result.help = true
    of "--model": result.model = value(a)
    of "--from", "--to":
      let v = value(a)
      let d = parseDay(v)
      if d.isNone: fail(a & " is a day, like 2018-08-27 (not '" & v & "')")
      if a == "--from": result.fromDay = d else: result.toDay = d
    of "--hourly": result.hourly = true
    of "--fitness-scale": scale(a, result.fitnessScale)
    of "--fatigue-scale": scale(a, result.fatigueScale)
    else:
      if a.startsWith("-"): fail("unexpected option " & a)
      fail("unexpected argument " & a)
    inc i
  if result.fromDay.isSome and result.toDay.isSome and result.fromDay.get > result.toDay.get:
    fail("--from is after --to")
