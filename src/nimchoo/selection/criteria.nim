## What `nch list` is asked for: the command line parsed into criteria, and the
## criteria turned into SQL.  Pure: no database, no clock, no terminal (the time
## zone is a parameter), so all of it is tested directly.

import std/[math, options, strutils, times]
import ./ranges
export ranges

{.push raises: [].}

type
  NearKind* = enum nkNone, nkPoint, nkLatest, nkPrevious

  Criteria* = object
    show*: bool               ## --show: the stored selection, no criteria
    save*: bool               ## --save: keep what is listed as the selection
    verbose*: bool            ## -v: show more of each activity (a display option)
    newest*, oldest*: int     ## only the N newest (oldest) of those that meet the other
                              ## criteria, by start time; 0: no limit
    users*: seq[string]       ## empty: the current user
    distanceM*, activeS*: NumRange   ## --distance, --active (metres, seconds; open: any)
    distanceRel*, activeRel*: Option[Relative]    ## --distance latest~T / previous~T, --active ...
    sportRef*, subSportRef*: Reference            ## --sport latest / previous, --sub-sport ...
    sports*, subSports*: seq[string]  ## only these (lower case; "none": not recorded); empty: any
    fromT*: Option[int64]     ## start of the activity at or after (Unix seconds)
    toT*: Option[int64]       ## start of the activity before (exclusive)
    near*: NearKind
    lat*, lon*: float         ## for nkPoint
    radiusKm*: float

  Relative* = object
    ## `latest~10%`: around an activity that is found when the command runs.
    refers*: Reference
    tol*: Tol

  Parsed* = object
    criteria*: Criteria
    help*: bool
    problem*: string          ## "" if the command line was fine

  Box* = object
    minX*, minY*, maxX*, maxY*: float   ## degrees

const
  defaultRadiusKm* = 100.0
  timeFormats = [
    ("yyyy-MM-dd'T'HH:mm:ss", 1), ("yyyy-MM-dd HH:mm:ss", 1),
    ("yyyy-MM-dd'T'HH:mm", 60), ("yyyy-MM-dd HH:mm", 60),
    ("yyyy-MM-dd", 0)]          # (granularity in seconds; 0: a calendar day)

proc parseWhen*(s: string, zone: Timezone, isEnd: bool): Option[int64] =
  ## A time typed by the user, in `zone`, as Unix seconds.  For an end (`--to`, isEnd) it is
  ## the first moment after what was named: after the day, the minute, the second.
  for (format, granule) in timeFormats:
    try:
      let dt = parse(s, format, zone)
      if not isEnd: return some(dt.toTime.toUnix)
      let after = if granule == 0: dt + initTimeInterval(days = 1)
                  else: dt + initDuration(seconds = granule)
      return some(after.toTime.toUnix)
    except TimeParseError, TimeFormatParseError, ValueError, OverflowDefect:
      discard
  none(int64)

func parseLatLon*(s: string): Option[(float, float)] =
  ## "38.72,-9.14": latitude, longitude, in range.
  let parts = s.split(',')
  if parts.len != 2: return none((float, float))
  try:
    let lat = parseFloat(parts[0].strip)
    let lon = parseFloat(parts[1].strip)
    if lat < -90 or lat > 90 or lon < -180 or lon > 180: return none((float, float))
    some((lat, lon))
  except ValueError:
    none((float, float))

