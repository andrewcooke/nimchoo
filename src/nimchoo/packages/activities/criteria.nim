## What `nch activities` is asked for: the command line parsed into criteria, and the
## criteria turned into SQL.  Pure: no database, no clock, no terminal (the time
## zone is a parameter), so all of it is tested directly.

import std/[math, options, strutils, times]
import ../fit/time
import ../confirm/confirm
import ../util/args/args
import ../db/sqltext
import ../../core/ids
import ../text/fold/fold
import ./[completion, criterion, ranges]
export ranges, criterion

{.push raises: [].}

type
  NearKind* = enum
    nkNone
    nkPoint
    nkLatest
    nkPrevious

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
    fromT*: Option[UnixTime] ## start of the activity at or after
    toT*: Option[UnixTime] ## start of the activity before (exclusive)
    gps*: GpsFilter
    invert*: bool
      ## --invert: the activities that do NOT meet the criteria (before --newest / --oldest)
    near*: NearKind
    lat*, lon*: float ## for nkPoint
    radiusKm*: float

  Relative* = object
    ## `latest~10%`: around an activity that is found when the command runs.
    refers*: Reference
    tol*: Tol

  Box* = object
    minX*, minY*, maxX*, maxY*: float ## degrees

const
  defaultRadiusKm* = 100.0
  timeFormats = [
    ("yyyy-MM-dd'T'HH:mm:ss", 1),
    ("yyyy-MM-dd HH:mm:ss", 1),
    ("yyyy-MM-dd'T'HH:mm", 60),
    ("yyyy-MM-dd HH:mm", 60),
    ("yyyy-MM-dd", 0),
  ] # (granularity in seconds; 0: a calendar day)

proc parseWhen*(s: string, zone: Timezone, isEnd: bool): Option[UnixTime] =
  ## A time typed by the user, in `zone`, as Unix seconds.  For an end (`--to`, isEnd) it is
  ## the first moment after what was named: after the day, the minute, the second.
  for (format, granule) in timeFormats:
    try:
      let dt = parse(s, format, zone)
      if not isEnd:
        return some(UnixTime(dt.toTime.toUnix))
      let after =
        if granule == 0:
          dt + initTimeInterval(days = 1)
        else:
          dt + initDuration(seconds = granule)
      return some(UnixTime(after.toTime.toUnix))
    except TimeParseError, TimeFormatParseError, ValueError, OverflowDefect:
      discard
  none(UnixTime)

func parseLatLon*(s: string): Option[(float, float)] =
  ## "38.72,-9.14": latitude, longitude, in range.
  let parts = s.split(',')
  if parts.len != 2:
    return none((float, float))
  try:
    let lat = parseFloat(parts[0].strip)
    let lon = parseFloat(parts[1].strip)
    if lat < -90 or lat > 90 or lon < -180 or lon > 180:
      return none((float, float))
    some((lat, lon))
  except ValueError:
    none((float, float))

type ListState = object
  ## What the options of `nch activities` fill in as they are read.
  c: Criteria
  help: bool
  zone: Timezone
  offered: seq[Criterion] ## the criteria other packages offer
  radiusGiven: bool ## --radius was given
  criteriaGiven: bool ## some option other than those that say what to display

func takeCount(p: var ListState, name, value: string, oldest: bool): Problem =
  ## --newest N, -n N, --oldest N.
  var n = 0
  if not parseIntIn(value, 1, high(int), n):
    return
      refuse(name & " needs a number of activities, 1 or more (not '" & value & "')")
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
    return refuse(name & " needs at least one name")
  for n in names:
    if parseReference(n) != refNone:
      if p.c.sportRef != refNone and p.c.sportRef != parseReference(n):
        return refuse("--sports: latest and previous cannot be used together")
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
    return refuse(name & " needs at least one name")
  for n in names:
    if parseReference(n) != refNone:
      if p.c.subSportRef != refNone and p.c.subSportRef != parseReference(n):
        return refuse("--sub-sports: latest and previous cannot be used together")
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
    return refuse(name & " needs some text")
  for t in found:
    if parseReference(t) != refNone:
      if ref0 != refNone and ref0 != parseReference(t):
        return refuse(name & ": latest and previous cannot be used together")
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
    return refuse(name & " needs some text")
  fine

