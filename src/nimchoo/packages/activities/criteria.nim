## What `nch activities` is asked for: the command line parsed into criteria, and the
## criteria turned into SQL.  Pure: no database, no clock, no terminal (the time
## zone is a parameter), so all of it is tested directly.

import std/[math, options, strformat, strutils, times]
import ../fit/time
import ../confirm/confirm
import ../util/args/args
import ../ui/units
import ../db/sqltext
import ../../core/ids
import ../geo/position
import ../text/fold/fold
import ./[completion, criterion, ranges]
export ranges, criterion

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

  Points* = object
    ## the points `--from` and `--near` came to, once a place, `latest` and `previous` are worked out: (lat, lon)
    start*, passes*: Option[(float, float)]

  GpsFilter* = enum
    gfAny
    gfWith
    gfWithout
      ## --gps: only activities with at least one position; --no-gps: only those without any

  Criteria* = object
    all*: bool ## --all: every activity (not the selection)
    given*: bool
      ## some criterion or limit was given: the activities are searched for, not the selection
    select*: bool ## --select: keep what is listed as the selection
    delete*: bool ## --delete: delete the activities (an action, not a criterion)
    rename*: bool ## --rename: name the activities again (an action, not a criterion)
    force*: Force ## -f: really do it (with --delete)
    verbose*: bool ## -v: show more of each activity (a display option)
    newest*, oldest*: int
      ## only the N newest (oldest) of those that meet the other
      ## criteria, by start time; 0: no limit
    distanceM*, activeS*: NumRange ## --distance, --active (metres, seconds; open: any)
    distanceRel*, activeRel*: Option[Relative]
      ## --distance latest~T / previous~T, --active ...
    sportRef*, subSportRef*: Reference ## --sports latest / previous, --sub-sports ...
    sports*, subSports*: seq[string]
      ## only these (lower case; "none": not recorded); empty: any
    nameRef*, startRef*: Reference ## --names latest / previous, --starts ...
    names*, starts*: seq[string]
      ## --names, --starts: text found in the name (the start place), whatever its case and
      ## accents; "none": nothing; empty: any
    namesExact*, startsExact*: seq[string]
      ## what `latest` / `previous` came to: the whole value ("" is none)
    nameIds*: seq[int64]
      ## the activities a whole number in `--names` meant, when no name held it (worked out when the command runs)
    paths*: seq[string]
      ## --paths: text found in a path the file was imported from (or in its name)
    contributed*: seq[Contributed]
      ## the options that other packages offer (`--climbs`), as given: they are resolved when the command runs
    afterT*: Option[UnixTime] ## the activity starts at or after this instant
    beforeT*: Option[UnixTime] ## the activity starts before this instant
    gps*: GpsFilter
    invert*: bool
      ## --invert: the activities that do NOT meet the criteria (before --newest / --oldest)
    start*: Spot ## --from: where the activity starts
    passes*: Spot ## --near: a point its route passes
    radiusKm*: Option[float] ## --radius (none: each its default)

  Relative* = object
    ## `latest~10%`: around an activity that is found when the command runs.
    refers*: Reference
    tol*: Tol

  Box* = object
    minX*, minY*, maxX*, maxY*: float ## degrees

const
  defaultStartKm* = 10.0 ## the radius of --from: a start within this
  defaultPassKm* = 1.0 ## the radius of --near: a route that comes this close has passed
  timeFormats = [
    "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
    "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
  ] ## (a date alone is its midnight: as if written with T00:00:00)

proc parseWhen*(s: string, zone: Timezone): Option[UnixTime] =
  ## An instant typed by the user, in `zone`, as Unix seconds: exactly what is written, a date being the start of its day
  ## (`--after`, `--before`: the one rule for every form, so that `--after D --before E` meets the next range at E).
  for format in timeFormats:
    try:
      return some(UnixTime(parse(s, format, zone).toTime.toUnix))
    except TimeParseError, TimeFormatParseError, ValueError, OverflowDefect:
      discard
  none(UnixTime)

proc parseOnDay*(s: string, zone: Timezone): Option[tuple[start, next: UnixTime]] =
  ## A date typed by the user (`--on`: a date, not a time), as the start of that day in `zone` and the start of the next
  ## (a day is not always 24 hours: the clocks change).
  try:
    let d = parse(s, "yyyy-MM-dd", zone)
    some((UnixTime(d.toTime.toUnix), UnixTime((d + 1.days).toTime.toUnix)))
  except TimeParseError, TimeFormatParseError, ValueError, OverflowDefect:
    none(tuple[start, next: UnixTime])

