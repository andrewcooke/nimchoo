## What `nch activities` is asked for: the command line parsed into criteria, and the
## criteria turned into SQL.  Pure: no database, no clock, no terminal (the time
## zone is a parameter), so all of it is tested directly.

import std/[math, options, strutils, times]
import ../fit/time
import ../cli/args
import ../db/sqltext
import ../ids
import ../fold
import ./ranges
export ranges

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
    force*: bool ## -f: really do it (with --delete)
    importPaths*: seq[string]
      ## --import: the files and folders to import (an action, not a criterion)
    quiet*, slow*: bool ## -q, --slow: how to import
    jobs*: int ## -j: threads to import with (0: the default)
    verbose*: bool ## -v: show more of each activity (a display option)
    calendar*: bool ## --calendar: show the activities on a calendar (a display option)
    newest*, oldest*: int
      ## only the N newest (oldest) of those that meet the other
      ## criteria, by start time; 0: no limit
    distanceM*, activeS*: NumRange ## --distance, --active (metres, seconds; open: any)
    distanceRel*, activeRel*: Option[Relative]
      ## --distance latest~T / previous~T, --active ...
    sportRef*, subSportRef*: Reference ## --sport latest / previous, --sub-sport ...
    sports*, subSports*: seq[string]
      ## only these (lower case; "none": not recorded); empty: any
    nameRef*, startRef*: Reference ## --name latest / previous, --start ...
    names*, starts*: seq[string]
      ## --name, --start: text found in the name (the start place), whatever its case and
      ## accents; "none": nothing; empty: any
    namesExact*, startsExact*: seq[string]
      ## what `latest` / `previous` came to: the whole value ("" is none)
    paths*: seq[string]
      ## --path: text found in a path the file was imported from (or in its name)
    climbs*: seq[string]
      ## --climb: text found in the name of a climb the activity has an effort on
    climbIds*: seq[int64]
      ## ... which climbs those are (worked out when the command runs, from the names as shown)
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

  Parsed* = object
    criteria*: Criteria
    help*: bool
    problem*: string ## "" if the command line was fine

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
  radiusGiven: bool ## --radius was given
  criteriaGiven: bool ## some option other than those that say what to display

func takeCount(p: var ListState, name, value: string, oldest: bool): string =
  ## --newest N, -n N, --oldest N.
  var n = 0
  if not parseIntIn(value, 1, high(int), n):
    return name & " needs a number of activities, 1 or more (not '" & value & "')"
  p.criteriaGiven = true
  if oldest:
    p.c.oldest = n
  else:
    p.c.newest = n
  ""

func splitNames(values: seq[string], lower: bool): seq[string] =
  ## Names, separated by spaces or commas.
  for v in values:
    for name in v.split(','):
      if name.len > 0:
        result.add (if lower: name.toLowerAscii else: name)

proc takeSports(
    p: var ListState, name: string, values: seq[string]
): string {.nimcall.} =
  p.criteriaGiven = true
  let names = splitNames(values, true)
  if names.len == 0:
    return name & " needs at least one name"
  for n in names:
    if parseReference(n) != refNone:
      if p.c.sportRef != refNone and p.c.sportRef != parseReference(n):
        return "--sport: latest and previous cannot be used together"
      p.c.sportRef = parseReference(n)
    else:
      p.c.sports.add n
  ""

proc takeSubSports(
    p: var ListState, name: string, values: seq[string]
): string {.nimcall.} =
  p.criteriaGiven = true
  let names = splitNames(values, true)
  if names.len == 0:
    return name & " needs at least one name"
  for n in names:
    if parseReference(n) != refNone:
      if p.c.subSportRef != refNone and p.c.subSportRef != parseReference(n):
        return "--sub-sport: latest and previous cannot be used together"
      p.c.subSportRef = parseReference(n)
    else:
      p.c.subSports.add n
  ""

proc takeTexts(
    p: var ListState,
    name: string,
    values: seq[string],
    texts: var seq[string],
    ref0: var Reference,
): string =
  p.criteriaGiven = true
  var found: seq[string]
  for v in values:
    for part in v.split(','):
      if part.strip.len > 0:
        found.add part.strip
  if found.len == 0:
    return name & " needs some text"
  for t in found:
    if parseReference(t) != refNone:
      if ref0 != refNone and ref0 != parseReference(t):
        return name & ": latest and previous cannot be used together"
      ref0 = parseReference(t)
    else:
      texts.add t
  ""

