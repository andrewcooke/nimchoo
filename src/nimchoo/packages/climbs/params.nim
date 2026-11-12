## The command line of `nch climbs`, parsed.  Pure.

import ../confirm/confirm
import ../util/args/args
import ./completion
import ./[display, match]
import std/[strformat, strutils, unicode]

{.push raises: [].}

const maxNameLength* = 60

type
  ClimbAction* = enum
    caSelected ## the climbs of the selected activities
    caNamed ## the climbs whose names hold some text
    caAll ## every climb found
    caEdit ## change one climb
    caRetired ## list the retired climbs
    caDuplicates ## list the climbs that largely overlap
    caDeleteAll ## delete every climb and start again

  Attempts* = object ## how a list of climbs shows the attempts
    verbose*: bool ## list the attempts under each climb
    everyone*: bool ## the people's best times instead of the user's own attempts

  ByName* = object
    names*: seq[string] ## the climbs whose name holds any of these texts
    attempts*: Attempts

  ChangeKind* = enum
    ckRename
    ckAuto
    ckRetire
    ckUnretire

  Change* = object ## the one thing to do to a climb
    case kind*: ChangeKind
    of ckRename:
      newName*: string
    of ckAuto, ckRetire, ckUnretire:
      discard

  Edit* = object
    climb*: string ## as `nch climbs --all` shows it ("Morro La Cabra₁")
    change*: Change

  Params* = object
    case action*: ClimbAction
    of caSelected:
      selected*: Attempts
    of caNamed:
      named*: ByName
    of caEdit:
      edit*: Edit
    of caDeleteAll:
      force*: Force ## really do it
    of caAll, caRetired, caDuplicates:
      discard

  Raw = object ## what the options fill in
    help, all, editing, auto, retire, unretire, retired, duplicates, delete: bool
    force: Force
    verbose, everyone: bool
    name, rename: string
    names: seq[string]

func nameProblem*(s: string): string =
  ## "" if `s` can be the name of a climb, else what is wrong.
  let t = s.strip
  if t.len == 0:
    return "a name cannot be empty"
  if t.runeLen > maxNameLength:
    return fmt"a name has at most {maxNameLength} characters"
  for c in t:
    if c < ' ' or c == '\x7f':
      return "a name cannot hold control characters"
  if endsWithSubscript(t):
    return
      "a name cannot end in a subscript number: the program adds that itself when climbs share a name"
  ""

proc takeNames(p: var Raw, name: string, values: seq[string]): Problem {.nimcall.} =
  for v in values:
    if v.strip.len == 0:
      return refuse(fmt"{name} needs some text")
    p.names.add v.strip
  if values.len == 0:
    return refuse(fmt"{name} needs some text")
  fine

func climbSpec*(): Spec[Raw] =
  ## The options of `nch climbs`: the options that change a climb go under `--edit`.
  Spec[Raw](
    opts: @[
      listOption[Raw](
        ["--names"],
        takeNames,
        "TEXT...",
        "the climbs whose name holds any of the texts (case and accents do not matter; the number counts: `--names farellones₂`, which `--names \"farellones 2\"` also means), among all the climbs, not those of the selected rides; a whole number that no name holds is a climb's number (`--names 62`)",
      ),
      flag(
        Raw,
        ["-v", "--verbose"],
        verbose,
        "list the attempts under each climb, the fastest first, each with its rank (those of the selected rides in blue)",
      ),
      flag(
        Raw,
        ["--everyone"],
        everyone,
        "the people instead of your attempts: how many have ridden each climb, the fastest and who, and where your best time comes among everyone's best times (\"4 of 6\"); with -v each person's best.  (The personal rank and this one are never shown together.)",
      ),
      flag(
        Raw,
        ["--all"],
        all,
        "just the climbs found, the biggest first: category, length, height gained and gradient, how many times it has been ridden, and \"manual\" against a name given by a person",
      ),
      flag(
        Raw,
        ["--delete"],
        delete,
        "(with --all) delete every climb found, with the efforts on them (of every user), and start again: the next `nch climbs` works them out again from the rides.  Names given by hand are lost (the message says how many).  Needs -f.  The climbs are never deleted one at a time: `--edit NAME --retire` hides one",
        level = 1,
      ),
      forceOption(Raw, force, 2),
      custom(
        Raw,
        ["--edit"],
        true,
        "NAME",
        "change that climb, with one of the following.  NAME is a climb's name as `--all` shows it, its number included where several share a name: \"Morro La Cabra₁\" (\"Morro La Cabra 1\" and \"Morro La Cabra1\" do as well).  The number is kept: it never changes",
        completion = completesFrom(completeClimbNames),
        body = (p.editing = true; p.name = value; fine),
      ),
      custom(
        Raw,
        ["--rename"],
        true,
        "NEW",
        "give it the name NEW (any words; at most 60 characters; not ending in a subscript number, which the program adds when climbs share a name).  The name is kept: the program never changes it.  Several climbs may have the same name",
        level = 1,
        body = (
          block:
            p.rename = value.strip
            let why = nameProblem(value)
            if why.len > 0:
              return refuse(why)
            fine
        ),
      ),
      flag(
        Raw,
        ["--auto"],
        auto,
        "forget the name; it is named again at once from the places near it (or by the next `nch climbs` if the names cannot be had)",
        level = 1,
      ),
      flag(
        Raw,
        ["--retire"],
        retire,
        "hide the climb from the lists, as a segment can be hidden on Strava.  Nothing is deleted: it keeps its efforts, still takes those of new rides, and keeps its number, so the gap shows",
        level = 1,
      ),
      flag(Raw, ["--unretire"], unretire, "show it again", level = 1),
      flag(Raw, ["--retired"], retired, "list the retired climbs"),
      flag(
        Raw,
        ["--duplicates"],
        duplicates,
        fmt"list the climbs that largely overlap (more than half of each lies within {int(gateRadius)}m of the other), the most ridden first, with the command to hide each of the others",
      ),
      helpFlag(Raw),
    ],
    hint: proc(arg: string): string {.nimcall, raises: [].} =
      fmt" (to change a climb: --edit {arg} --rename NEW, --auto, --retire or --unretire)",
  )