type ListState = object
  ## What the options of `nch activities` fill in as they are read.
  c: Criteria
  help: bool
  zone: Timezone
  offered: seq[Criterion] ## the criteria other packages offer
  radiusGiven: bool ## --radius was given
  onGiven, rangeGiven: bool ## --on was given; --after or --before was
  criteriaGiven: bool ## some option other than those that say what to display

func takeCount(p: var ListState, name, value: string, oldest: bool): Problem =
  ## --newest N, -n N, --oldest N.
  var n = 0
  if not parseIntIn(value, 1, high(int), n):
    return refuse(~"`{name}` needs a number of activities, 1 or more (not '{value}')")
  p.criteriaGiven = true
  if oldest:
    p.c.oldest = n
  else:
    p.c.newest = n
  fine

func splitNames(values: seq[string], lower: bool): seq[string] =
  ## The names given, one to a word (a comma is part of a name).
  for v in values:
    if v.len > 0:
      result.add (if lower: v.toLowerAscii else: v)

proc takeSports(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  p.criteriaGiven = true
  let names = splitNames(values, true)
  if names.len == 0:
    return refuse(~"`{name}` needs at least one name")
  for n in names:
    if parseReference(n) != refNone:
      if p.c.sportRef != refNone and p.c.sportRef != parseReference(n):
        return refuse(~"`--sports`: latest and previous cannot be used together")
      p.c.sportRef = parseReference(n)
    else:
      p.c.sports.add n
  fine

proc takeSubSports(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  p.criteriaGiven = true
  let names = splitNames(values, true)
  if names.len == 0:
    return refuse(~"`{name}` needs at least one name")
  for n in names:
    if parseReference(n) != refNone:
      if p.c.subSportRef != refNone and p.c.subSportRef != parseReference(n):
        return refuse(~"`--sub-sports`: latest and previous cannot be used together")
      p.c.subSportRef = parseReference(n)
    else:
      p.c.subSports.add n
  fine

proc takeTexts(
    p: var ListState,
    name: string,
    values: seq[string],
    texts: var seq[string],
    ref0: var Reference,
): Problem =
  p.criteriaGiven = true
  var found: seq[string]
  for v in values:
    if v.strip.len > 0:
      found.add v.strip
  if found.len == 0:
    return refuse(~"`{name}` needs some text")
  for t in found:
    if parseReference(t) != refNone:
      if ref0 != refNone and ref0 != parseReference(t):
        return refuse(~"`{name}`: latest and previous cannot be used together")
      ref0 = parseReference(t)
    else:
      texts.add t
  fine

proc takeNames(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  takeTexts(p, name, values, p.c.names, p.c.nameRef)

proc takeStarts(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  takeTexts(p, name, values, p.c.starts, p.c.startRef)

proc takePaths(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  p.criteriaGiven = true
  for v in values:
    if v.strip.len > 0:
      p.c.paths.add v.strip
  if p.c.paths.len == 0:
    return refuse(~"`{name}` needs some text")
  fine

proc takeContributed(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  ## An option that another package offers: the words are kept for it to resolve.
  p.criteriaGiven = true
  for o in p.offered:
    if name in o.doc.names:
      if o.doc.arity == aList and values.len == 0:
        return refuse(~"`{name}` needs at least one word")
      for c in p.c.contributed.mitems:
        if c.option == o.doc.names[0]:
          c.values.add values
          return fine
      p.c.contributed.add Contributed(
        option: o.doc.names[0], values: values, resolve: o.resolve
      )
      return fine
  refuse(~"`{name}` is not an option") # (cannot happen: the spec has just these)

func contributedOption(o: Criterion): Opt[ListState] =
  ## The option of an offered criterion, as the parser has them.
  result = Opt[ListState](
    names: o.doc.names,
    takesList: o.doc.arity == aList,
    takesValue: o.doc.arity in {aOne, aOptional},
    valueOptional: o.doc.arity == aOptional,
    applyList: takeContributed,
    apply: proc(
        p: var ListState, name, value: string
    ): Problem {.nimcall, raises: [].} =
      takeContributed(p, name, (if value.len > 0: @[value] else: @[])),
    metavar: o.doc.metavar,
    help: o.doc.help,
    completion: o.doc.completion,
  )

func rangeUnit(v, unit: string): Option[string] =
  ## `--distance 40-` -> `40km-`, `--active 90-` -> `90h-`: for `withUnit`.
  addDefaultUnit(v, unit)

proc takeDistance(p: var ListState, name, text: string): Problem {.nimcall.} =
  p.criteriaGiven = true
  let v = sharedUnit(text)
  if '~' in v:
    let ar = parseAround(v, metresEnd)
    if ar.isNone:
      return refuse(
        ~"cannot read the distance '{text}' (use 42~2km, 500m~50m, latest~10% or previous~10%)"
      )
    if ar.get.centre.isSome:
      p.c.distanceM = around(ar.get.centre.get, ar.get.tol)
    else:
      p.c.distanceRel = some(Relative(refers: ar.get.refers, tol: ar.get.tol))
  else:
    let r = parseRange(v, metresEnd)
    if r.isNone:
      if isBackwards(v, metresEnd):
        return refuse(~"the distance range '{text}' is backwards (smaller end first)")
      return refuse(
        ~"cannot read the distance range '{text}' (use 40km-, 10-50km, -5km, 500m-, 42~2km, latest~10% or previous~10%)"
      )
    p.c.distanceM = r.get
  fine

proc takeActive(p: var ListState, name, text: string): Problem {.nimcall.} =
  p.criteriaGiven = true
  let v = sharedUnit(text)
  if '~' in v:
    let ar = parseAround(v, secondsEnd)
    if ar.isNone:
      return refuse(
        ~"cannot read the active time '{text}' (use 2h~15m, latest~10% or previous~10%)"
      )
    if ar.get.centre.isSome:
      p.c.activeS = around(ar.get.centre.get, ar.get.tol)
    else:
      p.c.activeRel = some(Relative(refers: ar.get.refers, tol: ar.get.tol))
  else:
    let r = parseRange(v, secondsEnd)
    if r.isNone:
      if isBackwards(v, secondsEnd):
        return
          refuse(~"the active time range '{text}' is backwards (shorter end first)")
      return refuse(
        ~"cannot read the active time range '{text}' (use 1h-, 30m-2h, -45m, 2h~15m, latest~10% or previous~10%; units d h m s)"
      )
    p.c.activeS = r.get
  fine

proc takeWhen(p: var ListState, v: string, before: bool): Problem =
  ## --after T, --before T: the instant as written.
  p.criteriaGiven = true
  p.rangeGiven = true
  let t = parseWhen(v, p.zone)
  if t.isNone:
    return refuse(~"cannot read the time '{v}' (use 2018-08-27 or 2018-08-27T09:30)")
  if before:
    p.c.beforeT = t
  else:
    p.c.afterT = t
  fine

proc takeOn(p: var ListState, v: string): Problem =
  ## --on DATE: the activities of that day.
  p.criteriaGiven = true
  p.onGiven = true
  let d = parseOnDay(v, p.zone)
  if d.isNone:
    return refuse(~"`--on` takes a date, like 2018-08-27 (not '{v}')")
  p.c.afterT = some(d.get.start)
  p.c.beforeT = some(d.get.next)
  fine

func takeGps(p: var ListState, wanted: GpsFilter): Problem =
  ## --gps and --no-gps, which contradict each other.
  p.criteriaGiven = true
  if p.c.gps notin {gfAny, wanted}:
    return refuse(~"`--gps` and `--no-gps` cannot be used together")
  p.c.gps = wanted
  fine

func parseSpot(v: string): Option[Spot] =
  ## LAT,LON, a place's name, `latest` or `previous`.
  if parseReference(v) == refLatest:
    return some(Spot(kind: nkLatest))
  if parseReference(v) == refPrevious:
    return some(Spot(kind: nkPrevious))
  let pos = parsePosition(v)
  if pos.isSome:
    return some(Spot(kind: nkPoint, lat: pos.get.lat, lon: pos.get.lon))
  if v.strip.len > 0 and v[0] notin {'0' .. '9', '-', '+', '.'}:
    # (a name: what looks like a number is a position written wrongly, and says so)
    return some(Spot(kind: nkPlace, place: v.strip))
  none(Spot)

func takeSpot(p: var ListState, v: string, passes: bool): Problem =
  ## --from SPOT (where the activity starts), --near SPOT (a point its route passes).
  p.criteriaGiven = true
  let spot = parseSpot(v)
  if spot.isNone:
    return refuse(
      ~"cannot read the position '{v}' (use 38.72,-9.14, a place's name, latest or previous)"
    )
  if passes:
    p.c.passes = spot.get
  else:
    p.c.start = spot.get
  fine

func takeRadius(p: var ListState, v: string): Problem =
  p.criteriaGiven = true
  let r = parseDistance(v)
  if r.isNone:
    return refuse(
      ~"cannot read the radius '{v}' (a distance more than 0, with its unit: `3km` or `500m`)"
    )
  p.c.radiusKm = some(r.get.inKm)
  p.radiusGiven = true
  fine

func startKm*(c: Criteria): float =
  ## The radius of --from.
  c.radiusKm.get(defaultStartKm)

func passKm*(c: Criteria): float =
  ## The radius of --near.
  c.radiusKm.get(defaultPassKm)

func hasFilter*(c: Criteria): bool =
  ## Whether any criterion that picks activities is given (not the limits, the users or the display).
  c.sports.len > 0 or c.subSports.len > 0 or c.names.len > 0 or c.starts.len > 0 or
    c.paths.len > 0 or c.contributed.len > 0 or c.sportRef != refNone or
    c.subSportRef != refNone or c.nameRef != refNone or c.startRef != refNone or
    c.distanceM.lo.isSome or c.distanceM.hi.isSome or c.activeS.lo.isSome or
    c.activeS.hi.isSome or c.distanceRel.isSome or c.activeRel.isSome or c.afterT.isSome or
    c.beforeT.isSome or c.gps != gfAny or c.start.kind != nkNone or
    c.passes.kind != nkNone

proc criteriaSpec*(offered: seq[Criterion] = @[]): Spec[ListState] =
  ## The options of `nch activities`, in the order the usage lists them, each with its help; the criteria that other
  ## packages offer come after the sports, names and paths.
  result = Spec[ListState](
    opts: @[
      custom(
        ListState,
        ["--all"],
        false,
        "",
        ~"every activity, not just the selection",
        body = (p.c.all = true; fine),
      ),
      listOption[ListState](
        ["--sports"],
        takeSports,
        "SPORT...",
        ~"only these sports (cycling, running, swimming ...); \"none\" means not recorded; \"latest\" or \"previous\": that activity's sport",
        completion = completesFrom(completeSports),
      ),
      listOption[ListState](
        ["--sub-sports"],
        takeSubSports,
        "SPORT...",
        ~"only these sub-sports (road, trail, open_water ...).  Many files say \"generic\" or nothing, so this misses some rides",
        completion = completesFrom(completeSubSports),
      ),
      listOption[ListState](
        ["--names"],
        takeNames,
        "TEXT...",
        ~"activities whose name contains any of the TEXTs, whatever its case or accents: `--names toyo` finds \"El Toyo and back\", `--names toyo farellones` finds either; a text with spaces is quoted; a whole number that no name contains is an activity's number (`--names 737`); \"none\": no name; \"latest\" or \"previous\": the same name as that activity",
      ),
      listOption[ListState](
        ["--starts"],
        takeStarts,
        "TEXT...",
        ~"the same for the place the activity started (\"Providencia\", \"near Lo Barnechea\"): `--starts providencia`",
      ),
      listOption[ListState](
        ["--paths"],
        takePaths,
        "TEXT...",
        ~"the same for the path of the file the activity was imported from (or any other path the same file was seen at): `--paths bowman`, `--paths 2026-10`",
      ),
      custom(
        ListState,
        ["--distance"],
        true,
        "RANGE",
        ~"distance, with its unit (`km` or `m`; given once is enough: `10-50km`): 40km- (40 or more), 10-50km, -5km (up to 5), 500m-; 42~2km (between 40 and 44), latest~10%, previous~10%; with no unit it is taken as km, after asking",
        body = takeDistance(p, name, value),
      )
        .withUnit("km", rangeUnit),
      custom(
        ListState,
        ["--active"],
        true,
        "RANGE",
        ~"active time: 1h-, 30m-2h, -45m (units d h m s, as printed; given once is enough in a range: `30-90m`); 2h~15m, latest~10%, previous~10%; with no unit it is taken as hours, after asking",
        body = takeActive(p, name, value),
      )
        .withUnit("h", rangeUnit),
      custom(
        ListState,
        ["--after"],
        true,
        "TIME",
        ~"activities that start at or after TIME",
        body = takeWhen(p, value, false),
      ),
      custom(
        ListState,
        ["--before"],
        true,
        "TIME",
        ~"activities that start before TIME (TIME is in your time zone: 2018-08-27, 2018-08-27T09:30 or with seconds; a date is the start of that day, as if written with T00:00:00: `--after 2018-08-01 --before 2018-09-01` is August)",
        body = takeWhen(p, value, true),
      ),
      custom(
        ListState,
        ["--on"],
        true,
        "DATE",
        ~"activities that start on that day (a date: `--on 2018-08-27` is `--after 2018-08-27 --before 2018-08-28`)",
        body = takeOn(p, value),
      ),
      custom(
        ListState,
        ["--gps"],
        false,
        "",
        ~"only activities that have positions (a GPS track)",
        body = takeGps(p, gfWith),
      ),
      custom(
        ListState,
        ["--no-gps"],
        false,
        "",
        ~"only activities that have none (indoor rides, treadmill runs ...)",
        body = takeGps(p, gfWithout),
      ),
      custom(
        ListState,
        ["--from"],
        true,
        "LAT,LON|PLACE",
        ~"activities that start within the radius (default: {defaultStartKm:g}km) of the point; or of a place, by its name (one of your landmarks, else the biggest place of that name among those the names were loaded for: `--from providencia`); `--from latest`: of where the latest activity started (or \"previous\")",
        body = takeSpot(p, value, false),
      ),
      custom(
        ListState,
        ["--near"],
        true,
        "LAT,LON|PLACE",
        ~"activities whose route passes within the radius (default: {defaultPassKm:g}km) of the point, or of a place (as `--from`: `--near farellones`), or of where the latest activity started (or \"previous\")",
        body = takeSpot(p, value, true),
      ),
      custom(
        ListState,
        ["--radius"],
        true,
        "DISTANCE",
        ~"the radius for `--from` and `--near`, with its unit (`3km`, `500m`; a bare number is taken as km, after asking); on its own it means `--from latest`",
        body = takeRadius(p, value),
      )
        .withUnit("km"),
      custom(
        ListState,
        ["--invert"],
        false,
        "",
        ~"the activities that do NOT meet the criteria (all of them taken together): everything that fails to match, including those that have nothing recorded for a criterion.  \"latest\" and \"previous\" are found before inverting; `--newest` and `--oldest` apply after.  Needs a criterion",
        body = (p.criteriaGiven = true; p.c.invert = true; fine),
      ),
      custom(
        ListState,
        ["-n", "--newest"],
        true,
        "N",
        ~"only the N newest of the activities that meet the other criteria",
        body = takeCount(p, name, value, false),
      ),
      custom(
        ListState,
        ["--oldest"],
        true,
        "N",
        ~"only the N oldest of them",
        body = takeCount(p, name, value, true),
      ),
      custom(
        ListState,
        ["--latest"],
        false,
        "",
        ~"the same as `--newest 1`",
        body = (p.criteriaGiven = true; p.c.newest = 1; fine),
      ),
      custom(
        ListState,
        ["--select", "--save"],
        false,
        "",
        ~"make what is listed the selection (needs criteria or `--all`)",
        body = (p.c.select = true; fine),
      ),
      custom(
        ListState,
        ["--rename"],
        false,
        "",
        ~"name the activities again (with no criteria and no `--all`, those of the selection): where each started and what it is called, from the places and your landmarks as they are now (after `nch landmarks --add`, say)",
        body = (p.c.rename = true; fine),
      ),
      custom(
        ListState,
        ["--delete"],
        false,
        "",
        ~"delete the activities (with no criteria and no `--all`, those of the selection) and everything made from them: coordinates, route, heart rate, impulses, efforts.  The climbs found in them stay (they are shared), and so do the names on those.  The file of an activity is forgotten as well: importing its folder again would bring the activity back.  Nothing is deleted without `-f` (it says what it would delete)",
        body = (p.c.delete = true; fine),
      ),
      forceOptionIn(ListState, c, force),
      custom(
        ListState,
        ["-v", "--verbose"],
        false,
        "",
        ~"show more of each activity: where it started (its coordinates, or \"no GPS\" if the file has no positions), the place it started and its name (made when it was imported), and the path of its file",
        body = (p.c.verbose = true; fine),
      ),
      helpFlag(ListState),
    ]
  )
  var at = 0
    # (the offered ones go before --distance: with the criteria that say what an activity is called or where)
  while at < result.opts.len and "--distance" notin result.opts[at].names:
    inc at
  for k, o in offered:
    result.opts.insert(contributedOption(o), at + k)

func finish(st: ListState): Parsed[Criteria] =
  ## What was read, if the options go together.
  func bad(why: Line): Parsed[Criteria] =
    problemWith[Criteria](why)

  var c = st.c
  c.given = st.criteriaGiven
  if c.all and c.hasFilter:
    return bad(
      ~"`--all` is every activity: it does not go with criteria (`--newest` and `--oldest` do)"
    )
  if c.force != fNo and not c.delete:
    return bad(~"`-f` goes with `--delete`")
  if c.delete and (c.select or c.verbose):
    return bad(~"`--delete` shows nothing: it does not go with `--select` or `-v`")
  if c.rename and (c.delete or c.select or c.verbose):
    return bad(
      ~"`--rename` shows nothing: it does not go with `--delete`, `--select` or `-v`"
    )
  if c.select and not (c.given or c.all):
    return bad(
      ~"`--select` keeps the activities listed as the selection, so it needs criteria or `--all`"
    )
  if st.radiusGiven and c.start.kind == nkNone and c.passes.kind == nkNone:
    c.start = Spot(kind: nkLatest) # --radius alone: around where the latest started
  if c.invert and not c.hasFilter:
    return bad(
      ~"`--invert` needs a criterion to invert (`--sports`, `--names`, `--distance` ...)"
    )
  if c.newest > 0 and c.oldest > 0:
    return bad(~"`--newest` and `--oldest` cannot be used together")
  if st.onGiven and st.rangeGiven:
    return
      bad(~"`--on` is a day of its own: it does not go with `--after` or `--before`")
  if c.afterT.isSome and c.beforeT.isSome and c.afterT.get >= c.beforeT.get:
    return bad(~"`--after` is not before `--before`")
  parsedOk(c)

proc parseArgs*(
    args: seq[string], zone: Timezone, offered: seq[Criterion] = @[]
): Parsed[Criteria] =
  ## The command line of `nch activities`.  Options with values: `--sports A B`, `--sub-sports A B`, `--names`, `--starts`,
  ## `--paths`, `--climbs` (words up to the next option), `--delete [-f]`, `--after T`, `--before T`, `--on DATE`, `--from` and `--near` (LAT,LON, a place, latest, previous), `--radius DISTANCE` (`3km`, `500m`);
  ## `--newest N` (or `-n N`), `--oldest N`, `--latest` (= `--newest 1`), `--invert`, `--all` (every activity), `--select`
  ## (keep what is listed as the selection), and `-v`/`--verbose` (what to display).  With no
  ## criterion and no `--all` it is the selection that is meant.
  parseCommand(
    args,
    criteriaSpec(offered),
    ListState(c: Criteria(), zone: zone, offered: offered),
    finish,
  )

func box*(lat, lon, radiusKm: float): Box =
  ## A box in degrees that holds the circle of `radiusKm` around the point: for the
  ## spatial index, which is asked for a box.  (A circle over a pole, or over the
  ## antimeridian, gets the whole range of longitudes.)
  let dLat = radiusKm / 110.5
  let c = cos(degToRad(lat))
  let dLon =
    if c < 0.01 or abs(lat) + dLat >= 90:
      360.0
    else:
      radiusKm / (110.5 * c)
  Box(
    minX: max(-180.0, lon - dLon),
    maxX: min(180.0, lon + dLon),
    minY: max(-90.0, lat - dLat),
    maxY: min(90.0, lat + dLat),
  )

func boxes*(lat, lon, radiusKm: float): seq[Box] =
  ## `box`, and where the circle goes past the date line (longitude 180 / -180) the part on the
  ## other side as a second box.
  let b = box(lat, lon, radiusKm)
  result.add b
  let c = cos(degToRad(lat))
  let dLat = radiusKm / 110.5
  if c < 0.01 or abs(lat) + dLat >= 90:
    return # (all longitudes already)
  let dLon = radiusKm / (110.5 * c)
  if lon - dLon < -180.0:
    result.add Box(minX: lon - dLon + 360.0, maxX: 180.0, minY: b.minY, maxY: b.maxY)
  if lon + dLon > 180.0:
    result.add Box(minX: -180.0, maxX: lon + dLon - 360.0, minY: b.minY, maxY: b.maxY)

func refersTo*(c: Criteria, r: Reference): bool =
  ## Whether any criterion is measured against the activity `r` stands for.
  let near = if r == refLatest: nkLatest else: nkPrevious
  c.start.kind == near or c.passes.kind == near or
    (c.distanceRel.isSome and c.distanceRel.get.refers == r) or
    (c.activeRel.isSome and c.activeRel.get.refers == r) or c.sportRef == r or
    c.subSportRef == r or c.nameRef == r or c.startRef == r

func usesLatest*(c: Criteria): bool =
  ## Whether a criterion refers to "latest".
  c.refersTo(refLatest)
func usesPrevious*(c: Criteria): bool =
  ## Whether a criterion refers to "previous".
  c.refersTo(refPrevious)

func withoutLatest*(c: Criteria): Criteria =
  ## The criteria that do not mention `latest` (those that mention `previous` have been
  ## resolved by then), and not `--newest/--oldest` either: the activities that meet these
  ## are those among which "latest" is found.
  result = c
  if result.start.kind == nkLatest:
    result.start = Spot()
  if result.passes.kind == nkLatest:
    result.passes = Spot()
  if result.distanceRel.isSome and result.distanceRel.get.refers == refLatest:
    result.distanceRel = none(Relative)
  if result.activeRel.isSome and result.activeRel.get.refers == refLatest:
    result.activeRel = none(Relative)
  if result.sportRef == refLatest:
    result.sportRef = refNone
  if result.subSportRef == refLatest:
    result.subSportRef = refNone
  if result.nameRef == refLatest:
    result.nameRef = refNone
  if result.startRef == refLatest:
    result.startRef = refNone
  result.invert = false
    # (`latest` is found among the activities that meet the criteria, before they are inverted)
  result.newest = 0
  result.oldest = 0

func inValues*(column, name: string, values: seq[string]): Sql =
  ## " and (a.sport in (:sport0, :sport1))": the values, as `:name0`, `:name1` ...; "none" stands for NULL (not
  ## recorded).  Nothing if there are no values.
  if values.len == 0:
    return
  var marks, parts: seq[string]
  var orNull = false
  for v in values:
    if v == "none":
      orNull = true
    else:
      let n = name & $marks.len
      marks.add ":" & n
      result.args.add (n, arg(v))
  if marks.len > 0:
    parts.add column & " in (" & marks.join(", ") & ")"
  if orNull:
    parts.add column & " is null"
  result.text = " and (" & parts.join(" or ") & ")"

func textSql*(
    column, name: string, typed, exact: seq[string], ids: seq[int64] = @[]
): Sql =
  ## " and (instr(fold(a.name), :nameT0) > 0 or a.name = :nameE0)": the typed text (folded) found anywhere in the
  ## value, whatever its case and accents (see fold.nim), or the whole value (what `latest` came to).  "none" (typed, or
  ## an exact "") is no value: null or "".  Nothing if there is nothing to match.
  if typed.len == 0 and exact.len == 0 and ids.len == 0:
    return
  var parts: seq[string]
  for i, id in ids:
    let n = name & "I" & $i
    parts.add "a.id = :" & n
    result.args.add (n, arg(id))
  for i, t in typed:
    if t.toLowerAscii == "none":
      parts.add "(" & column & " is null or " & column & " = '')"
    else:
      let n = name & "T" & $i
      parts.add "instr(fold(" & column & "), :" & n & ") > 0"
      result.args.add (n, arg(foldText(t.strip)))
  for i, e in exact:
    if e.len == 0:
      parts.add "(" & column & " is null or " & column & " = '')"
    else:
      let n = name & "E" & $i
      parts.add column & " = :" & n
      result.args.add (n, arg(e))
  result.text = " and (" & parts.join(" or ") & ")"

func pathSql*(paths: seq[string]): Sql =
  ## " and (instr(fold(f.name), :path0) > 0 or exists (select 1 from seen_file ...))": the text found in any path the
  ## file was imported from (a file can have been seen at several), or in the file's name; whatever its case and
  ## accents (see fold.nim).
  if paths.len == 0:
    return
  var parts: seq[string]
  for i, t in paths:
    let n = "path" & $i
    parts.add "(instr(fold(f.name), :" & n &
      ") > 0 or exists (select 1 from seen_file s where s.file_id = f.id and instr(fold(s.path), :" &
      n & ") > 0))"
    result.args.add (n, arg(foldText(t.strip)))
  result.text = " and (" & parts.join(" or ") & ")"

func rangeSql*(column, name: string, r: NumRange): Sql =
  ## " and a.distance_m >= :distanceLo and a.distance_m <= :distanceHi": the ends that are given, both inclusive.
  ## (Not recorded, NULL, is never in a range.)
  if r.lo.isSome:
    result.text.add " and " & column & " >= :" & name & "Lo"
    result.args.add (name & "Lo", arg(r.lo.get))
  if r.hi.isSome:
    result.text.add " and " & column & " <= :" & name & "Hi"
    result.args.add (name & "Hi", arg(r.hi.get))

func nearSql(
    centre: (float, float), km: float, idColumn, table, column, name: string
): Sql =
  ## " and (the row's box meets the circle's)", with the point and the radius bound as :NAMELon, :NAMELat and :NAMEM for
  ## the test of the distance that follows.
  let (lat, lon) = centre
  var probes: seq[string]
  for k, b in boxes(lat, lon, km):
    let n = name & "Box" & $k
    probes.add inBox(
      idColumn,
      table,
      column,
      ":" & n & "West, :" & n & "South, :" & n & "East, :" & n & "North",
    )
    result.args.add (n & "West", arg(b.minX))
    result.args.add (n & "South", arg(b.minY))
    result.args.add (n & "East", arg(b.maxX))
    result.args.add (n & "North", arg(b.maxY))
  result.text = " and (" & probes.join(" or ") & ")"
  result =
    result.with(name & "Lon", lon).with(name & "Lat", lat).with(name & "M", km * 1000)

func matchSql*(
    userIds: seq[UserId],
    c: Criteria,
    points: Points,
    columns = sqlOf("a.id"),
    extra = Sql(),
): Sql =
  ## A query for the activities of `userIds` that meet the criteria, giving
  ## `columns` (of `a`, the activity, and `f`, its file).  The one place the
  ## criteria become SQL, used to list them, to count them and to save them.
  ## `extra` is the conditions of the criteria other packages offer, each " and (...)" (`resolveOffered`).
  ## `points` are the points `--from` and `--near` came to.  Every value is bound by name (`sqltext.nim`).
  var ids: seq[int64]
  for id in userIds:
    ids.add int64(id)
  result =
    "select " & columns & " from activity a join file f on f.id = a.file_id " &
    "where f.user_id in (select value from json_each(:users))"
  result = result.with("users", jsonList(ids))
  var filt = Sql()
    # the criteria, each as " and ...": with --invert, the whole is negated
  filt = filt & inValues("a.sport", "sport", c.sports)
  filt = filt & inValues("a.sub_sport", "subSport", c.subSports)
  filt = filt & textSql("a.name", "name", c.names, c.namesExact, c.nameIds)
  filt = filt & textSql("a.start_place", "start", c.starts, c.startsExact)
  filt = filt & pathSql(c.paths)
  filt = filt & extra
  filt = filt & rangeSql("a.distance_m", "distance", c.distanceM)
  filt = filt & rangeSql("a.timer_s", "active", c.activeS)
  case c.gps
  of gfWith:
    filt = filt & " and exists (select 1 from track k where k.activity_id = a.id)"
  of gfWithout:
    filt = filt & " and not exists (select 1 from track k where k.activity_id = a.id)"
  of gfAny:
    discard
  if c.afterT.isSome:
    filt = filt & sqlOf(" and a.start_t >= :afterT").with("afterT", int64(c.afterT.get))
  if c.beforeT.isSome:
    filt =
      filt & sqlOf(" and a.start_t < :beforeT").with("beforeT", int64(c.beforeT.get))
  if points.start.isSome:
    # activities that START within the radius: the spatial index finds those in a box, and the distance on the ground
    # decides (an activity without a start is never near)
    filt =
      filt & nearSql(points.start.get, c.startKm, "a.id", "activity", "start", "start") &
      " and ST_Distance(a.start, MakePoint(:startLon, :startLat, 4326), 1) <= :startM"
  if points.passes.isSome:
    # activities whose ROUTE passes within the radius: the index of the routes (a route's row is its activity's id) finds
    # those whose box meets the circle's, and the distance on the ground from the point to the line decides
    filt =
      filt & nearSql(points.passes.get, c.passKm, "a.id", "route", "geom", "pass") &
      " and exists (select 1 from route r where r.activity_id = a.id" &
      " and ST_Distance(r.geom, MakePoint(:passLon, :passLat, 4326), 1) <= :passM)"
  # an activity that fails a test because a value is not recorded (null) fails to match, so it matches the inverse
  result =
    result & (
      if c.invert:
        " and not coalesce((1" & filt & "), 0)"
      else:
        filt
    )
  if c.newest > 0:
    result =
      result & sqlOf(" order by a.start_t desc limit :newest").with("newest", c.newest)
  if c.oldest > 0:
    result =
      result & sqlOf(" order by a.start_t asc limit :oldest").with("oldest", c.oldest)