proc takeNames(
    p: var ListState, name: string, values: seq[string]
): string {.nimcall.} =
  takeTexts(p, name, values, p.c.names, p.c.nameRef)

proc takeStarts(
    p: var ListState, name: string, values: seq[string]
): string {.nimcall.} =
  takeTexts(p, name, values, p.c.starts, p.c.startRef)

proc takePaths(
    p: var ListState, name: string, values: seq[string]
): string {.nimcall.} =
  p.criteriaGiven = true
  for v in values:
    for part in v.split(','):
      if part.strip.len > 0:
        p.c.paths.add part.strip
  if p.c.paths.len == 0:
    return name & " needs some text"
  ""

proc takeClimbs(
    p: var ListState, name: string, values: seq[string]
): string {.nimcall.} =
  p.criteriaGiven = true
  for v in values:
    for part in v.split(','):
      if part.strip.len > 0:
        p.c.climbs.add part.strip
  if p.c.climbs.len == 0:
    return name & " needs some text"
  ""

proc takeJobs(p: var ListState, name, value: string): string =
  var n = 0
  if not parseIntIn(value, 1, 256, n):
    return valueIs(name, "a number of threads, 1 to 256", value)
  p.c.jobs = n
  ""

proc takeImport(
    p: var ListState, name: string, values: seq[string]
): string {.nimcall.} =
  p.c.importPaths.add values
  if p.c.importPaths.len == 0:
    return name & " needs at least one path"
  ""

proc takeDistance(p: var ListState, name, v: string): string {.nimcall.} =
  p.criteriaGiven = true
  if '~' in v:
    let ar = parseAround(v, parseDistance)
    if ar.isNone:
      return
        "cannot read the distance '" & v &
        "' (use 42~2, 0.5~0.1, latest~10% or previous~10%; kilometres)"
    if ar.get.centre.isSome:
      p.c.distanceM = around(ar.get.centre.get, ar.get.tol)
    else:
      p.c.distanceRel = some(Relative(refers: ar.get.refers, tol: ar.get.tol))
  else:
    let r = parseRange(v, parseDistance)
    if r.isNone:
      if isBackwards(v, parseDistance):
        return "the distance range '" & v & "' is backwards (smaller end first)"
      return
        "cannot read the distance range '" & v &
        "' (use 40-, 10-50, -5, 0.5-, 42~2, latest~10% or previous~10%; kilometres)"
    p.c.distanceM = r.get
  ""

proc takeActive(p: var ListState, name, v: string): string {.nimcall.} =
  p.criteriaGiven = true
  if '~' in v:
    let ar = parseAround(v, parseInterval)
    if ar.isNone:
      return
        "cannot read the active time '" & v &
        "' (use 2h~15m, latest~10% or previous~10%)"
    if ar.get.centre.isSome:
      p.c.activeS = around(ar.get.centre.get, ar.get.tol)
    else:
      p.c.activeRel = some(Relative(refers: ar.get.refers, tol: ar.get.tol))
  else:
    let r = parseRange(v, parseInterval)
    if r.isNone:
      if isBackwards(v, parseInterval):
        return "the active time range '" & v & "' is backwards (shorter end first)"
      return
        "cannot read the active time range '" & v &
        "' (use 1h-, 30m-2h, -45m, 2h~15m, latest~10% or previous~10%; units d h m s)"
    p.c.activeS = r.get
  ""

proc takeWhen(p: var ListState, v: string, isEnd: bool): string =
  ## --from T (the start of what is named) and --to T (the end).
  p.criteriaGiven = true
  let t = parseWhen(v, p.zone, isEnd)
  if t.isNone:
    return "cannot read the time '" & v & "' (use 2018-08-27 or 2018-08-27T09:30)"
  if isEnd:
    p.c.toT = t
  else:
    p.c.fromT = t
  ""

