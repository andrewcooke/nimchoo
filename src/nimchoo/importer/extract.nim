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
## * a record without a position makes no coordinate;
## * the stretches during which the timer ran (between a timer start and the
##   next stop) are the activity's segments: disjoint intervals in time order.
##   Every coordinate lies in one.

import std/[algorithm, options, sequtils, strutils, tables]
import ../db/channel
import ../errors
import ../profile/model
import ../warnings
import ../fit/reader
import ../fit/records
import ../fit/time

{.push raises: [].}

const
  minCalendarFit* = 0x10000000'i64  ## 1998-07-03; earlier times are not UTC
  semicircleDegrees = 180.0 / 2147483648.0  ## degrees per FIT semicircle

type
  Coord* = object
    t*: int64             ## Unix seconds, UTC
    lon*, lat*: float     ## degrees
    alt*: Option[float]   ## metres

  Segment* = object
    ## A stretch during which the timer ran (a closed interval).
    startT*, endT*: int64   ## Unix seconds, UTC

  TimerEvent* = object
    t*: int64
    running*: bool          ## a start (true) or a stop (false)

  ActivityData* = object
    ## One session of a file.
    session*: int         ## position of the session message in the file
    startT*, endT*: int64   ## Unix seconds, UTC
    utcOffsetS*: Option[int]  ## local time minus UTC
    sport*, subSport*: string  ## "" if unknown
    elapsedS*, timerS*, distanceM*: Option[float]
    calories*: Option[int]
    coords*: seq[Coord]   ## in time order, one per second at most
    samples*: Samples     ## the other fields asked for (see `readActivities`), by name
    segments*: seq[Segment]  ## disjoint, in time order, covering all coords

  RawCoord = object
    c: Coord
    index: int            ## order of appearance, to keep the last of a second
    offset: int           ## file offset, for warnings

  RawSample = object
    channel: string
    s: Sample
    index: int

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
    raiseImport(ifBadTime, "session " & $index & " has no valid start time")
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

func merged(segs: seq[Segment]): seq[Segment] =
  ## Segments in time order; those that touch or overlap become one.
  for g in segs:
    if result.len > 0 and g.startT <= result[^1].endT:
      result[^1].endT = max(result[^1].endT, g.endT)
    else:
      result.add g

func segmentsOf*(startT, endT: int64, events: seq[TimerEvent]): seq[Segment] =
  ## The segments of a session lasting from `startT` to `endT`, given its timer
  ## events in time order.  A start while running and a stop while stopped
  ## change nothing; a first event that is a stop means the timer was running
  ## from the start of the session; a timer still running at the end stops
  ## there; no events at all is one segment.
  var running = events.len == 0 or not events[0].running
  var since = startT
  var found: seq[Segment]
  for e in events:
    if e.running and not running:
      running = true
      since = e.t
    elif not e.running and running:
      running = false
      found.add Segment(startT: since, endT: e.t)
  if running: found.add Segment(startT: since, endT: endT)
  for g in found.mitems:
    g.startT = max(g.startT, startT)
    g.endT = min(g.endT, endT)
  merged(found.filterIt(it.endT >= it.startT))

proc cover(segs: var seq[Segment], coords: seq[Coord], ws: var seq[Warning]) =
  ## Make every coordinate (in time order) lie in a segment: one outside all of
  ## them extends the nearest, with a warning.
  if segs.len == 0: return
  var j = 0
  for c in coords:
    while j < segs.high and c.t > segs[j].endT: inc j
    if c.t >= segs[j].startT and c.t <= segs[j].endT: continue
    # c is before segs[j] (in a gap or before the first) or after the last
    let toPrevious = if j > 0: c.t - segs[j - 1].endT else: high(int64)
    let toThis = if c.t < segs[j].startT: segs[j].startT - c.t else: c.t - segs[j].endT
    if j > 0 and toPrevious <= toThis:
      segs[j - 1].endT = c.t
    elif c.t < segs[j].startT:
      segs[j].startT = c.t
    else:
      segs[j].endT = c.t
    ws.add wkOutsideSegment, 0, "a coordinate at " & $c.t &
      " is outside the timer segments; the nearest segment is extended"
  segs = merged(segs)

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

proc uniqueSamples(raw: var seq[RawSample]): Table[string, seq[Sample]] =
  ## By channel, in time order; of several in one second the last (by appearance) is kept.
  ## (The duplicate seconds are already warned about for the coordinates.)
  raw.sort do (a, b: RawSample) -> int:
    result = cmp(a.s.t, b.s.t)
    if result == 0: result = cmp(a.index, b.index)
  for x in raw:
    let list = addr result.mgetOrPut(x.channel, @[])
    if list[].len > 0 and list[][^1].t == x.s.t: list[][^1] = x.s else: list[].add x.s

proc readActivities*(p: Profile, data: sink seq[byte], ws: var seq[Warning],
                     channels: seq[string] = @[]): seq[ActivityData]
    {.raises: [FitError, ImportError].} =
  ## The activities in a FIT file, in order of start time (`session` is the
  ## position of the session message in the file).  Warnings (the reader's and
  ## ours) are added to `ws`.  Raises FitError if the file cannot be read,
  ## ImportError if it holds no usable activity.  `channels` are `record` fields
  ## wanted besides the position: their values go to each activity's `samples`
  ## (a record that lacks one, or has an invalid value, gives none).
  var
    r = initReader(p, data)
    sessions: seq[ActivityData]
    raw: seq[RawCoord]
    rawSamples: seq[RawSample]
    timer: seq[TimerEvent]
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
        if rc.isSome: raw.add rc.get
        for name in channels:
          let v = rec.firstNum(name)
          if v.isSome:
            rawSamples.add RawSample(channel: name, s: Sample(t: fitToUnix(rec.timestamp.get), v: v.get),
                                     index: count)
        inc count
      of "event":
        if nameOf(p, rec, "event") == "timer" and rec.timestamp.isSome and
            rec.timestamp.get >= minCalendarFit:
          let kind = nameOf(p, rec, "event_type")
          if kind == "start" or kind.startsWith("stop"):
            timer.add TimerEvent(t: fitToUnix(rec.timestamp.get),
                                 running: kind == "start")
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
    raiseImport(ifNoActivity, "no activity in this file (it has no session message)")
  sessions.sort do (a, b: ActivityData) -> int:
    result = cmp(a.startT, b.startT)
    if result == 0: result = cmp(a.session, b.session)
  let coords = sortedUnique(raw, ws)
  var k = 0   # the session the coordinates are being given to
  for c in coords:
    while k + 1 < sessions.len and sessions[k + 1].startT <= c.t: inc k
    sessions[k].coords.add c
  # the other fields go to sessions the same way
  for name, list in uniqueSamples(rawSamples):
    k = 0
    for x in list:
      while k + 1 < sessions.len and sessions[k + 1].startT <= x.t: inc k
      sessions[k].samples.mgetOrPut(name, @[]).add x
  # timer events go to sessions the way coordinates do; then the segments
  timer.sort do (a, b: TimerEvent) -> int: cmp(a.t, b.t)
  var perSession = newSeq[seq[TimerEvent]](sessions.len)
  k = 0
  for e in timer:
    while k + 1 < sessions.len and sessions[k + 1].startT <= e.t: inc k
    perSession[k].add e
  for i, s in sessions.mpairs:
    s.utcOffsetS = offsetS
    s.segments = segmentsOf(s.startT, s.endT, perSession[i])
    cover(s.segments, s.coords, ws)
  sessions
