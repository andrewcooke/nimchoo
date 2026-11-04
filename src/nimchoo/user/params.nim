## The command line of `nch user`, parsed.  Pure.

import ../cli/args
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
  makeDefault*: bool         ## make the user (new, or current) the default one
  rename*: string            ## the new name of the current user ("": no)
  remove*: bool              ## delete the current user and everything they have
  force*: bool               ## ... really
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

proc parseArgs*(args: seq[string]): Params =
  ## `nch user` (list), `--add NAME [--fthr N] [--default]`, `--fthr N`, `--clear-fthr`, `--rename NEW`, `--default`,
  ## `--remove -f`.
  let createOption = custom(Params, ["--add"], true):
    p.create = true
    p.name = value
    ""
  let fthrOption = custom(Params, ["--fthr"], true):
    p.fthr = parseFthr(value)
    if p.fthr.isNone:
      return "--fthr is a whole number of beats per minute, " & $minFthr & " to " & $maxFthr &
             " (not '" & value & "')"
    ""
  let renameOption = custom(Params, ["--rename"], true):
    if not validUserName(value):
      return "'" & value & "' is not a name for a user (1 to " & $maxNameLength &
             " letters, digits, _ . -, not starting with -)"
    p.rename = value
    ""
  let spec = Spec[Params](
    opts: @[
      flag(Params, ["-h", "--help"], help),
      createOption,
      flag(Params, ["--clear-fthr"], clearFthr),
      flag(Params, ["--default"], makeDefault),
      fthrOption,
      renameOption,
      flag(Params, ["--remove"], remove),
      flag(Params, ["-f", "--force"], force)],
    hint: proc(arg: string): string {.nimcall, raises: [].} =
      " (to make a user: --add " & arg & "; to change an existing user: `nch --user " & arg &
      " user ...`)")
  template fail(msg: string) =
    result.problem = msg
    return
  let why = parseOptions(args, spec, result)
  if why.len > 0: fail(why)
  if result.help: return
  if result.create:
    if not validUserName(result.name):
      fail("'" & result.name & "' is not a name for a user (1 to " & $maxNameLength &
           " letters, digits, _ . -, not starting with -)")
    if result.rename.len > 0 or result.clearFthr:
      fail("--add can be combined only with --fthr and --default")
  if result.fthr.isSome and result.clearFthr:
    fail("--fthr and --clear-fthr cannot be used together")
  if result.force and not result.remove: fail("-f goes with --remove")
  if result.remove and (result.create or result.fthr.isSome or result.clearFthr or
                        result.makeDefault or result.rename.len > 0):
    fail("--remove cannot be combined with the other options (only -f)")
  result.list = not result.create and result.fthr.isNone and not result.clearFthr and
                result.rename.len == 0 and not result.makeDefault and not result.remove
