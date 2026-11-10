## The command line of `nch landmarks`, parsed.  Pure.

import ../util/args/args
import std/[options, strutils]
import ./landmarks

{.push raises: [].}

type
  Position* = tuple[lon, lat: float] ## in degrees

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
      near*: Position

  PickedLandmark* = object ## `--add NAME` at suggestion `pick` of `from`
    name*: string
    suggestions*: Suggest
    pick*: int ## 1-based
    radiusM*: float

  PlacedLandmark* = object ## `--add NAME --at LON,LAT`
    name*: string
    at*: Position
    radiusM*: float

  DeletedLandmark* = object
    name*: string
    force*: bool ## really do it

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
    help, force, adding, deleting: bool
    name, search: string
    near, at: Option[Position]
    pick: int
    radiusM: float

func parsePosition*(s: string): Option[tuple[lon, lat: float]] =
  ## "LON,LAT" in degrees.
  let parts = s.split(',')
  if parts.len != 2:
    return
  try:
    let lon = parseFloat(parts[0].strip)
    let lat = parseFloat(parts[1].strip)
    if lon < -180.0 or lon > 180.0 or lat < -90.0 or lat > 90.0:
      return
    result = some((lon, lat))
  except ValueError:
    discard

func landmarkSpec*(): Spec[Raw] =
  ## The options of `nch landmarks`.
  Spec[Raw](
    opts: @[
      text(
        Raw,
        ["--search"],
        search,
        "TEXT",
        "suggest features of GeoNames whose name holds TEXT (any kind: streams, farms, parks ...), numbered; only places whose cells have been read can be found (the places you have ridden)",
      ),
      custom(
        Raw,
        ["--near"],
        true,
        "LON,LAT",
        "suggest the features within 2 km of a position, nearest first, numbered (the names for that area are fetched if need be)",
        body = (
          block:
            p.near = parsePosition(value)
            if p.near.isNone:
              return refuse(
                "--near is a position as LON,LAT in degrees (not '" & value & "')"
              )
            fine
        ),
      ),
      custom(
        Raw,
        ["--add"],
        true,
        "NAME",
        "make a landmark called NAME, at the position of suggestion N (`--pick N`, from the same --search or --near) or at a position you give (`--at LON,LAT`); its circle has the radius of --radius (100 to 20,000 metres; default 1,000)",
        body = (p.adding = true; p.name = value; fine),
      ),
      custom(
        Raw,
        ["--pick"],
        true,
        "N",
        "the number of the suggestion to make the landmark at",
        level = 1,
        body = (
          block:
            try:
              p.pick = parseInt(value)
            except ValueError:
              return
                refuse("--pick is the number of a suggestion (not '" & value & "')")
            if p.pick < 1:
              return refuse("--pick is the number of a suggestion, from 1")
            fine
        ),
      ),
      custom(
        Raw,
        ["--at"],
        true,
        "LON,LAT",
        "the position of the landmark, if not at a suggestion",
        level = 1,
        body = (
          block:
            p.at = parsePosition(value)
            if p.at.isNone:
              return
                refuse("--at is a position as LON,LAT in degrees (not '" & value & "')")
            fine
        ),
      ),
      custom(
        Raw,
        ["--radius"],
        true,
        "METRES",
        "the radius of the landmark's circle",
        level = 1,
        body = (
          block:
            try:
              p.radiusM = parseFloat(value)
            except ValueError:
              return refuse("--radius is metres (not '" & value & "')")
            fine
        ),
      ),
      custom(
        Raw,
        ["--delete"],
        true,
        "NAME",
        "delete the landmark (needs -f)",
        body = (p.deleting = true; p.name = value; fine),
      ),
      flag(Raw, ["-f", "--force"], force, "really do it", level = 1),
      helpFlag(Raw),
    ],
    hint: proc(arg: string): string {.nimcall, raises: [].} =
      " (to find a place: --search " & arg & "; to make a landmark: --add " & arg &
        " ...)",
  )

func finish(raw: Raw): Parsed[Params] =
  func bad(why: string): Parsed[Params] =
    problemWith[Params](why)

  if raw.force and not raw.deleting:
    return bad("-f goes with --delete")
  if raw.adding and raw.deleting:
    return bad("--add and --delete cannot be used together")
  let sources =
    (if raw.search.len > 0: 1 else: 0) + (if raw.near.isSome: 1 else: 0) +
    (if raw.at.isSome: 1 else: 0)
  if raw.deleting:
    if sources > 0 or raw.pick > 0:
      return bad("--delete goes with a name only")
    return parsedOk(
      Params(
        action: laDelete, deleted: DeletedLandmark(name: raw.name, force: raw.force)
      )
    )
  if raw.adding:
    if sources != 1:
      return bad(
        "--add needs one of: --search TEXT --pick N, --near LON,LAT --pick N, --at LON,LAT"
      )
    if raw.at.isNone and raw.pick == 0:
      return bad(
        "--add with --search or --near also needs --pick N (the number of the suggestion)"
      )
    if raw.at.isSome and raw.pick > 0:
      return bad("--pick goes with --search or --near, not with --at")
    let why = problem(raw.name, 0.0, 0.0, raw.radiusM)
    if why.len > 0:
      return bad(why)
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
    return bad("--pick goes with --add NAME")
  if raw.at.isSome:
    return bad("--at goes with --add NAME")
  if sources > 1:
    return bad("--search and --near cannot be used together")
  if raw.radiusM != defaultRadiusM:
    return bad("--radius goes with --add")
  if raw.search.len > 0:
    parsedOk(
      Params(action: laSearch, suggest: Suggest(kind: skSearch, text: raw.search))
    )
  elif raw.near.isSome:
    parsedOk(Params(action: laNear, suggest: Suggest(kind: skNear, near: raw.near.get)))
  else:
    parsedOk(Params(action: laList))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch landmarks` (list), `--search TEXT`, `--near LON,LAT`, `--add NAME (--search TEXT | --near LON,LAT) --pick N`,
  ## `--add NAME --at LON,LAT`, each with `--radius METRES`; `--delete NAME`.
  parseCommand(args, landmarkSpec(), Raw(radiusM: defaultRadiusM), finish)