func finish(raw: Raw): Parsed[Params] =
  func bad(why: string): Parsed[Params] =
    problemWith[Params](why)

  let changes =
    (if raw.rename.len > 0: 1 else: 0) + (if raw.auto: 1 else: 0) +
    (if raw.retire: 1 else: 0) + (if raw.unretire: 1 else: 0)
  if raw.editing:
    if raw.name.strip.len == 0:
      return bad("--edit needs the name of a climb, as `nch climbs --all` shows it")
    if changes == 0:
      return bad(
        "--edit needs something to change: --rename NEW, --auto, --retire or --unretire"
      )
    if changes > 1:
      return bad("--rename, --auto, --retire and --unretire cannot be used together")
    if raw.retired or raw.duplicates or raw.all:
      return
        bad("--all, --retired and --duplicates list climbs: they do not go with --edit")
  elif changes > 0:
    return bad("--rename, --auto, --retire and --unretire go with --edit NAME")
  if (if raw.retired: 1 else: 0) + (if raw.duplicates: 1 else: 0) +
      (if raw.all: 1 else: 0) > 1:
    return bad("--all, --retired and --duplicates cannot be used together")
  if raw.force != fNo and not raw.delete:
    return bad("-f goes with --delete")
  if raw.delete:
    if not raw.all:
      return bad(
        "--delete needs --all: the climbs are never deleted one at a time (to hide one: --edit NAME --retire)"
      )
    if raw.editing or raw.retired or raw.duplicates:
      return bad("--delete does not go with --edit, --retired or --duplicates")
  let listing = raw.all or raw.editing or raw.delete or raw.retired or raw.duplicates
  if raw.names.len > 0 and listing:
    return bad(
      "--names chooses the climbs to show: it does not go with --all, --edit, --delete, --retired or --duplicates"
    )
  if (raw.verbose or raw.everyone) and listing:
    return bad(
      "-v and --everyone go with the attempts: `nch climbs` (or `--names TEXT`) shows them"
    )
  let attempts = Attempts(verbose: raw.verbose, everyone: raw.everyone)
  if raw.delete:
    parsedOk(Params(action: caDeleteAll, force: raw.force))
  elif raw.editing:
    let change =
      if raw.rename.len > 0:
        Change(kind: ckRename, newName: raw.rename)
      elif raw.auto:
        Change(kind: ckAuto)
      elif raw.retire:
        Change(kind: ckRetire)
      else:
        Change(kind: ckUnretire)
    parsedOk(Params(action: caEdit, edit: Edit(climb: raw.name, change: change)))
  elif raw.retired:
    parsedOk(Params(action: caRetired))
  elif raw.duplicates:
    parsedOk(Params(action: caDuplicates))
  elif raw.all:
    parsedOk(Params(action: caAll))
  elif raw.names.len > 0:
    parsedOk(
      Params(action: caNamed, named: ByName(names: raw.names, attempts: attempts))
    )
  else:
    parsedOk(Params(action: caSelected, selected: attempts))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch climbs` (the climbs of the selected activities), `--all`, `--retired`, `--duplicates`,
  ## `--delete --all -f`, `--edit NAME --rename NEW`, `--edit NAME --auto`, `--edit NAME --retire`, `--edit NAME --unretire`.
  parseCommand(args, climbSpec(), Raw(), finish)
