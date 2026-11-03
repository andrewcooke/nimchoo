## The command line of `nch user`, parsed.  Pure.

import std/[options, strutils]

{.push raises: [].}

const
  minFthr* = 80
  maxFthr* = 230
  maxNameLength* = 32

type Params* = object
  list*: bool                ## show the users (nothing to change)
  create*: bool              ## make the user `name`
  name*: string              ## the user to make
  fthr*: Option[int]         ## set the threshold heart rate (of the current user, or of the new one)
  clearFthr*: bool
  rename*: string            ## the new name of the current user ("": no)
  help*: bool
  problem*: string

func validUserName*(s: string): bool =
  ## 1 to 32 characters: letters, digits, `_`, `.` and `-` (not first).  A name is used after
  ## `--user` and in comma-separated lists (`--users a,b`), so it holds nothing that would break either.
  if s.len == 0 or s.len > maxNameLength or s[0] == '-': return false
  for c in s:
    if c notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '.', '-'}: return false
  true

func parseFthr*(s: string): Option[int] =
  ## A whole number of bpm, 80 to 230.
  try:
    let n = parseInt(s)
    if n >= minFthr and n <= maxFthr: return some(n)
  except ValueError:
    discard
  none(int)

func parseArgs*(args: seq[string]): Params =
  ## `nch user` (list), `--create NAME [--fthr N]`, `--fthr N`, `--clear-fthr`, `--rename NEW`.
  var i = 0
  template fail(msg: string) =
    result.problem = msg
    return
  template value(name: string): string =
    inc i
    if i >= args.len: fail(name & " needs a value")
    args[i]
  while i < args.len:
    let a = args[i]
    case a
    of "-h", "--help": result.help = true
    of "--create":
      result.create = true
      result.name = value(a)
    of "--clear-fthr": result.clearFthr = true
    of "--fthr":
      let v = value(a)
      result.fthr = parseFthr(v)
      if result.fthr.isNone:
        fail("--fthr is a whole number of beats per minute, " & $minFthr & " to " & $maxFthr &
             " (not '" & v & "')")
    of "--rename":
      let v = value(a)
      if not validUserName(v):
        fail("'" & v & "' is not a name for a user (1 to " & $maxNameLength &
             " letters, digits, _ . -, not starting with -)")
      result.rename = v
    else:
      if a.startsWith("-"): fail("unexpected option " & a)
      fail("unexpected argument " & a & " (to make a user: --create " & a &
           "; to change an existing user: `nch --user " & a & " user ...`)")
    inc i
  if result.help: return
  if result.create:
    if not validUserName(result.name):
      fail("'" & result.name & "' is not a name for a user (1 to " & $maxNameLength &
           " letters, digits, _ . -, not starting with -)")
    if result.rename.len > 0 or result.clearFthr:
      fail("--create can be combined only with --fthr")
  if result.fthr.isSome and result.clearFthr:
    fail("--fthr and --clear-fthr cannot be used together")
  result.list = not result.create and result.fthr.isNone and not result.clearFthr and
                result.rename.len == 0
