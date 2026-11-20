## The command line of `nch climbs`, parsed.  Pure.  With no criteria it lists the climbs selection; criteria (or `--all`)
## search every climb, and `--select` keeps what they find as the selection, as `nch activities` does.

import ../geo/position
import ../confirm/confirm
import ../util/args/args
import ./completion
import ./[display, match, overlap]
import std/[math, options, strformat, strutils, unicode]

{.push raises: [].}

const
  maxNameLength* = 60
  defaultStartKm* = 10.0 ## for `--from`: a climb starts within this of the point
  defaultPassKm* = 1.0 ## for `--near`: a climb's line comes this close to the point
  categoryNames* = ["HC", "1", "2", "3", "4"] ## as the database has them

type
  ClimbAction* = enum
    caList ## list climbs: the selection, or those the criteria find
    caEdit ## change one climb
    caRetired ## list the retired climbs
    caDuplicates ## list the climbs that largely overlap
    caDeleteAll ## delete every climb and start again

  Attempts* = object ## how a list of climbs shows the attempts
    verbose*: bool ## list the attempts under each climb
    everyone*: bool ## the people's best times instead of the user's own attempts

  NearKind* = enum
    nrPoint ## a position
    nrPlace ## a place by its name, found when the command runs (`names/places`)

  Near* = object ## where `--from` or `--near` says
    case kind*: NearKind
    of nrPoint:
      lat*, lon*: float
    of nrPlace:
      place*: string

  ClimbCriteria* = object
    ## which climbs: each criterion given narrows them (all of them, with `--invert`, widen)
    names*: seq[string] ## whose name holds any of these texts
    ridden*: bool ## that the selected activities went up
    start*: Option[Near] ## that start near a point (`--from`)
    passes*: Option[Near] ## whose line passes near a point (`--near`)
    radiusKm*: Option[float] ## `--radius` (none: each its default)
    categories*: seq[string] ## of these categories (`categoryNames`)
    invert*: bool ## those the others do NOT find

  ListKind* = enum
    lkSelection ## the climbs selection
    lkFound ## every climb, or those that the criteria find

  Listing* = object ## what `nch climbs` lists, and how
    attempts*: Attempts
    case kind*: ListKind
    of lkSelection:
      discard
    of lkFound:
      criteria*: ClimbCriteria ## none given: every climb (`--all`)
      select*: bool ## keep what is found as the climbs selection

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
    of caList:
      list*: Listing
    of caEdit:
      edit*: Edit
    of caDeleteAll:
      force*: Force ## really do it
    of caRetired, caDuplicates:
      discard

  Raw = object ## what the options fill in
    help, all, editing, auto, retire, unretire, retired, duplicates, delete: bool
    force: Force
    verbose, everyone, ridden, invert, select: bool
    name, rename: string
    names, categories: seq[string]
    start, passes: Option[Near]
    radiusKm: Option[float]

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
      return refuse(~"`{name}` needs some text")
    p.names.add v.strip
  if values.len == 0:
    return refuse(~"`{name}` needs some text")
  fine

proc takeCategories(
    p: var Raw, name: string, values: seq[string]
): Problem {.nimcall.} =
  if values.len == 0:
    return refuse(~"`{name}` needs at least one category")
  for v in values:
    let c = v.strip.toUpperAscii
    if c notin categoryNames:
      return refuse(~"'{v}' is not a category (they are {categoryNames.join(\" \")})")
    p.categories.add c
  fine

func takeNear(p: var Raw, v: string, passes: bool): Problem =
  let pos = parsePosition(v)
  var near: Near
  if pos.isSome:
    near = Near(kind: nrPoint, lat: pos.get.lat, lon: pos.get.lon)
  elif v.strip.len > 0 and v[0] notin {'0' .. '9', '-', '+', '.'}:
    # (a name: what looks like a number is a position written wrongly, and says so)
    near = Near(kind: nrPlace, place: v.strip)
  else:
    return
      refuse(~"cannot read the position '{v}' (use -33.42,-70.63 or a place's name)")
  if passes:
    p.passes = some(near)
  else:
    p.start = some(near)
  fine

func takeRadius(p: var Raw, v: string): Problem =
  try:
    let r = parseFloat(v)
    if r <= 0:
      return refuse(~"the radius must be more than 0km")
    p.radiusKm = some(r)
  except ValueError:
    return refuse(~"cannot read the radius '{v}' (kilometres)")
  fine