proc parseArgs*(args: seq[string], zone: Timezone): Parsed =
  ## The command line of `nch list`.  Options with values: `--users A B C`, `--sport A B`, `--sub-sport A B` (names up to
  ## the next option), `--from T`, `--to T`, `--near LAT,LON|latest`, `--radius KM`;
  ## `--newest N` (or `-n N`), `--oldest N`, `--latest` (= `--newest 1`), and `--save` or
  ## `--show` (which takes no criteria), and `-v`/`--verbose` (what to display).
  var c = Criteria(radiusKm: defaultRadiusKm)
  var radiusGiven = false
  var criteriaGiven = false
  var i = 0
  template fail(msg: string) =
    result.problem = msg
    return
  template value(name: string): string =
    inc i
    if i >= args.len: fail(name & " needs a value")
    args[i]
  while i < args.len:
    let a = args[i]
    if a notin ["-h", "--help", "--save", "--show", "-v", "--verbose"]: criteriaGiven = true
    case a
    of "-h", "--help": result.help = true
    of "--save": c.save = true
    of "-v", "--verbose": c.verbose = true
    of "--show": c.show = true
    of "--latest": c.newest = 1
    of "--newest", "-n", "--oldest":
      let v = value(a)
      var n = 0
      try:
        n = parseInt(v)
      except ValueError:
        discard
      if n < 1: fail(a & " needs a number of activities, 1 or more (not '" & v & "')")
      if a == "--oldest": c.oldest = n else: c.newest = n
    of "--users", "--sport", "--sub-sport":
      var names: seq[string]
      inc i
      while i < args.len and not args[i].startsWith("-"):
        for name in args[i].split(','):
          if name.len > 0: names.add (if a == "--users": name else: name.toLowerAscii)
        inc i
      dec i
      if names.len == 0: fail(a & " needs at least one name")
      case a
      of "--users": c.users.add names
      of "--sport":
        for n in names:
          if parseReference(n) != refNone:
            if c.sportRef != refNone and c.sportRef != parseReference(n):
              fail("--sport: latest and previous cannot be used together")
            c.sportRef = parseReference(n)
          else: c.sports.add n
      else:
        for n in names:
          if parseReference(n) != refNone:
            if c.subSportRef != refNone and c.subSportRef != parseReference(n):
              fail("--sub-sport: latest and previous cannot be used together")
            c.subSportRef = parseReference(n)
          else: c.subSports.add n
    of "--distance":
      let v = value("--distance")
      if '~' in v:
        let ar = parseAround(v, parseDistance)
        if ar.isNone: fail("cannot read the distance '" & v & "' (use 42~2, 0.5~0.1, latest~10% or previous~10%; kilometres)")
        if ar.get.centre.isSome: c.distanceM = around(ar.get.centre.get, ar.get.tol)
        else: c.distanceRel = some(Relative(refers: ar.get.refers, tol: ar.get.tol))
      else:
        let r = parseRange(v, parseDistance)
        if r.isNone:
          if isBackwards(v, parseDistance): fail("the distance range '" & v & "' is backwards (smaller end first)")
          fail("cannot read the distance range '" & v & "' (use 40-, 10-50, -5, 0.5-, 42~2, latest~10% or previous~10%; kilometres)")
        c.distanceM = r.get
    of "--active":
      let v = value("--active")
      if '~' in v:
        let ar = parseAround(v, parseInterval)
        if ar.isNone: fail("cannot read the active time '" & v & "' (use 2h~15m, latest~10% or previous~10%)")
        if ar.get.centre.isSome: c.activeS = around(ar.get.centre.get, ar.get.tol)
        else: c.activeRel = some(Relative(refers: ar.get.refers, tol: ar.get.tol))
      else:
        let r = parseRange(v, parseInterval)
        if r.isNone:
          if isBackwards(v, parseInterval): fail("the active time range '" & v & "' is backwards (shorter end first)")
          fail("cannot read the active time range '" & v & "' (use 1h-, 30m-2h, -45m, 2h~15m, latest~10% or previous~10%; units d h m s)")
        c.activeS = r.get
    of "--from":
      let v = value("--from")
      let t = parseWhen(v, zone, isEnd = false)
      if t.isNone: fail("cannot read the time '" & v & "' (use 2018-08-27 or 2018-08-27T09:30)")
      c.fromT = t
    of "--to":
      let v = value("--to")
      let t = parseWhen(v, zone, isEnd = true)
      if t.isNone: fail("cannot read the time '" & v & "' (use 2018-08-27 or 2018-08-27T09:30)")
      c.toT = t
    of "--near":
      let v = value("--near")
      if parseReference(v) == refLatest:
        c.near = nkLatest
      elif parseReference(v) == refPrevious:
        c.near = nkPrevious
      else:
        let p = parseLatLon(v)
        if p.isNone: fail("cannot read the position '" & v & "' (use 38.72,-9.14, latest or previous)")
        c.near = nkPoint
        (c.lat, c.lon) = p.get
    of "--radius":
      let v = value("--radius")
      try:
        c.radiusKm = parseFloat(v)
      except ValueError:
        fail("cannot read the radius '" & v & "' (kilometres)")
      if c.radiusKm <= 0: fail("the radius must be more than 0km")
      radiusGiven = true
    else:
      fail("unexpected argument " & a)
    inc i
  if c.show:
    if c.save: fail("--show shows the stored selection: it cannot be combined with --save")
    if criteriaGiven: fail("--show takes no criteria (it shows the stored selection)")
  if radiusGiven and c.near == nkNone: c.near = nkLatest   # --radius alone: around the latest
  if c.newest > 0 and c.oldest > 0: fail("--newest and --oldest cannot be used together")
  if c.fromT.isSome and c.toT.isSome and c.fromT.get >= c.toT.get:
    fail("--from is not before --to")
  result.criteria = c

func box*(lat, lon, radiusKm: float): Box =
  ## A box in degrees that holds the circle of `radiusKm` around the point: for the
  ## spatial index, which is asked for a box.  (A circle over a pole, or over the
  ## antimeridian, gets the whole range of longitudes.)
  let dLat = radiusKm / 110.5
  let c = cos(degToRad(lat))
  let dLon = if c < 0.01 or abs(lat) + dLat >= 90: 360.0 else: radiusKm / (110.5 * c)
  Box(minX: max(-180.0, lon - dLon), maxX: min(180.0, lon + dLon),
      minY: max(-90.0, lat - dLat), maxY: min(90.0, lat + dLat))

