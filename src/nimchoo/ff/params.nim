## The command line of `nch ff`, parsed.  Pure.

import std/[options, strutils, times]
import ../cache
import ../packages/util/args/args
import ../serve/webopts

{.push raises: [].}

type Params* = object
  check*: string
    ## the hash of the data that must still be the current ones ("": no check)
  model*: string ## "": the default model
  fromDay*, toDay*: Option[int64]
    ## a calendar date, as Unix seconds at its start in UTC (it is a day of the timezone used)
  hourly*: bool
  utc*: bool ## days and times in UTC, not the computer's timezone
  fitnessScale*, fatigueScale*: float
  stdout*: bool ## print the CSV, not write a file
  web*: WebArgs ## --worker, --web and what goes with it
  help*: bool
  problem*: string

proc parseDay*(s: string): Option[int64] =
  ## `2018-08-27`, as the start of that UTC day.
  if s.len != 10:
    return
  try:
    return some(parse(s, "yyyy-MM-dd", utc()).toTime.toUnix)
  except TimeParseError, ValueError:
    discard

func dayOption(names: openArray[string], toDay: bool): Opt[Params] =
  ## --from and --to: a day, kept in `fromDay` or `toDay`.
  if toDay:
    custom(Params, names, true):
      let d = parseDay(value)
      if d.isNone:
        return name & " is a day, like 2018-08-27 (not '" & value & "')"
      p.toDay = d
      ""
  else:
    custom(Params, names, true):
      let d = parseDay(value)
      if d.isNone:
        return name & " is a day, like 2018-08-27 (not '" & value & "')"
      p.fromDay = d
      ""

proc parseArgs*(args: seq[string]): Params =
  ## The options of `nch ff`; `problem` says what is wrong with them, if anything.
  result.web = initWebArgs()
  result.fitnessScale = 1
  result.fatigueScale = 1
  const positive = 5.0e-324 # (the smallest number above 0)
  const scaleText = "a number above 0"
  let checkOption = custom(Params, ["--check"], true):
    if not isOptionValue(value):
      return "'" & value & "' is not a hash of the data"
    p.check = value
    ""
  let spec = Spec[Params](
    opts:
      @[
        flag(Params, ["-h", "--help"], help),
        text(Params, ["--model"], model),
        dayOption(["--from"], false),
        dayOption(["--to"], true),
        flag(Params, ["--hourly"], hourly),
        flag(Params, ["--utc"], utc),
        flag(Params, ["--stdout"], stdout),
        checkOption,
        number(Params, ["--fitness-scale"], fitnessScale, positive, 1.0e12, scaleText),
        number(Params, ["--fatigue-scale"], fatigueScale, positive, 1.0e12, scaleText),
      ] & webOptions(Params, web)
  )
  template fail(msg: string) =
    result.problem = msg
    return

  let why = parseOptions(args, spec, result)
  if why.len > 0:
    fail(why)
  if result.fromDay.isSome and result.toDay.isSome and
      result.fromDay.get > result.toDay.get:
    fail("--from is after --to")
  if (result.web.enabled or result.web.worker) and result.stdout:
    fail("--stdout cannot be used with --web or --worker")
  let combination = webProblem(result.web)
  if combination.len > 0:
    fail(combination)