func takeGps(p: var ListState, wanted: GpsFilter): string =
  ## --gps and --no-gps, which contradict each other.
  p.criteriaGiven = true
  if p.c.gps notin {gfAny, wanted}:
    return "--gps and --no-gps cannot be used together"
  p.c.gps = wanted
  ""

func takeNear(p: var ListState, v: string): string =
  p.criteriaGiven = true
  if parseReference(v) == refLatest:
    p.c.near = nkLatest
  elif parseReference(v) == refPrevious:
    p.c.near = nkPrevious
  else:
    let pos = parseLatLon(v)
    if pos.isNone:
      return
        "cannot read the position '" & v & "' (use 38.72,-9.14, latest or previous)"
    p.c.near = nkPoint
    (p.c.lat, p.c.lon) = pos.get
  ""

func takeRadius(p: var ListState, v: string): string =
  p.criteriaGiven = true
  try:
    p.c.radiusKm = parseFloat(v)
  except ValueError:
    return "cannot read the radius '" & v & "' (kilometres)"
  if p.c.radiusKm <= 0:
    return "the radius must be more than 0km"
  p.radiusGiven = true
  ""

func hasFilter*(c: Criteria): bool =
  ## Whether any criterion that picks activities is given (not the limits, the users or the display).
  c.sports.len > 0 or c.subSports.len > 0 or c.names.len > 0 or c.starts.len > 0 or
    c.paths.len > 0 or c.climbs.len > 0 or c.sportRef != refNone or
    c.subSportRef != refNone or c.nameRef != refNone or c.startRef != refNone or
    c.distanceM.lo.isSome or c.distanceM.hi.isSome or c.activeS.lo.isSome or
    c.activeS.hi.isSome or c.distanceRel.isSome or c.activeRel.isSome or c.fromT.isSome or
    c.toT.isSome or c.gps != gfAny or c.near != nkNone