func boxes*(lat, lon, radiusKm: float): seq[Box] =
  ## `box`, and where the circle goes past the date line (longitude 180 / -180) the part on the
  ## other side as a second box.
  let b = box(lat, lon, radiusKm)
  result.add b
  let c = cos(degToRad(lat))
  let dLat = radiusKm / 110.5
  if c < 0.01 or abs(lat) + dLat >= 90: return           # (all longitudes already)
  let dLon = radiusKm / (110.5 * c)
  if lon - dLon < -180.0:
    result.add Box(minX: lon - dLon + 360.0, maxX: 180.0, minY: b.minY, maxY: b.maxY)
  if lon + dLon > 180.0:
    result.add Box(minX: -180.0, maxX: lon + dLon - 360.0, minY: b.minY, maxY: b.maxY)

func deg(x: float): string = formatFloat(x, ffDecimal, 7)

func refersTo*(c: Criteria, r: Reference): bool =
  ## Whether any criterion is measured against the activity `r` stands for.
  let near = if r == refLatest: nkLatest else: nkPrevious
  c.near == near or (c.distanceRel.isSome and c.distanceRel.get.refers == r) or
    (c.activeRel.isSome and c.activeRel.get.refers == r) or c.sportRef == r or c.subSportRef == r

func usesLatest*(c: Criteria): bool = c.refersTo(refLatest)
func usesPrevious*(c: Criteria): bool = c.refersTo(refPrevious)

func withoutLatest*(c: Criteria): Criteria =
  ## The criteria that do not mention `latest` (those that mention `previous` have been
  ## resolved by then), and not `--newest/--oldest` either: the activities that meet these
  ## are those among which "latest" is found.
  result = c
  if result.near == nkLatest: result.near = nkNone
  if result.distanceRel.isSome and result.distanceRel.get.refers == refLatest:
    result.distanceRel = none(Relative)
  if result.activeRel.isSome and result.activeRel.get.refers == refLatest:
    result.activeRel = none(Relative)
  if result.sportRef == refLatest: result.sportRef = refNone
  if result.subSportRef == refLatest: result.subSportRef = refNone
  result.newest = 0
  result.oldest = 0

func inValues*(column: string, values: seq[string]): string =
  ## " and a.sport in ('cycling', 'running')": the values, quoted; "none" stands for
  ## NULL (not recorded).  Nothing if there are no values.
  if values.len == 0: return ""
  var quoted, parts: seq[string]
  var orNull = false
  for v in values:
    if v == "none": orNull = true
    else: quoted.add "'" & v.replace("'", "''") & "'"
  if quoted.len > 0: parts.add column & " in (" & quoted.join(", ") & ")"
  if orNull: parts.add column & " is null"
  " and (" & parts.join(" or ") & ")"

func rangeSql*(column: string, r: NumRange): string =
  ## " and a.distance_m >= 40000.000 and a.distance_m <= 50000.000": the ends that are
  ## given, both inclusive.  (Not recorded, NULL, is never in a range.)
  if r.lo.isSome: result.add " and " & column & " >= " & formatFloat(r.lo.get, ffDecimal, 3)
  if r.hi.isSome: result.add " and " & column & " <= " & formatFloat(r.hi.get, ffDecimal, 3)

func matchSql*(userIds: seq[int64], c: Criteria, centre: Option[(float, float)],
               columns = "a.id"): string =
  ## A query for the activities of `userIds` that meet the criteria, giving
  ## `columns` (of `a`, the activity, and `f`, its file).  The one place the
  ## criteria become SQL, used to list them, to count them and to save them.
  ## `centre` is the point `--near` means.  (Only numbers are put into the text;
  ## names have been turned into ids.)
  var ids: seq[string]
  for id in userIds: ids.add $id
  result = "select " & columns & " from activity a join file f on f.id = a.file_id " &
    "where f.user_id in (" & ids.join(", ") & ")"
  result.add inValues("a.sport", c.sports)
  result.add inValues("a.sub_sport", c.subSports)
  result.add rangeSql("a.distance_m", c.distanceM)
  result.add rangeSql("a.timer_s", c.activeS)
  if c.fromT.isSome: result.add " and a.start_t >= " & $c.fromT.get
  if c.toT.isSome: result.add " and a.start_t < " & $c.toT.get
  if centre.isSome:
    let (lat, lon) = centre.get
    # activities that START within the radius: the spatial index finds those in a box, and
    # the distance on the ground decides (an activity without a start is never near)
    var probes: seq[string]
    for b in boxes(lat, lon, c.radiusKm):
      probes.add "a.id in (select ROWID from SpatialIndex where f_table_name = 'activity' and " &
        "f_geometry_column = 'start' and search_frame = BuildMbr(" &
        deg(b.minX) & ", " & deg(b.minY) & ", " & deg(b.maxX) & ", " & deg(b.maxY) & "))"
    result.add " and (" & probes.join(" or ") & ") and ST_Distance(a.start, MakePoint(" &
      deg(lon) & ", " & deg(lat) & ", 4326), 1) <= " & deg(c.radiusKm * 1000)
  if c.newest > 0: result.add " order by a.start_t desc limit " & $c.newest
  if c.oldest > 0: result.add " order by a.start_t asc limit " & $c.oldest

func saveSql*(owner: int64, match: string): string =
  ## The statement that makes the activities of the query `match` (which gives
  ## a column `id` first) the selection of `owner`.
  "insert into selection(user_id, activity_id) select " & $owner & ", id from (" & match & ")"
