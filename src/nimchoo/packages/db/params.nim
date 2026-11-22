## The command line of `nch db`, parsed.  Pure.

import ../util/args/args

{.push raises: [].}

type
  DbAction* = enum
    daShow ## say where the database is, how big, and what it holds, table by table
    daDelete

  Params* = object
    case action*: DbAction
    of daShow, daDelete:
      discard

  Raw = object ## what the options fill in
    help, delete: bool

func dbSpec*(): Spec[Raw] =
  ## The options of `nch db`.
  Spec[Raw](
    opts: @[
      flag(
        Raw,
        ["--delete"],
        delete,
        ~"delete the database file, and with it the users and all their data: files, activities, climbs, landmarks, names.  (The cache survives, so nothing is downloaded again.  To delete less: `nch activities --all --delete` keeps the users, `nch climbs --all --delete` keeps the activities.)  The next command that needs a database makes a new one.",
      ),
      helpFlag(Raw),
    ]
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.delete:
    parsedOk(Params(action: daDelete))
  else:
    parsedOk(Params(action: daShow))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch db`, `nch db --delete`.
  parseCommand(args, dbSpec(), Raw(), finish)
