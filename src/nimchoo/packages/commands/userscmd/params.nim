## The command line of `nch users`, parsed.  Pure.

import ../../util/args/args
import std/[options, sequtils, strutils]

{.push raises: [].}

const
  minFthr* = 80
  maxFthr* = 230
  maxNameLength* = 32

type Params* = object
  list*: bool ## show the users (nothing to change)
  create*: bool ## `--add`: make the user `name`
  edit*: bool ## `--edit`: change the user `name`
  delete*: bool ## `--delete`: delete the user `name` and everything they have
  name*: string ## the user the one of those three is about
  fthr*: Option[int] ## set the threshold heart rate (of the new user, or the one edited)
  clearFthr*: bool
  makeDefault*: bool ## make the user the default one
  rename*: string ## the new name of the user edited ("": no)
  force*: bool ## ... really (with --delete)
  help*: bool
  problem*: string

func validUserName*(s: string): bool =
  ## 1 to 32 characters: letters, digits, `_`, `.` and `-` (not first).  A name is used after
  ## `--user` and in comma-separated lists (`--users a,b`), so it holds nothing that would break either.
  if s.len == 0 or s.len > maxNameLength or s[0] == '-':
    return false
  for c in s:
    if c notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '.', '-'}:
      return false
  true

func parseFthr*(s: string): Option[int] =
  ## A whole number of bpm, 80 to 230.
  try:
    let n = parseInt(s)
    if n >= minFthr and n <= maxFthr:
      return some(n)
  except ValueError:
    discard
  none(int)

proc parseArgs*(args: seq[string]): Params =
  ## `nch users` (list), `--add NAME [--fthr N] [--default]`,
  ## `--edit NAME` with `--fthr N`, `--clear-fthr`, `--rename NEW`, `--default`, `--delete NAME -f`.
  let addOption = custom(Params, ["--add"], true):
    p.create = true
    p.name = value
    ""
  let editOption = custom(Params, ["--edit"], true):
    p.edit = true
    p.name = value
    ""
  let removeOption = custom(Params, ["--delete"], true):
    p.delete = true
    p.name = value
    ""
  let fthrOption = custom(Params, ["--fthr"], true):
    p.fthr = parseFthr(value)
    if p.fthr.isNone:
      return
        "--fthr is a whole number of beats per minute, " & $minFthr & " to " & $maxFthr &
        " (not '" & value & "')"
    ""
  let renameOption = custom(Params, ["--rename"], true):
    if not validUserName(value):
      return
        "'" & value & "' is not a name for a user (1 to " & $maxNameLength &
        " letters, digits, _ . -, not starting with -)"
    p.rename = value
    ""
  let spec = Spec[Params](
    opts: @[
      flag(Params, ["-h", "--help"], help),
      addOption,
      editOption,
      removeOption,
      flag(Params, ["--clear-fthr"], clearFthr),
      flag(Params, ["--default"], makeDefault),
      fthrOption,
      renameOption,
      flag(Params, ["-f", "--force"], force),
    ],
    hint: proc(arg: string): string {.nimcall, raises: [].} =
      " (to make a user: --add " & arg & "; to change one: --edit " & arg & ")",
  )
  template fail(msg: string) =
    result.problem = msg
    return

  let why = parseOptions(args, spec, result)
  if why.len > 0:
    fail(why)
  if result.help:
    return
  let modes = [result.create, result.edit, result.delete]
  if modes.count(true) > 1:
    fail("--add, --edit and --delete cannot be used together")
  let changes =
    result.fthr.isSome or result.clearFthr or result.makeDefault or result.rename.len > 0
  if result.create:
    if not validUserName(result.name):
      fail(
        "'" & result.name & "' is not a name for a user (1 to " & $maxNameLength &
          " letters, digits, _ . -, not starting with -)"
      )
    if result.rename.len > 0 or result.clearFthr:
      fail("--add can be combined only with --fthr and --default")
  if result.fthr.isSome and result.clearFthr:
    fail("--fthr and --clear-fthr cannot be used together")
  if result.edit and not changes:
    fail(
      "--edit needs something to change: --fthr, --clear-fthr, --rename or --default"
    )
  if result.delete and changes:
    fail("--delete cannot be combined with the other options (only -f)")
  if changes and not (result.create or result.edit):
    fail(
      "--fthr, --clear-fthr, --rename and --default go with --add NAME or --edit NAME"
    )
  if result.force and not result.delete:
    fail("-f goes with --delete")
  result.list = not (result.create or result.edit or result.delete)
