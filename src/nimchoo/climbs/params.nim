## The command line of `nch climbs`, parsed.  Pure.

import ../cli/args
import std/[strutils, unicode]

{.push raises: [].}

const maxNameLength* = 60

type Params* = object
  all*: bool                 ## `--all`: every climb, not just those of the selected activities
  edit*: bool                ## `--edit`: change the climb `name`
  name*: string              ## the climb, as `nch climbs --all` shows it ("Morro La Cabra (1/3)")
  rename*: string            ## the new name ("": no)
  auto*: bool                ## go back to the name the program makes
  retire*, unretire*: bool   ## `--retire` / `--unretire`: hide the climb from the lists / show it again
  retired*: bool             ## `--retired`: list the retired climbs
  duplicates*: bool          ## `--duplicates`: list the climbs that largely overlap
  listOnly*: bool            ## `--retired` or `--duplicates`: a list that needs no working out of climbs
  help*: bool
  problem*: string

func looksNumbered*(s: string): bool =
  ## Ends in " (n/m)": the form the program adds to names that are shared, so a name given by a person
  ## must not, or `--edit` could not tell which climb is meant.
  if not s.endsWith(")"): return false
  let open = s.rfind(" (")
  if open < 0: return false
  let inside = s[open + 2 ..< s.high]
  let parts = inside.split('/')
  if parts.len != 2: return false
  for part in parts:
    if part.len == 0: return false
    for c in part:
      if c notin {'0' .. '9'}: return false
  true

func nameProblem*(s: string): string =
  ## "" if `s` can be the name of a climb, else what is wrong.
  let t = s.strip
  if t.len == 0: return "a name cannot be empty"
  if t.runeLen > maxNameLength: return "a name has at most " & $maxNameLength & " characters"
  for c in t:
    if c < ' ' or c == '\x7f': return "a name cannot hold control characters"
  if looksNumbered(t):
    return "a name cannot end in (n/m): the program adds that itself when climbs share a name"
  ""

proc parseArgs*(args: seq[string]): Params =
  ## `nch climbs` (the climbs of the selected activities), `--all`, `--retired`, `--duplicates`,
  ## `--edit NAME --rename NEW`, `--edit NAME --auto`, `--edit NAME --retire`, `--edit NAME --unretire`.
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
      flag(Params, ["--all"], all)],
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
  result.listOnly = result.retired or result.duplicates