proc parseArgs*(args: seq[string], zone: Timezone): Parsed =
  ## The command line of `nch activities`.  Options with values: `--sport A B`, `--sub-sport A B`, `--name`, `--start`,
  ## `--path`, `--climb` (words up to the next option), `--delete [-f]`, `--from T`, `--to T`, `--near LAT,LON|latest`, `--radius KM`;
  ## `--newest N` (or `-n N`), `--oldest N`, `--latest` (= `--newest 1`), `--invert`, `--all` (every activity), `--select`
  ## (keep what is listed as the selection), and `-v`/`--verbose` and `--calendar` (what to display).  With no
  ## criterion and no `--all` it is the selection that is meant.
  var st = ListState(c: Criteria(radiusKm: defaultRadiusKm), zone: zone)
  let newestOption =
    custom(ListState, ["--newest", "-n"], true, takeCount(p, name, value, false))
  let oldestOption =
    custom(ListState, ["--oldest"], true, takeCount(p, name, value, true))
  let latestOption =
    custom(ListState, ["--latest"], false, (p.criteriaGiven = true; p.c.newest = 1; ""))
  let spec = Spec[ListState](
    opts: @[
      flag(ListState, ["-h", "--help"], help),
      custom(ListState, ["--select"], false, (p.c.select = true; "")),
      custom(ListState, ["--all"], false, (p.c.all = true; "")),
      custom(ListState, ["--delete"], false, (p.c.delete = true; "")),
      custom(ListState, ["-f", "--force"], false, (p.c.force = true; "")),
      listOption[ListState](["--import"], takeImport),
      custom(ListState, ["-q", "--quiet"], false, (p.c.quiet = true; "")),
      custom(ListState, ["--slow"], false, (p.c.slow = true; "")),
      custom(ListState, ["-j", "--jobs"], true, takeJobs(p, name, value)),
      custom(ListState, ["-v", "--verbose"], false, (p.c.verbose = true; "")),
      custom(ListState, ["--calendar"], false, (p.c.calendar = true; "")),
      custom(
        ListState, ["--invert"], false, (p.criteriaGiven = true; p.c.invert = true; "")
      ),
      latestOption,
      newestOption,
      oldestOption,
      listOption[ListState](["--sport"], takeSports),
      listOption[ListState](["--sub-sport"], takeSubSports),
      listOption[ListState](["--name"], takeNames),
      listOption[ListState](["--start"], takeStarts),
      listOption[ListState](["--path"], takePaths),
      listOption[ListState](["--climb"], takeClimbs),
      custom(ListState, ["--distance"], true, takeDistance(p, name, value)),
      custom(ListState, ["--active"], true, takeActive(p, name, value)),
      custom(ListState, ["--from"], true, takeWhen(p, value, false)),
      custom(ListState, ["--to"], true, takeWhen(p, value, true)),
      custom(ListState, ["--gps"], false, takeGps(p, gfWith)),
      custom(ListState, ["--no-gps"], false, takeGps(p, gfWithout)),
      custom(ListState, ["--near"], true, takeNear(p, value)),
      custom(ListState, ["--radius"], true, takeRadius(p, value)),
    ]
  )
  template fail(msg: string) =
    result.problem = msg
    return

  let why = parseOptions(args, spec, st)
  if why.len > 0:
    fail(why)
  result.help = st.help
  var c = st.c
  c.given = st.criteriaGiven
  if c.all and c.hasFilter:
    fail(
      "--all is every activity: it does not go with criteria (--newest and --oldest do)"
    )
  if c.importPaths.len > 0:
    if c.given or c.all or c.select or c.delete or c.force or c.calendar or c.verbose or
        c.invert:
      fail(
        "--import takes only -q, --slow and -j: it does not go with criteria, --all, --select, --delete, -v or --calendar"
      )
  elif c.quiet or c.slow or c.jobs > 0:
    fail("-q, --slow and -j go with --import")
  if c.force and not c.delete:
    fail("-f goes with --delete")
  if c.delete and (c.select or c.calendar or c.verbose):
    fail("--delete shows nothing: it does not go with --select, --calendar or -v")
  if c.select and not (c.given or c.all):
    fail(
      "--select keeps the activities listed as the selection, so it needs criteria or --all"
    )
  if st.radiusGiven and c.near == nkNone:
    c.near = nkLatest # --radius alone: around the latest
  if c.invert and not c.hasFilter:
    fail("--invert needs a criterion to invert (--sport, --name, --distance ...)")
  if c.newest > 0 and c.oldest > 0:
    fail("--newest and --oldest cannot be used together")
  if c.fromT.isSome and c.toT.isSome and c.fromT.get >= c.toT.get:
    fail("--from is not before --to")
  result.criteria = c

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

func textSql*(column, name: string, typed, exact: seq[string]): Sql =
  ## " and (instr(fold(a.name), :nameT0) > 0 or a.name = :nameE0)": the typed text (folded) found anywhere in the
  ## value, whatever its case and accents (see fold.nim), or the whole value (what `latest` came to).  "none" (typed, or
  ## an exact "") is no value: null or "".  Nothing if there is nothing to match.
  if typed.len == 0 and exact.len == 0:
    return
  var parts: seq[string]
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
): Sql =
  ## A query for the activities of `userIds` that meet the criteria, giving
  ## `columns` (of `a`, the activity, and `f`, its file).  The one place the
  ## criteria become SQL, used to list them, to count them and to save them.
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
  filt = filt & textSql("a.name", "name", c.names, c.namesExact)
  filt = filt & textSql("a.start_place", "start", c.starts, c.startsExact)
  filt = filt & pathSql(c.paths)
  if c.climbs.len > 0:
    # the activities that have an effort on one of the climbs (ids worked out from the names as shown, with no match: none)
    var climbIds: seq[int64]
    for id in c.climbIds:
      climbIds.add id
    filt =
      filt & (
        if climbIds.len == 0:
          sqlOf(" and 0")
        else:
          sqlOf(
            " and exists (select 1 from effort e where e.activity_id = a.id and e.sector_id in (select value from json_each(:climbs)))"
          )
            .with("climbs", jsonList(climbIds))
      )
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

func saveSql*(owner: UserId, match: Sql): Sql =
  ## The statement that makes the activities of the query `match` (which gives
  ## a column `id` first) the selection of `owner`.
  sqlOf("insert into selection(user_id, activity_id) select :owner, id from (").with(
    "owner", owner
  ) & match & ")"
