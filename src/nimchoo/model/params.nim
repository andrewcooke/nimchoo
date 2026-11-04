## The command line of `nch model`, parsed.  Pure.

import std/strutils
import ../cli/args
import ./calc

{.push raises: [].}

const maxNameLength* = 32

type Params* = object
  list*: bool
  add*: bool
  model*: Model              ## for `add`: the defaults, with what was given
  varsGiven: bool            ## some variable was given
  help*: bool
  problem*: string

func validModelName*(s: string): bool =
  ## 1 to 32 characters: letters, digits, `_`, `.` and `-` (not first).
  if s.len == 0 or s.len > maxNameLength or s[0] == '-': return false
  for c in s:
    if c notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '.', '-'}: return false
  true

template variable(nameList: openArray[string], field: untyped): Opt[Params] =
  ## A variable of the model: a number.
  custom(Params, nameList, true):
    var x = 0.0
    if not parseFloatIn(value, -1.0e12, 1.0e12, x): return valueIs(name, "a number", value)
    p.model.field = x
    p.varsGiven = true
    ""

const zonesWhat = "--zones is five percentages of the threshold heart rate, like 68,83,94,105,121"

proc parseArgs*(args: seq[string]): Params =
  ## `nch model` (list), `--add NAME` with any of the variables.
  result.model = defaultModel()
  let addOption = custom(Params, ["--add"], true):
    p.add = true
    if not validModelName(value):
      return "'" & value & "' is not a name for a model (1 to " & $maxNameLength &
             " letters, digits, _ . -, not starting with -)"
    p.model.name = value
    ""
  let maxSecsOption = custom(Params, ["--max-secs"], true):
    var n = 0
    try: n = parseInt(value)
    except ValueError: return valueIs(name, "a whole number of seconds", value)
    p.model.maxSecs = n
    p.varsGiven = true
    ""
  let zonesOption = custom(Params, ["--zones"], true):
    let parts = value.split(',')
    if parts.len != 5: return zonesWhat
    for k, part in parts:
      var x = 0.0
      if not parseFloatIn(part, -1.0e12, 1.0e12, x): return zonesWhat
      p.model.zones[k] = x
    p.varsGiven = true
    ""
  let spec = Spec[Params](
    opts: @[
      flag(Params, ["-h", "--help"], help),
      addOption,
      variable(["--gamma"], gamma),
      variable(["--zero"], zero),
      variable(["--one"], one),
      maxSecsOption,
      zonesOption,
      variable(["--fitness-days"], fitnessDays),
      variable(["--fatigue-days"], fatigueDays)],
    hint: proc(arg: string): string {.nimcall, raises: [].} = " (to add a model: --add " & arg & ")")
  template fail(msg: string) =
    result.problem = msg
    return
  let why = parseOptions(args, spec, result)
  if why.len > 0: fail(why)
  if result.help: return
  if result.varsGiven and not result.add: fail("the variables can be given only with --add NAME")
  if result.add:
    let why = problem(result.model)
    if why.len > 0: fail(why)
  result.list = not result.add
