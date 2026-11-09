## The command line of `nch landmarks`, parsed.  Pure.

import ../packages/util/args/args
import std/[options, strutils]
import ../packages/landmark/landmarks

{.push raises: [].}

type Params* = object
  list*: bool ## show the landmarks (nothing else asked)
  add*: bool ## `--add NAME`
  delete*: bool ## `--delete NAME`
  force*: bool ## `-f`: really (with --delete)
  name*: string
  search*: string ## `--search TEXT`: suggest features by name
  near*: Option[tuple[lon, lat: float]]
    ## `--near LON,LAT`: suggest features round a position
  at*: Option[tuple[lon, lat: float]] ## `--at LON,LAT`: the position of the new landmark
  pick*: int ## `--pick N`: take suggestion N (1-based); 0: not given
  radiusM*: float ## `--radius METRES`
  help*: bool
  problem*: string

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

proc parseArgs*(args: seq[string]): Params =
  ## `nch landmarks` (list), `--search TEXT`, `--near LON,LAT`, `--add NAME (--search TEXT | --near LON,LAT) --pick N`,
  ## `--add NAME --at LON,LAT`, each with `--radius METRES`; `--delete NAME`.
  result.radiusM = defaultRadiusM
  let addOption = custom(Params, ["--add"], true):
    p.add = true
    p.name = value
    ""
  let removeOption = custom(Params, ["--delete"], true):
    p.delete = true
    p.name = value
    ""
  let nearOption = custom(Params, ["--near"], true):
    p.near = parsePosition(value)
    if p.near.isNone:
      return "--near is a position as LON,LAT in degrees (not '" & value & "')"
    ""
  let atOption = custom(Params, ["--at"], true):
    p.at = parsePosition(value)
    if p.at.isNone:
      return "--at is a position as LON,LAT in degrees (not '" & value & "')"
    ""
  let pickOption = custom(Params, ["--pick"], true):
    try:
      p.pick = parseInt(value)
    except ValueError:
      return "--pick is the number of a suggestion (not '" & value & "')"
    if p.pick < 1:
      return "--pick is the number of a suggestion, from 1"
    ""
  let radiusOption = custom(Params, ["--radius"], true):
    try:
      p.radiusM = parseFloat(value)
    except ValueError:
      return "--radius is metres (not '" & value & "')"
    ""
  let spec = Spec[Params](
    opts: @[
      flag(Params, ["-h", "--help"], help),
      flag(Params, ["-f", "--force"], force),
      addOption,
      removeOption,
      nearOption,
      atOption,
      pickOption,
      radiusOption,
      text(Params, ["--search"], search),
    ],
    hint: proc(arg: string): string {.nimcall, raises: [].} =
      " (to find a place: --search " & arg & "; to make a landmark: --add " & arg &
        " ...)",
  )
  template fail(msg: string) =
    result.problem = msg
    return

  let why = parseOptions(args, spec, result)
  if why.len > 0:
    fail(why)
  if result.help:
    return
  if result.force and not result.delete:
    fail("-f goes with --delete")
  if result.add and result.delete:
    fail("--add and --delete cannot be used together")
  let sources =
    (if result.search.len > 0: 1 else: 0) + (if result.near.isSome: 1 else: 0) +
    (if result.at.isSome: 1 else: 0)
  if result.delete:
    if sources > 0 or result.pick > 0:
      fail("--delete goes with a name only")
  elif result.add:
    if sources != 1:
      fail(
        "--add needs one of: --search TEXT --pick N, --near LON,LAT --pick N, --at LON,LAT"
      )
    if result.at.isNone and result.pick == 0:
      fail(
        "--add with --search or --near also needs --pick N (the number of the suggestion)"
      )
    if result.at.isSome and result.pick > 0:
      fail("--pick goes with --search or --near, not with --at")
    let why = problem(result.name, 0.0, 0.0, result.radiusM)
    if why.len > 0:
      fail(why)
  else:
    if result.pick > 0:
      fail("--pick goes with --add NAME")
    if result.at.isSome:
      fail("--at goes with --add NAME")
    if sources > 1:
      fail("--search and --near cannot be used together")
    if result.radiusM != defaultRadiusM:
      fail("--radius goes with --add")
  result.list =
    not (result.add or result.delete or result.search.len > 0 or result.near.isSome)
