## The command line of `nch users`, parsed.  Pure.

import ../util/args/args
import std/[options, sequtils, strutils]

{.push raises: [].}

const
  minFthr* = 80
  maxFthr* = 230
  maxNameLength* = 32

type
  UserAction* = enum
    uaList ## show the users
    uaAdd
    uaEdit
    uaDelete

  FthrKind* = enum
    fkKeep
    fkSet
    fkClear

  FthrChange* = object ## what to do to the threshold heart rate
    case kind*: FthrKind
    of fkSet:
      bpm*: int
    of fkKeep, fkClear:
      discard

  NewUser* = object
    name*: string
    fthr*: Option[int]
    makeDefault*: bool

  EditUser* = object ## `--edit NAME`: at least one change
    name*: string
    fthr*: FthrChange
    rename*: Option[string]
    makeDefault*: bool

  DeleteUser* = object
    name*: string
    force*: bool ## really do it

  Params* = object
    case action*: UserAction
    of uaList:
      discard
    of uaAdd:
      add*: NewUser
    of uaEdit:
      edit*: EditUser
    of uaDelete:
      delete*: DeleteUser

  Raw = object ## what the options fill in
    help, makeDefault, clearFthr, force: bool
    adding, editing, deleting: bool
    name, rename: string
    fthr: Option[int]

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

const notAName = " letters, digits, _ . -, not starting with -)"

func userSpec*(): Spec[Raw] =
  ## The options of `nch users`; the options that change a user go with `--add` and `--edit`.
  Spec[Raw](
    opts: @[
      custom(
        Raw,
        ["--add"],
        true,
        "NAME",
        "make the user NAME (users are never made by accident: it must be asked for)",
        body = (p.adding = true; p.name = value; fine),
      ),
      custom(
        Raw,
        ["--edit"],
        true,
        "NAME",
        "change the user NAME, with one or more of:",
        body = (p.editing = true; p.name = value; fine),
      ),
      custom(
        Raw,
        ["--fthr"],
        true,
        "BPM",
        "the user's functional threshold heart rate: the highest rate they can sustain for about an hour (80 to 230).  Heart-rate zones, and so training impulse, are worked out from it.",
        level = 1,
        body = (
          block:
            p.fthr = parseFthr(value)
            if p.fthr.isNone:
              return refuse(
                "--fthr is a whole number of beats per minute, " & $minFthr & " to " &
                  $maxFthr & " (not '" & value & "')"
              )
            fine
        ),
      ),
      flag(Raw, ["--clear-fthr"], clearFthr, "forget it", level = 1),
      custom(
        Raw,
        ["--rename"],
        true,
        "NEW",
        "change the user's name",
        level = 1,
        body = (
          block:
            if not validUserName(value):
              return refuse(
                "'" & value & "' is not a name for a user (1 to " & $maxNameLength &
                  " letters, digits, _ . -, not starting with -)"
              )
            p.rename = value
            fine
        ),
      ),
      flag(
        Raw,
        ["--default"],
        makeDefault,
        "make the user the default: the one used when there is no --user",
        level = 1,
      ),
      custom(
        Raw,
        ["--delete"],
        true,
        "NAME",
        "delete the user and everything they have (files, activities, ...); if they were the default another user becomes it.  Needs -f; on a terminal there are then 5 seconds in which to press Ctrl-C.  (To keep the user and delete only their data: `nch activities --all --delete -f` with `--user NAME` before it.)",
        body = (p.deleting = true; p.name = value; fine),
      ),
      flag(Raw, ["-f", "--force"], force, "really do it", level = 1),
      helpFlag(Raw),
    ],
    hint: proc(arg: string): string {.nimcall, raises: [].} =
      " (to make a user: --add " & arg & "; to change one: --edit " & arg & ")",
  )

func finish(raw: Raw): Parsed[Params] =
  let modes = [raw.adding, raw.editing, raw.deleting]
  if modes.count(true) > 1:
    return problemWith[Params]("--add, --edit and --delete cannot be used together")
  let changes =
    raw.fthr.isSome or raw.clearFthr or raw.makeDefault or raw.rename.len > 0
  if raw.fthr.isSome and raw.clearFthr:
    return problemWith[Params]("--fthr and --clear-fthr cannot be used together")
  if raw.adding:
    if not validUserName(raw.name):
      return problemWith[Params](
        "'" & raw.name & "' is not a name for a user (1 to " & $maxNameLength & notAName
      )
    if raw.rename.len > 0 or raw.clearFthr:
      return problemWith[Params]("--add can be combined only with --fthr and --default")
  if raw.editing and not changes:
    return problemWith[Params](
      "--edit needs something to change: --fthr, --clear-fthr, --rename or --default"
    )
  if raw.deleting and changes:
    return problemWith[Params](
      "--delete cannot be combined with the other options (only -f)"
    )
  if changes and not (raw.adding or raw.editing):
    return problemWith[Params](
      "--fthr, --clear-fthr, --rename and --default go with --add NAME or --edit NAME"
    )
  if raw.force and not raw.deleting:
    return problemWith[Params]("-f goes with --delete")
  if raw.adding:
    parsedOk(
      Params(
        action: uaAdd,
        add: NewUser(name: raw.name, fthr: raw.fthr, makeDefault: raw.makeDefault),
      )
    )
  elif raw.editing:
    let fthr =
      if raw.fthr.isSome:
        FthrChange(kind: fkSet, bpm: raw.fthr.get)
      elif raw.clearFthr:
        FthrChange(kind: fkClear)
      else:
        FthrChange(kind: fkKeep)
    parsedOk(
      Params(
        action: uaEdit,
        edit: EditUser(
          name: raw.name,
          fthr: fthr,
          rename: (if raw.rename.len > 0: some(raw.rename)
          else: none(string)),
          makeDefault: raw.makeDefault,
        ),
      )
    )
  elif raw.deleting:
    parsedOk(
      Params(action: uaDelete, delete: DeleteUser(name: raw.name, force: raw.force))
    )
  else:
    parsedOk(Params(action: uaList))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch users` (list), `--add NAME [--fthr N] [--default]`,
  ## `--edit NAME` with `--fthr N`, `--clear-fthr`, `--rename NEW`, `--default`, `--delete NAME -f`.
  parseCommand(args, userSpec(), Raw(), finish)