func climbSpec*(): Spec[Raw] =
  ## The options of `nch climbs`: the options that change a climb go under `--edit`.
  Spec[Raw](
    opts: @[
      listOption[Raw](
        ["--names"],
        takeNames,
        "TEXT...",
        ~"the climbs whose name holds any of the texts (case and accents do not matter; the number counts: `--names farellones₂`, which `--names \"farellones 2\"` also means); a whole number that no name holds is a climb's number (`--names 62`)",
      ),
      flag(
        Raw,
        ["--ridden"],
        ridden,
        ~"the climbs that the selected activities went up (see `nch activities --select`)",
      ),
      custom(
        Raw,
        ["--from"],
        true,
        "LAT,LON|PLACE",
        ~"the climbs that start within the radius (default: {defaultStartKm:g}km) of the point; or of a place, by its name (one of your landmarks, else the biggest place of that name among those the names were loaded for: `--from providencia`)",
        body = takeNear(p, value, false),
      ),
      custom(
        Raw,
        ["--near"],
        true,
        "LAT,LON|PLACE",
        ~"the climbs whose line passes within the radius (default: {defaultPassKm:g}km) of the point, or of a place (as `--from`: `--near farellones`)",
        body = takeNear(p, value, true),
      ),
      custom(
        Raw,
        ["--radius"],
        true,
        "KM",
        ~"the radius for `--from` and `--near` in kilometres",
        level = 1,
        body = takeRadius(p, value),
      ),
      listOption[Raw](
        ["--categories"],
        takeCategories,
        "CAT...",
        ~"the climbs of these categories ({categoryNames.join(\" \")}, by the height gained)",
      ),
      flag(
        Raw,
        ["--invert"],
        invert,
        ~"the climbs that the criteria do NOT find (all of them taken together)",
      ),
      flag(
        Raw,
        ["--select", "--save"],
        select,
        ~"make what is listed the climbs selection, which `nch climbs` lists and `nch map climbs` shows (needs criteria or `--all`)",
      ),
      flag(
        Raw,
        ["-v", "--verbose"],
        verbose,
        ~"list the attempts under each climb, the fastest first, each with its rank (those of the selected rides in the selection's colour)",
      ),
      flag(
        Raw,
        ["--everyone"],
        everyone,
        ~"the people instead of your attempts: how many have ridden each climb, the fastest and who, and where your best time comes among everyone's best times (\"4 of 6\"); with `-v` each person's best.  (The personal rank and this one are never shown together.)",
      ),
      flag(Raw, ["--all"], all, ~"every climb, not just the selection"),
      flag(
        Raw,
        ["--delete"],
        delete,
        ~"(with `--all`) delete every climb found, with the efforts on them (of every user), and start again: the next `nch climbs` works them out again from the rides.  Names given by hand are lost (the message says how many).  Needs `-f`.  The climbs are never deleted one at a time: `--edit NAME --retire` hides one",
        level = 1,
      ),
      forceOption(Raw, force, 2),
      custom(
        Raw,
        ["--edit"],
        true,
        "NAME",
        ~"change that climb, with one of the following.  NAME is a climb's name as `--all` shows it, its number included where several share a name: \"Morro La Cabra₁\" (\"Morro La Cabra 1\" and \"Morro La Cabra1\" do as well).  The number is kept: it never changes",
        completion = completesFrom(completeClimbNames),
        body = (p.editing = true; p.name = value; fine),
      ),
      custom(
        Raw,
        ["--rename"],
        true,
        "NEW",
        ~"give it the name NEW (any words; at most 60 characters; not ending in a subscript number, which the program adds when climbs share a name).  The name is kept: the program never changes it.  Several climbs may have the same name",
        level = 1,
        body = (
          block:
            p.rename = value.strip
            let why = nameProblem(value)
            if why.len > 0:
              return refuse(plain(why))
            fine
        ),
      ),
      flag(
        Raw,
        ["--auto"],
        auto,
        ~"forget the name; it is named again at once from the places near it (or by the next `nch climbs` if the names cannot be had)",
        level = 1,
      ),
      flag(
        Raw,
        ["--retire"],
        retire,
        ~"hide the climb from the lists, as a segment can be hidden on Strava.  Nothing is deleted: it keeps its efforts, still takes those of new rides, and keeps its number, so the gap shows",
        level = 1,
      ),
      flag(Raw, ["--unretire"], unretire, ~"show it again", level = 1),
      flag(Raw, ["--retired"], retired, ~"list the retired climbs"),
      flag(
        Raw,
        ["--duplicates"],
        duplicates,
        ~"list the climbs that largely overlap (more than {int(round((1 - nearCopyLimit) * 100))}% of each lies within {int(gateRadius)}m of the other), the most ridden first, with the command to hide each of the others",
      ),
      helpFlag(Raw),
    ],
    hint: proc(arg: string): Line {.nimcall, raises: [].} =
      ~" (to change a climb: `--edit {arg} --rename NEW`, `--auto`, `--retire` or `--unretire`)",
  )

