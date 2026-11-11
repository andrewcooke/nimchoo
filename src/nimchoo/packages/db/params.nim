## The command line of `nch db`, parsed.  Pure.

import ../confirm/confirm
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
      force*: Force ## really do it

  Raw = object ## what the options fill in
    help, delete: bool
    force: Force

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
      forceOption(Raw, force, 1),
      helpFlag(Raw),
    ]
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.force != fNo and not raw.delete:
    return problemWith[Params]("-f goes with --delete")
  if raw.delete:
    parsedOk(Params(action: daDelete, force: raw.force))
  else:
    parsedOk(Params(action: daShow))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch db`, `nch db --delete [-f]`.
  parseCommand(args, dbSpec(), Raw(), finish)
