## The command line of `nch landmarks`, parsed.  Pure.

import ../util/args/args
import ../confirm/confirm
import ../ui/units
import ./completion
import std/[options, strutils]
import ./landmarks
import ../geo/position
import ../near/near
export position.Position, near.Spot, near.NearKind

{.push raises: [].}

type
  LandmarkAction* = enum
    laList ## show the landmarks
    laSearch ## suggest features by name
    laNear ## suggest features round a position
    laAddPicked ## make a landmark at a suggestion
    laAddAt ## make a landmark at a position
    laDelete

  SuggestKind* = enum
    skSearch
    skNear

  Suggest* = object ## where the suggestions come from
    case kind*: SuggestKind
    of skSearch:
      text*: string
    of skNear:
      near*: Spot ## a position or a place's name (resolved by the command)

  PickedLandmark* = object ## `--add NAME` at suggestion `pick` of `from`
    name*: string
    suggestions*: Suggest
    pick*: int ## 1-based
    radiusM*: float

  PlacedLandmark* = object ## `--add NAME --at LAT,LON`
    name*: string
    at*: Spot
    radiusM*: float

  DeletedLandmark* = object
    name*: string
    force*: Force ## `-f`: really do it (`-f -f`: with no pause)

  Params* = object
    case action*: LandmarkAction
    of laList:
      discard
    of laSearch, laNear:
      suggest*: Suggest
    of laAddPicked:
      picked*: PickedLandmark
    of laAddAt:
      placed*: PlacedLandmark
    of laDelete:
      deleted*: DeletedLandmark

  Raw = object ## what the options fill in
    help, adding, deleting: bool
    force: Force
    name, search: string
    near, at: Option[Spot]
    pick: int
    radiusM: float

func landmarkSpec*(): Spec[Raw] =
  ## The options of `nch landmarks`.
  Spec[Raw](
    opts: @[
      text(
        Raw,
        ["--search"],
        search,
        "TEXT",
        ~"suggest features of GeoNames whose name holds TEXT (any kind: streams, farms, parks ...), numbered; only places whose cells have been read can be found (the places you have ridden)",
      ),
      custom(
        Raw,
        ["--near"],
        true,
        "LAT,LON|PLACE",
        ~"suggest the features within 2 km of a position or of a place (a landmark, else the biggest place of that name among those the names were loaded for), nearest first, numbered (the names for that area are fetched if need be)",
        body = (
          block:
            p.near = parseSpot(value, false)
            if p.near.isNone:
              return refuse(
                ~"`--near` is a position as LAT,LON in degrees, or a place's name (not '{value}')"
              )
            fine
        ),
      ),
      custom(
        Raw,
        ["--add"],
        true,
        "NAME",
        ~"make a landmark called NAME, at the position of suggestion N (`--pick N`, from the same `--search` or `--near`) or at a position you give (`--at LAT,LON`); its circle has the radius of `--size` (100m to 20km; default 1km)",
        body = (p.adding = true; p.name = value; fine),
      ),
      custom(
        Raw,
        ["--pick"],
        true,
        "N",
        ~"the number of the suggestion to make the landmark at",
        level = 1,
        body = (
          block:
            try:
              p.pick = parseInt(value)
            except ValueError:
              return refuse(~"`--pick` is the number of a suggestion (not '{value}')")
            if p.pick < 1:
              return refuse(~"`--pick` is the number of a suggestion, from 1")
            fine
        ),
      ),
      custom(
        Raw,
        ["--at"],
        true,
        "LAT,LON|PLACE",
        ~"the position of the landmark, if not at a suggestion: a position, or a place's name (as `--near`)",
        level = 1,
        body = (
          block:
            p.at = parseSpot(value, false)
            if p.at.isNone:
              return refuse(
                ~"`--at` is a position as LAT,LON in degrees, or a place's name (not '{value}')"
              )
            fine
        ),
      ),
      custom(
        Raw,
        ["--size"],
        true,
        "DISTANCE",
        ~"the radius of the landmark's own circle, with its unit (`500m`, `1.5km`; a bare number is taken as metres, after asking)",
        level = 1,
        body = (
          block:
            let d = parseDistance(value)
            if d.isNone:
              return valueIs(
                name, "a distance with its unit, more than 0 (`500m`, `1.5km`)", value
              )
            p.radiusM = d.get.inMetres
            fine
        ),
      )
        .withUnit("m"),
      custom(
        Raw,
        ["--delete"],
        true,
        "NAME",
        ~"delete the landmark (needs `-f`)",
        completion = completesFrom(completeLandmarks),
        body = (p.deleting = true; p.name = value; fine),
      ),
      forceOption(Raw, force, 1),
      helpFlag(Raw),
    ],
    hint: proc(arg: string): Line {.nimcall, raises: [].} =
      ~" (to find a place: `--search {arg}`; to make a landmark: `--add {arg} ...`)",
  )

