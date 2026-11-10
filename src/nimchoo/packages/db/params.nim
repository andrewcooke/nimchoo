## The command line of `nch db`, parsed.  Pure.

import ../util/args/args

{.push raises: [].}

type
  DbAction* = enum
    daShow ## say where the database is and how big
    daDelete

  Params* = object
    case action*: DbAction
    of daShow:
      discard
    of daDelete:
      force*: bool ## really do it

  Raw = object ## what the options fill in
    help, delete, force: bool

func dbSpec*(): Spec[Raw] =
  ## The options of `nch db`.
  Spec[Raw](
    opts: @[
      flag(
        Raw,
        ["--delete"],
        delete,
        "delete the database file, and with it the users and all their data: files, activities, climbs, landmarks, names.  (The cache survives, so nothing is downloaded again.  To delete less: `nch activities --all --delete -f` keeps the users, `nch climbs --all --delete -f` keeps the activities.)  The next command that needs a database makes a new one.",
      ),
      flag(
        Raw,
        ["-f", "--force"],
        force,
        "really do it: on a terminal there are then 5 seconds in which to press Ctrl-C",
        level = 1,
      ),
      helpFlag(Raw),
    ]
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.force and not raw.delete:
    return problemWith[Params]("-f goes with --delete")
  if raw.delete:
    parsedOk(Params(action: daDelete, force: raw.force))
  else:
    parsedOk(Params(action: daShow))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch db`, `nch db --delete [-f]`.
  parseCommand(args, dbSpec(), Raw(), finish)