func given*(c: ClimbCriteria): bool =
  ## Whether any criterion is given (none: every climb, `--all`).
  c.names.len > 0 or c.ridden or c.start.isSome or c.passes.isSome or
    c.categories.len > 0

func startKm*(c: ClimbCriteria): float =
  ## The radius of `--from`.
  c.radiusKm.get(defaultStartKm)

func passKm*(c: ClimbCriteria): float =
  ## The radius of `--near`.
  c.radiusKm.get(defaultPassKm)

func criteriaOf(raw: Raw): Option[ClimbCriteria] =
  ## The criteria given (none: there are none).
  let c = ClimbCriteria(
    names: raw.names,
    ridden: raw.ridden,
    start: raw.start,
    passes: raw.passes,
    radiusKm: raw.radiusKm,
    categories: raw.categories,
    invert: raw.invert,
  )
  if c.given:
    some(c)
  else:
    none(ClimbCriteria)

func finish(raw: Raw): Parsed[Params] =
  func bad(why: Line): Parsed[Params] =
    problemWith[Params](why)

  let changes =
    (if raw.rename.len > 0: 1 else: 0) + (if raw.auto: 1 else: 0) +
    (if raw.retire: 1 else: 0) + (if raw.unretire: 1 else: 0)
  if raw.editing:
    if raw.name.strip.len == 0:
      return bad(~"`--edit` needs the name of a climb, as `nch climbs --all` shows it")
    if changes == 0:
      return bad(
        ~"`--edit` needs something to change: `--rename NEW`, `--auto`, `--retire` or `--unretire`"
      )
    if changes > 1:
      return bad(
        ~"`--rename`, `--auto`, `--retire` and `--unretire` cannot be used together"
      )
    if raw.retired or raw.duplicates or raw.all:
      return bad(
        ~"`--all`, `--retired` and `--duplicates` list climbs: they do not go with `--edit`"
      )
  elif changes > 0:
    return
      bad(~"`--rename`, `--auto`, `--retire` and `--unretire` go with `--edit NAME`")
  if (if raw.retired: 1 else: 0) + (if raw.duplicates: 1 else: 0) +
      (if raw.all: 1 else: 0) > 1:
    return bad(~"`--all`, `--retired` and `--duplicates` cannot be used together")
  if raw.force != fNo and not raw.delete:
    return bad(~"`-f` goes with `--delete`")
  if raw.delete:
    if not raw.all:
      return bad(
        ~"`--delete` needs `--all`: the climbs are never deleted one at a time (to hide one: `--edit NAME --retire`)"
      )
    if raw.editing or raw.retired or raw.duplicates:
      return bad(~"`--delete` does not go with `--edit`, `--retired` or `--duplicates`")
  let criteria = criteriaOf(raw)
  let tidying = raw.editing or raw.delete or raw.retired or raw.duplicates
  if tidying and (criteria.isSome or raw.select or raw.invert or raw.radiusKm.isSome):
    return bad(
      ~"the criteria choose climbs to list: they do not go with `--edit`, `--delete`, `--retired` or `--duplicates`"
    )
  if (raw.verbose or raw.everyone) and tidying:
    return bad(
      ~"`-v` and `--everyone` go with the attempts: `nch climbs` (with criteria, or `--all`) shows them"
    )
  if raw.invert and criteria.isNone:
    return bad(~"`--invert` needs criteria to turn round")
  if raw.radiusKm.isSome and raw.start.isNone and raw.passes.isNone:
    return bad(~"`--radius` goes with `--from` or `--near`")
  if raw.select and criteria.isNone and not raw.all:
    return bad(
      ~"`--select` needs criteria or `--all`: it keeps what they find as the climbs selection"
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
  elif criteria.isSome or raw.all:
    parsedOk(
      Params(
        action: caList,
        list: Listing(
          kind: lkFound,
          attempts: attempts,
          criteria: criteria.get(ClimbCriteria()),
          select: raw.select,
        ),
      )
    )
  else:
    parsedOk(
      Params(action: caList, list: Listing(kind: lkSelection, attempts: attempts))
    )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch climbs` (the climbs selection), criteria or `--all` (and `--select`), `--retired`, `--duplicates`,
  ## `--delete --all -f`, `--edit NAME --rename NEW`, `--edit NAME --auto`, `--edit NAME --retire`, `--edit NAME --unretire`.
  parseCommand(args, climbSpec(), Raw(), finish)