proc takeContributed(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  ## An option that another package offers: the words are kept for it to resolve.
  p.criteriaGiven = true
  for o in p.offered:
    if name in o.doc.names:
      if o.doc.arity == aList and values.len == 0:
        return refuse(name & " needs at least one word")
      for c in p.c.contributed.mitems:
        if c.option == o.doc.names[0]:
          c.values.add values
          return fine
      p.c.contributed.add Contributed(
        option: o.doc.names[0], values: values, resolve: o.resolve
      )
      return fine
  refuse(name & " is not an option") # (cannot happen: the spec has just these)

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

proc takeDistance(p: var ListState, name, v: string): Problem {.nimcall.} =
  p.criteriaGiven = true
  if '~' in v:
    let ar = parseAround(v, parseDistance)
    if ar.isNone:
      return refuse(
        "cannot read the distance '" & v &
          "' (use 42~2, 0.5~0.1, latest~10% or previous~10%; kilometres)"
      )
    if ar.get.centre.isSome:
      p.c.distanceM = around(ar.get.centre.get, ar.get.tol)
    else:
      p.c.distanceRel = some(Relative(refers: ar.get.refers, tol: ar.get.tol))
  else:
    let r = parseRange(v, parseDistance)
    if r.isNone:
      if isBackwards(v, parseDistance):
        return refuse("the distance range '" & v & "' is backwards (smaller end first)")
      return refuse(
        "cannot read the distance range '" & v &
          "' (use 40-, 10-50, -5, 0.5-, 42~2, latest~10% or previous~10%; kilometres)"
      )
    p.c.distanceM = r.get
  fine

proc takeActive(p: var ListState, name, v: string): Problem {.nimcall.} =
  p.criteriaGiven = true
  if '~' in v:
    let ar = parseAround(v, parseInterval)
    if ar.isNone:
      return refuse(
        "cannot read the active time '" & v &
          "' (use 2h~15m, latest~10% or previous~10%)"
      )
    if ar.get.centre.isSome:
      p.c.activeS = around(ar.get.centre.get, ar.get.tol)
    else:
      p.c.activeRel = some(Relative(refers: ar.get.refers, tol: ar.get.tol))
  else:
    let r = parseRange(v, parseInterval)
    if r.isNone:
      if isBackwards(v, parseInterval):
        return
          refuse("the active time range '" & v & "' is backwards (shorter end first)")
      return refuse(
        "cannot read the active time range '" & v &
          "' (use 1h-, 30m-2h, -45m, 2h~15m, latest~10% or previous~10%; units d h m s)"
      )
    p.c.activeS = r.get
  fine

proc takeWhen(p: var ListState, v: string, isEnd: bool): Problem =
  ## --from T (the start of what is named) and --to T (the end).
  p.criteriaGiven = true
  let t = parseWhen(v, p.zone, isEnd)
  if t.isNone:
    return
      refuse("cannot read the time '" & v & "' (use 2018-08-27 or 2018-08-27T09:30)")
  if isEnd:
    p.c.toT = t
  else:
    p.c.fromT = t
  fine

func takeGps(p: var ListState, wanted: GpsFilter): Problem =
  ## --gps and --no-gps, which contradict each other.
  p.criteriaGiven = true
  if p.c.gps notin {gfAny, wanted}:
    return refuse("--gps and --no-gps cannot be used together")
  p.c.gps = wanted
  fine

func takeNear(p: var ListState, v: string): Problem =
  p.criteriaGiven = true
  if parseReference(v) == refLatest:
    p.c.near = nkLatest
  elif parseReference(v) == refPrevious:
    p.c.near = nkPrevious
  else:
    let pos = parseLatLon(v)
    if pos.isNone:
      return refuse(
        "cannot read the position '" & v & "' (use 38.72,-9.14, latest or previous)"
      )
    p.c.near = nkPoint
    (p.c.lat, p.c.lon) = pos.get
  fine

func takeRadius(p: var ListState, v: string): Problem =
  p.criteriaGiven = true
  try:
    p.c.radiusKm = parseFloat(v)
  except ValueError:
    return refuse("cannot read the radius '" & v & "' (kilometres)")
  if p.c.radiusKm <= 0:
    return refuse("the radius must be more than 0km")
  p.radiusGiven = true
  fine

func hasFilter*(c: Criteria): bool =
  ## Whether any criterion that picks activities is given (not the limits, the users or the display).
  c.sports.len > 0 or c.subSports.len > 0 or c.names.len > 0 or c.starts.len > 0 or
    c.paths.len > 0 or c.contributed.len > 0 or c.sportRef != refNone or
    c.subSportRef != refNone or c.nameRef != refNone or c.startRef != refNone or
    c.distanceM.lo.isSome or c.distanceM.hi.isSome or c.activeS.lo.isSome or
    c.activeS.hi.isSome or c.distanceRel.isSome or c.activeRel.isSome or c.fromT.isSome or
    c.toT.isSome or c.gps != gfAny or c.near != nkNone

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
        "every activity, not just the selection",
        body = (p.c.all = true; fine),
      ),
      listOption[ListState](
        ["--sports"],
        takeSports,
        "SPORT...",
        "only these sports (cycling, running, swimming ...); \"none\" means not recorded; \"latest\" or \"previous\": that activity's sport",
        completion = completesFrom(completeSports),
      ),
      listOption[ListState](
        ["--sub-sports"],
        takeSubSports,
        "SPORT...",
        "only these sub-sports (road, trail, open_water ...).  Many files say \"generic\" or nothing, so this misses some rides",
        completion = completesFrom(completeSubSports),
      ),
      listOption[ListState](
        ["--names"],
        takeNames,
        "TEXT...",
        "activities whose name contains any of the TEXTs, whatever its case or accents: --names toyo finds \"El Toyo and back\", --names toyo farellones finds either; a text with spaces is quoted; a whole number that no name contains is an activity's number (--names 737); \"none\": no name; \"latest\" or \"previous\": the same name as that activity",
      ),
      listOption[ListState](
        ["--starts"],
        takeStarts,
        "TEXT...",
        "the same for the place the activity started (\"Providencia\", \"near Lo Barnechea\"): --starts providencia",
      ),
      listOption[ListState](
        ["--paths"],
        takePaths,
        "TEXT...",
        "the same for the path of the file the activity was imported from (or any other path the same file was seen at): --paths bowman, --paths 2026-10",
      ),
      custom(
        ListState,
        ["--distance"],
        true,
        "RANGE",
        "distance in km: 40- (40 or more), 10-50, -5 (up to 5); 0.5- for half a km; 42~2 (between 40 and 44), latest~10%, previous~10%",
        body = takeDistance(p, name, value),
      ),
      custom(
        ListState,
        ["--active"],
        true,
        "RANGE",
        "active time: 1h-, 30m-2h, -45m (units d h m s, as printed); 2h~15m, latest~10%, previous~10%",
        body = takeActive(p, name, value),
      ),
      custom(
        ListState,
        ["--from"],
        true,
        "TIME",
        "activities that start at or after TIME",
        body = takeWhen(p, value, false),
      ),
      custom(
        ListState,
        ["--to"],
        true,
        "TIME",
        "activities that start before the end of TIME\n(TIME is in your time zone: 2018-08-27, 2018-08-27T09:30 or with seconds; a --to date means the whole day)",
        body = takeWhen(p, value, true),
      ),
      custom(
        ListState,
        ["--gps"],
        false,
        "",
        "only activities that have positions (a GPS track)",
        body = takeGps(p, gfWith),
      ),
      custom(
        ListState,
        ["--no-gps"],
        false,
        "",
        "only activities that have none (indoor rides, treadmill runs ...)",
        body = takeGps(p, gfWithout),
      ),
      custom(
        ListState,
        ["--near"],
        true,
        "LAT,LON",
        "activities that start within the radius of the point; --near latest: of where the latest activity started (or \"previous\")",
        body = takeNear(p, value),
      ),
      custom(
        ListState,
        ["--radius"],
        true,
        "KM",
        "radius for --near in kilometres (default: 100); on its own it means --near latest",
        body = takeRadius(p, value),
      ),
      custom(
        ListState,
        ["--invert"],
        false,
        "",
        "the activities that do NOT meet the criteria (all of them taken together): everything that fails to match, including those that have nothing recorded for a criterion.  \"latest\" and \"previous\" are found before inverting; --newest and --oldest apply after.  Needs a criterion",
        body = (p.criteriaGiven = true; p.c.invert = true; fine),
      ),
      custom(
        ListState,
        ["-n", "--newest"],
        true,
        "N",
        "only the N newest of the activities that meet the other criteria",
        body = takeCount(p, name, value, false),
      ),
      custom(
        ListState,
        ["--oldest"],
        true,
        "N",
        "only the N oldest of them",
        body = takeCount(p, name, value, true),
      ),
      custom(
        ListState,
        ["--latest"],
        false,
        "",
        "the same as --newest 1",
        body = (p.criteriaGiven = true; p.c.newest = 1; fine),
      ),
      custom(
        ListState,
        ["--select"],
        false,
        "",
        "make what is listed the selection (needs criteria or --all)",
        body = (p.c.select = true; fine),
      ),
      custom(
        ListState,
        ["--delete"],
        false,
        "",
        "delete the activities (with no criteria and no --all, those of the selection) and everything made from them: coordinates, route, heart rate, impulses, efforts.  The climbs found in them stay (they are shared), and so do the names on those.  The file of an activity is forgotten as well: importing its folder again would bring the activity back.  Nothing is deleted without -f (it says what it would delete)",
        body = (p.c.delete = true; fine),
      ),
      forceOptionIn(ListState, c, force),
      custom(
        ListState,
        ["-v", "--verbose"],
        false,
        "",
        "show more of each activity: where it started (its coordinates, or \"no GPS\" if the file has no positions), the place it started and its name (made when it was imported), and the path of its file",
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
  func bad(why: string): Parsed[Criteria] =
    problemWith[Criteria](why)

  var c = st.c
  c.given = st.criteriaGiven
  if c.all and c.hasFilter:
    return bad(
      "--all is every activity: it does not go with criteria (--newest and --oldest do)"
    )
  if c.force != fNo and not c.delete:
    return bad("-f goes with --delete")
  if c.delete and (c.select or c.verbose):
    return bad("--delete shows nothing: it does not go with --select or -v")
  if c.select and not (c.given or c.all):
    return bad(
      "--select keeps the activities listed as the selection, so it needs criteria or --all"
    )
  if st.radiusGiven and c.near == nkNone:
    c.near = nkLatest # --radius alone: around the latest
  if c.invert and not c.hasFilter:
    return
      bad("--invert needs a criterion to invert (--sports, --names, --distance ...)")
  if c.newest > 0 and c.oldest > 0:
    return bad("--newest and --oldest cannot be used together")
  if c.fromT.isSome and c.toT.isSome and c.fromT.get >= c.toT.get:
    return bad("--from is not before --to")
  parsedOk(c)

proc parseArgs*(
    args: seq[string], zone: Timezone, offered: seq[Criterion] = @[]
): Parsed[Criteria] =
  ## The command line of `nch activities`.  Options with values: `--sports A B`, `--sub-sports A B`, `--names`, `--starts`,
  ## `--paths`, `--climbs` (words up to the next option), `--delete [-f]`, `--from T`, `--to T`, `--near LAT,LON|latest`, `--radius KM`;
  ## `--newest N` (or `-n N`), `--oldest N`, `--latest` (= `--newest 1`), `--invert`, `--all` (every activity), `--select`
  ## (keep what is listed as the selection), and `-v`/`--verbose` (what to display).  With no
  ## criterion and no `--all` it is the selection that is meant.
  parseCommand(
    args,
    criteriaSpec(offered),
    ListState(c: Criteria(radiusKm: defaultRadiusKm), zone: zone, offered: offered),
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
  c.near == near or (c.distanceRel.isSome and c.distanceRel.get.refers == r) or
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
  if result.near == nkLatest:
    result.near = nkNone
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

func matchSql*(
    userIds: seq[UserId],
    c: Criteria,
    centre: Option[(float, float)],
    columns = sqlOf("a.id"),
    extra = Sql(),
): Sql =
  ## A query for the activities of `userIds` that meet the criteria, giving
  ## `columns` (of `a`, the activity, and `f`, its file).  The one place the
  ## criteria become SQL, used to list them, to count them and to save them.
  ## `extra` is the conditions of the criteria other packages offer, each " and (...)" (`resolveOffered`).
  ## `centre` is the point `--near` means.  Every value is bound by name (`sqltext.nim`).
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
    filt = filt & " and exists (select 1 from coords k where k.activity_id = a.id)"
  of gfWithout:
    filt = filt & " and not exists (select 1 from coords k where k.activity_id = a.id)"
  of gfAny:
    discard
  if c.fromT.isSome:
    filt = filt & sqlOf(" and a.start_t >= :fromT").with("fromT", int64(c.fromT.get))
  if c.toT.isSome:
    filt = filt & sqlOf(" and a.start_t < :toT").with("toT", int64(c.toT.get))
  if centre.isSome:
    let (lat, lon) = centre.get
    # activities that START within the radius: the spatial index finds those in a box, and
    # the distance on the ground decides (an activity without a start is never near)
    var probes: seq[string]
    var values = Sql()
    for k, b in boxes(lat, lon, c.radiusKm):
      let n = "box" & $k
      probes.add inBox(
        "a.id",
        "activity",
        "start",
        ":" & n & "West, :" & n & "South, :" & n & "East, :" & n & "North",
      )
      values.args.add (n & "West", arg(b.minX))
      values.args.add (n & "South", arg(b.minY))
      values.args.add (n & "East", arg(b.maxX))
      values.args.add (n & "North", arg(b.maxY))
    values.text =
      " and (" & probes.join(" or ") &
      ") and ST_Distance(a.start, MakePoint(:nearLon, :nearLat, 4326), 1) <= :nearM"
    values =
      values.with("nearLon", lon).with("nearLat", lat).with("nearM", c.radiusKm * 1000)
    filt = filt & values
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
