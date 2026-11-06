## The command line of `nch climbs`, parsed.  Pure.

import ../cli/args
import ./display
import std/[strutils, unicode]

{.push raises: [].}

const maxNameLength* = 60

type Params* = object
  all*: bool                 ## `--all`: every climb, not just those of the selected activities
  edit*: bool                ## `--edit`: change the climb `name`
  name*: string              ## the climb, as `nch climbs --all` shows it ("Morro La Cabra₁")
  rename*: string            ## the new name ("": no)
  auto*: bool                ## go back to the name the program makes
  retire*, unretire*: bool   ## `--retire` / `--unretire`: hide the climb from the lists / show it again
  retired*: bool             ## `--retired`: list the retired climbs
  duplicates*: bool          ## `--duplicates`: list the climbs that largely overlap
  delete*: bool              ## `--delete`: delete every climb and start again (with `--all`)
  force*: bool               ## `-f`: really (with --delete)
  listOnly*: bool            ## `--retired` or `--duplicates`: a list that needs no working out of climbs
  names*: seq[string]        ## `--name TEXT...`: the climbs whose name holds the text (all climbs, not the selection's)
  verbose*: bool            ## `-v`: list the attempts under each climb
  everyone*: bool           ## `--everyone`: the people's best times (the leaderboard) instead of the user's own attempts
  help*: bool
  problem*: string

func nameProblem*(s: string): string =
  ## "" if `s` can be the name of a climb, else what is wrong.
  let t = s.strip
  if t.len == 0: return "a name cannot be empty"
  if t.runeLen > maxNameLength: return "a name has at most " & $maxNameLength & " characters"
  for c in t:
    if c < ' ' or c == '\x7f': return "a name cannot hold control characters"
  if endsWithSubscript(t):
    return "a name cannot end in a subscript number: the program adds that itself when climbs share a name"
  ""

proc takeNames(p: var Params, name: string, values: seq[string]): string {.nimcall.} =
  for v in values:
    if v.strip.len == 0: return name & " needs some text"
    p.names.add v.strip
  if values.len == 0: return name & " needs some text"
  ""

proc parseArgs*(args: seq[string]): Params =
  ## `nch climbs` (the climbs of the selected activities), `--all`, `--retired`, `--duplicates`,
  ## `--delete --all -f`, `--edit NAME --rename NEW`, `--edit NAME --auto`, `--edit NAME --retire`, `--edit NAME --unretire`.
  let editOption = custom(Params, ["--edit"], true):
    p.edit = true
    p.name = value
    ""
  let renameOption = custom(Params, ["--rename"], true):
    p.rename = value.strip
    let why = nameProblem(value)
    if why.len > 0: return why
    ""
  let spec = Spec[Params](
    opts: @[
      flag(Params, ["-h", "--help"], help),
      editOption, renameOption,
      flag(Params, ["--auto"], auto),
      flag(Params, ["--retire"], retire), flag(Params, ["--unretire"], unretire),
      flag(Params, ["--retired"], retired), flag(Params, ["--duplicates"], duplicates),
      flag(Params, ["-v", "--verbose"], verbose), flag(Params, ["--everyone"], everyone),
      listOption[Params](["--name"], takeNames),
      flag(Params, ["--all"], all), flag(Params, ["--delete"], delete),
      flag(Params, ["-f", "--force"], force)],
    hint: proc(arg: string): string {.nimcall, raises: [].} =
      " (to change a climb: --edit " & arg & " --rename NEW, --auto, --retire or --unretire)")
  template fail(msg: string) =
    result.problem = msg
    return
  let why = parseOptions(args, spec, result)
  if why.len > 0: fail(why)
  if result.help: return
  let changes = (if result.rename.len > 0: 1 else: 0) + (if result.auto: 1 else: 0) +
                (if result.retire: 1 else: 0) + (if result.unretire: 1 else: 0)
  if result.edit:
    if result.name.strip.len == 0: fail("--edit needs the name of a climb, as `nch climbs --all` shows it")
    if changes == 0: fail("--edit needs something to change: --rename NEW, --auto, --retire or --unretire")
    if changes > 1: fail("--rename, --auto, --retire and --unretire cannot be used together")
    if result.retired or result.duplicates or result.all:
      fail("--all, --retired and --duplicates list climbs: they do not go with --edit")
  elif changes > 0:
    fail("--rename, --auto, --retire and --unretire go with --edit NAME")
  if (if result.retired: 1 else: 0) + (if result.duplicates: 1 else: 0) + (if result.all: 1 else: 0) > 1:
    fail("--all, --retired and --duplicates cannot be used together")
  if result.force and not result.delete: fail("-f goes with --delete")
  if result.delete:
    if not result.all: fail("--delete needs --all: the climbs are never deleted one at a time (to hide one: --edit NAME --retire)")
    if result.edit or result.retired or result.duplicates: fail("--delete does not go with --edit, --retired or --duplicates")
  if result.names.len > 0 and (result.all or result.edit or result.delete or result.retired or result.duplicates):
    fail("--name chooses the climbs to show: it does not go with --all, --edit, --delete, --retired or --duplicates")
  if (result.verbose or result.everyone) and (result.all or result.edit or result.delete or result.retired or result.duplicates):
    fail("-v and --everyone go with the attempts: `nch climbs` (or `--name TEXT`) shows them")
  result.listOnly = result.retired or result.duplicates
