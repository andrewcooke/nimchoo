## Activities from a FIT file: one per session, each with its summary and its
## coordinates.  Pure: it reads and decodes, and knows nothing of databases.
##
## Rules (see TODO.md, "Schema direction"):
## * a file with no `session` message is refused;
## * timestamps below `minCalendarFit` are not calendar times (they count from
##   the device's power-on, FIT spec): such records are dropped with a warning,
##   and a session starting at such a time refuses the file;
## * a record goes to the last session starting at or before it (records
##   before the first session go to the first), so none are lost;
## * records are put in time order, records in the same second keep the last;
## * a record without a position makes no coordinate.

import std/[algorithm, options]
import ../errors
import ../profile/model
import ../warnings
import ./reader
import ./records
import ./time

{.push raises: [].}

const
  minCalendarFit* = 0x10000000'i64  ## 1998-07-03; earlier times are not UTC
  semicircleDegrees = 180.0 / 2147483648.0  ## degrees per FIT semicircle

type
  Coord* = object
    t*: int64             ## Unix seconds, UTC
    lon*, lat*: float     ## degrees
    alt*: Option[float]   ## metres

  ActivityData* = object
    ## One session of a file.
    session*: int         ## position of the session message in the file
    startT*, endT*: int64   ## Unix seconds, UTC
    utcOffsetS*: Option[int]  ## local time minus UTC
    sport*, subSport*: string  ## "" if unknown
    elapsedS*, timerS*, distanceM*: Option[float]
    calories*: Option[int]
    coords*: seq[Coord]   ## in time order, one per second at most

  RawCoord = object
    c: Coord
    index: int            ## order of appearance, to keep the last of a second
    offset: int           ## file offset, for warnings

func firstNum(r: Record, name: string): Option[float] =
  ## First value of a numeric field.
  let f = r.field(name)
  if f.isSome:
    case f.get.kind
    of vkInt:
      if f.get.ints.len > 0: return some(float(f.get.ints[0]))
    of vkFloat:
      if f.get.floats.len > 0: return some(f.get.floats[0])
    of vkString: discard

func firstInt(r: Record, name: string): Option[int64] =
  let f = r.field(name)
  if f.isSome and f.get.kind == vkInt and f.get.ints.len > 0:
    return some(f.get.ints[0])

func nameOf(p: Profile, r: Record, field: string): string =
  ## The profile name of an enumerated field ("" if the record lacks it).
  let f = r.field(field)
  if f.isSome: valueName(p, f.get) else: ""

func sessionOf(p: Profile, r: Record, index: int): ActivityData
    {.raises: [ImportError].} =
  ## The summary part of an activity from a session record.
  result = ActivityData(session: index)
  let start = r.firstInt("start_time")
  if start.isNone or start.get < minCalendarFit:
    raiseImport("session " & $index & " has no valid start time")
  result.startT = fitToUnix(start.get)
  let finish = if r.timestamp.isSome: r.timestamp.get else: start.get
  result.endT = fitToUnix(max(finish, start.get))
  result.sport = nameOf(p, r, "sport")
  result.subSport = nameOf(p, r, "sub_sport")
  result.elapsedS = r.firstNum("total_elapsed_time")
  result.timerS = r.firstNum("total_timer_time")
  result.distanceM = r.firstNum("total_distance")
  let cal = r.firstNum("total_calories")
  if cal.isSome: result.calories = some(int(cal.get))

func coordOf(r: Record, t: int64, index, offset: int): Option[RawCoord] =
  ## The coordinate of a record, if it has a position.
  let lat = r.firstInt("position_lat")
  let lon = r.firstInt("position_long")
  if lat.isNone or lon.isNone: return
  var alt = r.firstNum("enhanced_altitude")
  if alt.isNone: alt = r.firstNum("altitude")
  some(RawCoord(
    c: Coord(t: t, lon: float(lon.get) * semicircleDegrees,
             lat: float(lat.get) * semicircleDegrees, alt: alt),
    index: index, offset: offset))

proc sortedUnique(raw: var seq[RawCoord], ws: var seq[Warning]): seq[Coord] =
  ## Time order; of several in one second the last (by appearance) is kept.
  raw.sort do (a, b: RawCoord) -> int:
    result = cmp(a.c.t, b.c.t)
    if result == 0: result = cmp(a.index, b.index)
  for i, rc in raw:
    if result.len > 0 and result[^1].t == rc.c.t:
      ws.add wkDuplicateTime, rc.offset, "several records at second " &
        $rc.c.t & "; the last is kept"
      result[^1] = rc.c
    else:
      result.add rc.c

proc readActivities*(p: Profile, data: sink seq[byte],
                     ws: var seq[Warning]): seq[ActivityData]
    {.raises: [FitError, ImportError].} =
  ## The activities in a FIT file, in order of start time (`session` is the
  ## position of the session message in the file).  Warnings (the reader's and ours) are added to `ws`.  Raises FitError if
  ## the file cannot be read, ImportError if it holds no usable activity.
  var
    r = initReader(p, data)
    sessions: seq[ActivityData]
    raw: seq[RawCoord]
    offsetS = none(int)
    count = 0
  try:
    for ev in r.events(p):
      if ev.kind != evRecord: continue
      let rec = ev.record
      case rec.name
      of "record":
        if rec.timestamp.isNone or rec.timestamp.get < minCalendarFit:
          ws.add wkInvalidTime, ev.offset, "record without a calendar time"
          continue
        let rc = coordOf(rec, fitToUnix(rec.timestamp.get), count, ev.offset)
        inc count
        if rc.isSome: raw.add rc.get
      of "session":
        sessions.add sessionOf(p, rec, sessions.len)
      of "activity":
        let local = rec.firstInt("local_timestamp")
        if offsetS.isNone and local.isSome and rec.timestamp.isSome:
          offsetS = some(int(local.get - rec.timestamp.get))
      else: discard
  finally:
    ws.add r.warnings
  if sessions.len == 0:
    raiseImport("no activity in this file (it has no session message)")
  sessions.sort do (a, b: ActivityData) -> int:
    result = cmp(a.startT, b.startT)
    if result == 0: result = cmp(a.session, b.session)
  let coords = sortedUnique(raw, ws)
  var k = 0   # the session the coordinates are being given to
  for c in coords:
    while k + 1 < sessions.len and sessions[k + 1].startT <= c.t: inc k
    sessions[k].coords.add c
  for s in sessions.mitems: s.utcOffsetS = offsetS
  sessions