func finish(raw: Raw): Parsed[Params] =
  func bad(why: Line): Parsed[Params] =
    problemWith[Params](why)

  if raw.force != fNo and not raw.deleting:
    return bad(~"`-f` goes with `--delete`")
  if raw.adding and raw.deleting:
    return bad(~"`--add` and `--delete` cannot be used together")
  let sources =
    (if raw.search.len > 0: 1 else: 0) + (if raw.near.isSome: 1 else: 0) +
    (if raw.at.isSome: 1 else: 0)
  if raw.deleting:
    if sources > 0 or raw.pick > 0:
      return bad(~"`--delete` goes with a name only")
    return parsedOk(
      Params(
        action: laDelete, deleted: DeletedLandmark(name: raw.name, force: raw.force)
      )
    )
  if raw.adding:
    if sources != 1:
      return bad(
        ~"`--add` needs one of: `--search TEXT --pick N`, `--near LAT,LON --pick N`, `--at LAT,LON`"
      )
    if raw.at.isNone and raw.pick == 0:
      return bad(
        ~"`--add` with `--search` or `--near` also needs `--pick N` (the number of the suggestion)"
      )
    if raw.at.isSome and raw.pick > 0:
      return bad(~"`--pick` goes with `--search` or `--near`, not with `--at`")
    let why = problem(raw.name, 0.0, 0.0, raw.radiusM)
    if why.len > 0:
      return bad(plain(why))
    if raw.at.isSome:
      return parsedOk(
        Params(
          action: laAddAt,
          placed: PlacedLandmark(name: raw.name, at: raw.at.get, radiusM: raw.radiusM),
        )
      )
    let source =
      if raw.search.len > 0:
        Suggest(kind: skSearch, text: raw.search)
      else:
        Suggest(kind: skNear, near: raw.near.get)
    return parsedOk(
      Params(
        action: laAddPicked,
        picked: PickedLandmark(
          name: raw.name, suggestions: source, pick: raw.pick, radiusM: raw.radiusM
        ),
      )
    )
  if raw.pick > 0:
    return bad(~"`--pick` goes with `--add NAME`")
  if raw.at.isSome:
    return bad(~"`--at` goes with `--add NAME`")
  if sources > 1:
    return bad(~"`--search` and `--near` cannot be used together")
  if raw.radiusM != defaultRadiusM:
    return bad(~"`--size` goes with `--add`")
  if raw.search.len > 0:
    parsedOk(
      Params(action: laSearch, suggest: Suggest(kind: skSearch, text: raw.search))
    )
  elif raw.near.isSome:
    parsedOk(Params(action: laNear, suggest: Suggest(kind: skNear, near: raw.near.get)))
  else:
    parsedOk(Params(action: laList))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch landmarks` (list), `--search TEXT`, `--near LAT,LON`, `--add NAME (--search TEXT | --near LAT,LON) --pick N`,
  ## `--add NAME --at LAT,LON|PLACE`, each with `--size DISTANCE`; `--delete NAME`.
  parseCommand(args, landmarkSpec(), Raw(radiusM: defaultRadiusM), finish)
