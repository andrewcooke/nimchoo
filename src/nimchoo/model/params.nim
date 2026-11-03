## The command line of `nch model`, parsed.  Pure.

import std/strutils
import ./calc

{.push raises: [].}

const maxNameLength* = 32

type Params* = object
  list*: bool
  add*: bool
  model*: Model              ## for `add`: the defaults, with what was given
  help*: bool
  problem*: string

func validModelName*(s: string): bool =
  ## 1 to 32 characters: letters, digits, `_`, `.` and `-` (not first).
  if s.len == 0 or s.len > maxNameLength or s[0] == '-': return false
  for c in s:
    if c notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '.', '-'}: return false
  true

func number(text: string, ok: var bool): float =
  try: result = parseFloat(text)
  except ValueError: ok = false

func parseArgs*(args: seq[string]): Params =
  ## `nch model` (list), `--add NAME` with any of the variables.
  result.model = defaultModel()
  var i = 0
  var given = false              ## some variable was given
  template fail(msg: string) =
    result.problem = msg
    return
  template value(name: string): string =
    inc i
    if i >= args.len: fail(name & " needs a value")
    args[i]
  template num(name: string, target: untyped,) =
    let v = value(name)
    var ok = true
    let x = number(v, ok)
    if not ok or x != x or abs(x) > 1.0e12: fail(name & " is a number (not '" & v & "')")
    target = x
    given = true
  while i < args.len:
    let a = args[i]
    case a
    of "-h", "--help": result.help = true
    of "--add":
      result.add = true
      let v = value(a)
      if not validModelName(v):
        fail("'" & v & "' is not a name for a model (1 to " & $maxNameLength &
             " letters, digits, _ . -, not starting with -)")
      result.model.name = v
    of "--gamma": num(a, result.model.gamma)
    of "--zero": num(a, result.model.zero)
    of "--one": num(a, result.model.one)
    of "--max-secs":
      let v = value(a)
      try: result.model.maxSecs = parseInt(v)
      except ValueError: fail("--max-secs is a whole number of seconds (not '" & v & "')")
      given = true
    of "--zones":
      let v = value(a)
      let parts = v.split(',')
      if parts.len != 5: fail("--zones is five percentages of the threshold heart rate, like 68,83,94,105,121")
      for k, p in parts:
        var ok = true
        let x = number(p, ok)
        if not ok or x != x or abs(x) > 1.0e12:
          fail("--zones is five percentages of the threshold heart rate, like 68,83,94,105,121")
        result.model.zones[k] = x
      given = true
    of "--fitness-days": num(a, result.model.fitnessDays)
    of "--fatigue-days": num(a, result.model.fatigueDays)
    else:
      if a.startsWith("-"): fail("unexpected option " & a)
      fail("unexpected argument " & a & " (to add a model: --add " & a & ")")
    inc i
  if result.help: return
  if given and not result.add: fail("the variables can be given only with --add NAME")
  if result.add:
    let why = problem(result.model)
    if why.len > 0: fail(why)
  result.list = not result.add
