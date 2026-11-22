## The command line of `nch models`, parsed.  Pure.

import std/[math, options, strutils]
import ../util/args/args
import ../ui/units
import ./calc

{.push raises: [].}

const maxNameLength* = 32

type
  ModelAction* = enum
    maList ## show the models
    maAdd

  Params* = object
    case action*: ModelAction
    of maList:
      discard
    of maAdd:
      model*: Model ## the defaults, with what was given

  Raw = object ## what the options fill in
    help, add, varsGiven: bool
    model: Model

func validModelName*(s: string): bool =
  ## 1 to 32 characters: letters, digits, `_`, `.` and `-` (not first, and no `--`: the name is a part of the file
  ## names `ff` makes, where `--` separates the options).
  if s.len == 0 or s.len > maxNameLength or s[0] == '-' or "--" in s:
    return false
  for c in s:
    if c notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '.', '-'}:
      return false
  true

template variable(
    nameList: openArray[string], field: untyped, metavar: string, help: Line
): Opt[Raw] =
  ## A variable of the model: a number, given with `--add`.
  custom(
    Raw,
    nameList,
    true,
    metavar,
    help,
    level = 1,
    body = (
      block:
        var x = 0.0
        if not parseFloatIn(value, -1.0e12, 1.0e12, x):
          return valueIs(name, "a number", value)
        p.model.field = x
        p.varsGiven = true
        fine
    ),
  )

func takeDecay(days: var float, name, value: string, given: var bool): Problem =
  ## A decay time: a duration with its unit, kept in days.
  let t = parseTimeSpan(value)
  if t.isNone:
    return valueIs(name, "a duration with its unit (`42d`, `36h`)", value)
  days = t.get.inDays
  given = true
  fine

const zonesWhat =
  ~"`--zones` is five percentages of the threshold heart rate, like 68,83,94,105,121"

func modelSpec*(): Spec[Raw] =
  ## The options of `nch models`.
  Spec[Raw](
    opts: @[
      custom(
        Raw,
        ["--add"],
        true,
        "NAME",
        ~"make a model called NAME",
        body = (
          block:
            p.add = true
            if not validModelName(value):
              return refuse(
                ~"'{value}' is not a name for a model (1 to {maxNameLength} letters, digits, _ . -, not starting with - and without --)"
              )
            p.model.name = value
            fine
        ),
      ),
      variable(
        ["--gamma"],
        gamma,
        "G",
        ~"the power in impulse = ((zone - ZERO) / (ONE - ZERO)) ^ G  (default 2)",
      ),
      variable(["--zero"], zero, "Z", ~"the zone with no impulse (default 1)"),
      variable(
        ["--one"], one, "O", ~"the zone with an impulse of 1 per 10 seconds (default 6)"
      ),
      custom(
        Raw,
        ["--max-gap"],
        true,
        "DURATION",
        ~"the longest gap in heart rate that is bridged, with its unit (default 60s; `2m`; whole seconds; a bare number is taken as seconds, after asking)",
        level = 1,
        body = (
          block:
            let t = parseTimeSpan(value)
            if t.isNone or t.get.inSeconds != floor(t.get.inSeconds):
              return valueIs(
                name, "a duration in whole seconds with its unit (`60s`, `2m`)", value
              )
            p.model.maxSecs = int(t.get.inSeconds)
            p.varsGiven = true
            fine
        ),
      )
        .withUnit("s"),
      custom(
        Raw,
        ["--zones"],
        true,
        "A,B,C,D,E",
        ~"the upper limits of zones 1 to 5, as percentages of the user's threshold heart rate (default 68,83,94,105,121)",
        level = 1,
        body = (
          block:
            let parts = value.split(',')
            if parts.len != 5:
              return refuse(zonesWhat)
            for k, part in parts:
              var x = 0.0
              if not parseFloatIn(part, -1.0e12, 1.0e12, x):
                return refuse(zonesWhat)
              p.model.zones[k] = x
            p.varsGiven = true
            fine
        ),
      ),
      custom(
        Raw,
        ["--fitness-decay"],
        true,
        "DURATION",
        ~"the decay time of the fitness curve, with its unit (default 42d; a bare number is taken as days, after asking)",
        level = 1,
        body = takeDecay(p.model.fitnessDays, name, value, p.varsGiven),
      )
        .withUnit("d"),
      custom(
        Raw,
        ["--fatigue-decay"],
        true,
        "DURATION",
        ~"the decay time of the fatigue curve, with its unit (default 7d; a bare number is taken as days, after asking)",
        level = 1,
        body = takeDecay(p.model.fatigueDays, name, value, p.varsGiven),
      )
        .withUnit("d"),
      helpFlag(Raw),
    ],
    hint: proc(arg: string): Line {.nimcall, raises: [].} =
      ~" (to add a model: `--add {arg}`)",
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.varsGiven and not raw.add:
    return problemWith[Params](~"the variables can be given only with `--add NAME`")
  if not raw.add:
    return parsedOk(Params(action: maList))
  let why = problem(raw.model)
  if why.len > 0:
    return problemWith[Params](plain(why))
  parsedOk(Params(action: maAdd, model: raw.model))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch models` (list), `--add NAME` with any of the variables.
  parseCommand(args, modelSpec(), Raw(model: defaultModel()), finish)
