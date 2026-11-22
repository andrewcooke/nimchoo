## `--from`, `--near` and `--radius`: the reading of a point, the radius and the options that give them.  Pure.
##
## The commands that search by place keep a `Where` while the options are read (`nearOptions` makes the three options, working
## on a field of the command's builder), and turn it into their criteria in `finish`.

import std/[options, strformat, strutils]
import ../geo/position
import ../ui/units
import ../util/args/args

{.push raises: [].}

type
  NearKind* = enum
    nkNone
    nkPoint
    nkPlace ## a place by its name, found when the command runs (`names/places`)
    nkLatest
    nkPrevious

  Spot* = object ## a point as given to `--from` or `--near`
    kind*: NearKind
    lat*, lon*: float ## for nkPoint
    place*: string ## for nkPlace: the name as given

  Where* = object ## what `--from`, `--near` and `--radius` said
    start*: Spot ## `--from`
    passes*: Spot ## `--near`
    radius*: Option[Distance] ## `--radius` (none: each its default)
    given*: bool ## one of the three was

const
  defaultStartRadius* = Distance(10_000.0) ## the radius of `--from`: a start within this
  defaultPassRadius* = Distance(1_000.0)
    ## the radius of `--near`: a route that comes this close has passed

func startKm*(radius: Option[Distance]): float =
  ## The radius of `--from`, in kilometres.
  radius.get(defaultStartRadius).inKm

func passKm*(radius: Option[Distance]): float =
  ## The radius of `--near`, in kilometres.
  radius.get(defaultPassRadius).inKm

func parseSpot*(v: string, references: bool): Option[Spot] =
  ## `LAT,LON` or a place's name; with `references`, `latest` or `previous` too (any case).  What looks like a number is a
  ## position written wrongly, not a name: none.
  if references and v.toLowerAscii == "latest":
    return some(Spot(kind: nkLatest))
  if references and v.toLowerAscii == "previous":
    return some(Spot(kind: nkPrevious))
  let pos = parsePosition(v)
  if pos.isSome:
    return some(Spot(kind: nkPoint, lat: pos.get.lat, lon: pos.get.lon))
  if v.strip.len > 0 and v[0] notin {'0' .. '9', '-', '+', '.'}:
    return some(Spot(kind: nkPlace, place: v.strip))
  none(Spot)

func spotHelp*(references: bool): string =
  ## What may be typed for a point, for a problem.
  if references:
    "use 38.72,-9.14, a place's name, latest or previous"
  else:
    "use -33.42,-70.63 or a place's name"

func takeSpot*(w: var Where, v: string, passes, references: bool): Problem =
  ## `--from SPOT` (where the thing starts), `--near SPOT` (a point its route passes).
  w.given = true
  let spot = parseSpot(v, references)
  if spot.isNone:
    return refuse(~"cannot read the position '{v}' ({spotHelp(references)})")
  if passes:
    w.passes = spot.get
  else:
    w.start = spot.get
  fine

func takeRadius*(w: var Where, v: string): Problem =
  ## `--radius DISTANCE`: more than zero, with its unit.
  w.given = true
  let r = parseDistance(v)
  if r.isNone:
    return refuse(
      ~"cannot read the radius '{v}' (a distance more than 0, with its unit: `3km` or `500m`)"
    )
  w.radius = r
  fine

func settle*(w: var Where, references: bool): Problem =
  ## `--radius` goes with `--from` or `--near`.  Alone it means `--from latest` where there is a latest (`references`: the
  ## activities), and is refused elsewhere.
  if w.radius.isSome and w.start.kind == nkNone and w.passes.kind == nkNone:
    if references:
      w.start = Spot(kind: nkLatest)
    else:
      return refuse(~"`--radius` goes with `--from` or `--near`")
  fine

func hasPlace*(w: Where): bool =
  ## Whether a point or a radius was given.
  w.start.kind != nkNone or w.passes.kind != nkNone or w.radius.isSome

func nearHelp*(thing: string, references: bool): array[3, Line] =
  ## The help of `--from`, `--near` and `--radius`.  `thing` is what is searched ("activities", "the climbs"); with
  ## `references`, `latest` and `previous` may be given for a point.
  let startKm = defaultStartRadius.inKm
  let passKm = defaultPassRadius.inKm
  let latest =
    if references:
      ~"; `--from latest`: of where the latest activity started (or \"previous\")"
    else:
      @[]
  let latestToo =
    if references:
      ~", or of where the latest activity started (or \"previous\")"
    else:
      @[]
  let alone =
    if references:
      ~"; on its own it means `--from latest`"
    else:
      @[]
  [
    ~"{thing} that start within the radius (default: {startKm:g}km) of the point; or of a place, by its name (one of your landmarks, else the biggest place of that name among those the names were loaded for: `--from providencia`)" &
      latest,
    ~"{thing} whose route or line passes within the radius (default: {passKm:g}km) of the point, or of a place (as `--from`: `--near farellones`)" &
      latestToo,
    ~"the radius for `--from` and `--near`, with its unit (`3km`, `500m`; a bare number is taken as km, after asking)" &
      alone,
  ]

func pointMetavar*(references: bool): string =
  if references: "LAT,LON|PLACE|latest" else: "LAT,LON|PLACE"

template nearOptions*(
    P: typedesc, field: untyped, thing: string, references: bool, indent: int = 0
): seq[Opt[P]] =
  ## The three options on the field `field` (a `Where`) of the builder `P`.
  block:
    let texts = nearHelp(thing, references)
    @[
      custom(
        P,
        ["--from"],
        true,
        pointMetavar(references),
        texts[0],
        level = indent,
        body = takeSpot(p.field, value, false, references),
      ),
      custom(
        P,
        ["--near"],
        true,
        pointMetavar(references),
        texts[1],
        level = indent,
        body = takeSpot(p.field, value, true, references),
      ),
      custom(
        P,
        ["--radius"],
        true,
        "DISTANCE",
        texts[2],
        level = indent,
        body = takeRadius(p.field, value),
      )
        .withUnit("km"),
    ]
