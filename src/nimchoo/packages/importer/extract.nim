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
##   next stop) are the activity's timer segments; those the device paused by
##   itself and the rider hardly left (stretch.nim) are joined into one, so the
##   activity's segments are stretches of riding: disjoint intervals in time
##   order.  Every coordinate lies in one.

import std/[algorithm, options, sequtils, strformat, strutils, tables]
import ./channel
import ../../core/errors
import ../fit/model
import ../util/profiling/profiling
import ../util/warnings/warnings
import ../fit/reader
import ../fit/records
import ../fit/time
import ../geo/geo
import ./stretch
import ./[clean, coord]
export coord

{.push raises: [].}

const
  minCalendarFit* = FitTime(0x10000000) ## 1998-07-03; earlier times are not UTC
  maxUtcOffsetS = 86_400 ## a local time more than a day from UTC is not a time zone

type
  Segment* = object
    ## A stretch of riding (a closed interval): a stretch during which the timer ran,
    ## or several of them joined across pauses the rider did not mean (see `joinStretches`).
    startT*, endT*: UnixTime
    startedBy*, endedBy*: Trigger
      ## who started and stopped the timer that began and ended it.  A session's
      ## own start and end are no timer events and have the default; the gaps
      ## between segments are what these are looked at for.

  TimerEvent* = object
    t*: UnixTime
    running*: bool ## a start (true) or a stop (false)
    trigger*: Trigger

  ActivityData* = object ## One session of a file.
    session*: int ## position of the session message in the file
    startT*, endT*: UnixTime
    utcOffsetS*: Option[int] ## local time minus UTC
    sport*, subSport*: string ## "" if unknown
    elapsedS*, timerS*, distanceM*: Option[float]
    calories*: Option[int]
    coords*: seq[Coord] ## in time order, one per second at most
    samples*: Samples ## the other fields asked for (see `readActivities`), by name
    segments*: seq[Segment]
      ## stretches of riding: disjoint, in time order, covering all coords

  RawCoord = object
    c: Coord
    index: int ## order of appearance, to keep the last of a second
    offset: int ## file offset, for warnings

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
      if f.get.ints.len > 0:
        return some(float(f.get.ints[0]))
    of vkFloat:
      if f.get.floats.len > 0:
        return some(f.get.floats[0])
    of vkString:
      discard

func firstInt(r: Record, name: string): Option[int64] =
  let f = r.field(name)
  if f.isSome and f.get.kind == vkInt and f.get.ints.len > 0:
    return some(f.get.ints[0])

func nameOf(p: Profile, r: Record, field: string): string =
  ## The profile name of an enumerated field ("" if the record lacks it).
  let f = r.field(field)
  if f.isSome:
    valueName(p, f.get)
  else:
    ""

func sessionOf(
    p: Profile, r: Record, index: int
): ActivityData {.raises: [ImportError].} =
  ## The summary part of an activity from a session record.
  result = ActivityData(session: index)
  let start = r.firstInt("start_time")
  if start.isNone or not isFitTime(FitTime(start.get)) or
      FitTime(start.get) < minCalendarFit:
    raiseImport(ifBadTime, fmt"session {index} has no valid start time")
  let startFit = FitTime(start.get)
  result.startT = fitToUnix(startFit)
  let finish = if r.timestamp.isSome: r.timestamp.get else: startFit
  result.endT = fitToUnix(max(finish, startFit))
  result.sport = nameOf(p, r, "sport")
  result.subSport = nameOf(p, r, "sub_sport")
  result.elapsedS = r.firstNum("total_elapsed_time")
  result.timerS = r.firstNum("total_timer_time")
  result.distanceM = r.firstNum("total_distance")
  let cal = r.firstNum("total_calories")
  if cal.isSome:
    result.calories = some(int(cal.get))

func coordOf(r: Record, t: UnixTime, index, offset: int): Option[RawCoord] =
  ## The coordinate of a record, if it has a position.
  let lat = r.firstInt("position_lat")
  let lon = r.firstInt("position_long")
  if lat.isNone or lon.isNone:
    return
  var alt = r.firstNum("enhanced_altitude")
  if alt.isNone:
    alt = r.firstNum("altitude")
  var speed = r.firstNum("enhanced_speed")
  if speed.isNone:
    speed = r.firstNum("speed")
  some(
    RawCoord(
      c: Coord(
        t: t,
        lon: float(lon.get) * semicircleDegrees,
        lat: float(lat.get) * semicircleDegrees,
        alt: alt,
        speed: speed,
      ),
      index: index,
      offset: offset,
    )
  )

func merged(segs: seq[Segment]): seq[Segment] =
  ## Segments in time order; those that touch or overlap become one.
  for g in segs:
    if result.len > 0 and g.startT <= result[^1].endT:
      if g.endT > result[^1].endT:
        result[^1].endT = g.endT
        result[^1].endedBy = g.endedBy
    else:
      result.add g

func triggerOf(name: string): Trigger =
  ## The `timer_trigger` of a timer event, by its name ("" if the event has none).
  case name
  of "auto": trAuto
  of "manual": trManual
  else: trOther

func segmentsOf*(startT, endT: UnixTime, events: seq[TimerEvent]): seq[Segment] =
  ## The segments of a session lasting from `startT` to `endT`, given its timer
  ## events in time order.  A start while running and a stop while stopped
  ## change nothing; a first event that is a stop means the timer was running
  ## from the start of the session; a timer still running at the end stops
  ## there; no events at all is one segment.
  var running = events.len == 0 or not events[0].running
  var since = startT
  var sinceBy: Trigger
  var found: seq[Segment]
  for e in events:
    if e.running and not running:
      running = true
      since = e.t
      sinceBy = e.trigger
    elif not e.running and running:
      running = false
      found.add Segment(
        startT: since, endT: e.t, startedBy: sinceBy, endedBy: e.trigger
      )
  if running:
    found.add Segment(startT: since, endT: endT, startedBy: sinceBy)
  for g in found.mitems:
    g.startT = max(g.startT, startT)
    g.endT = min(g.endT, endT)
  merged(found.filterIt(it.endT >= it.startT))

proc cover(segs: var seq[Segment], coords: seq[Coord], ws: var seq[Warning]) =
  ## Make every coordinate (in time order) lie in a segment: one outside all of
  ## them extends the nearest, with a warning.
  if segs.len == 0:
    return
  var j = 0
  for c in coords:
    while j < segs.high and c.t > segs[j].endT:
      inc j
    if c.t >= segs[j].startT and c.t <= segs[j].endT:
      continue
    # c is before segs[j] (in a gap or before the first) or after the last
    let toPrevious =
      if j > 0:
        c.t - segs[j - 1].endT
      else:
        high(int64)
    let toThis =
      if c.t < segs[j].startT:
        segs[j].startT - c.t
      else:
        c.t - segs[j].endT
    if j > 0 and toPrevious <= toThis:
      segs[j - 1].endT = c.t
    elif c.t < segs[j].startT:
      segs[j].startT = c.t
    else:
      segs[j].endT = c.t
    ws.add wkOutsideSegment,
      0,
      fmt"a coordinate at {c.t} is outside the timer segments; the nearest segment is extended"
  segs = merged(segs)

func joinStretches*(segs: seq[Segment], coords: seq[Coord]): seq[Segment] =
  ## Join the segments that `joinable` says are one stretch of riding.  `segs` are in time order and
  ## disjoint and `coords` in time order (each in a segment, as `cover` leaves them).  How far the
  ## rider moved over a gap is from the last position before it to the first after it; with no
  ## position on one side there is nothing to measure, and the segments stay apart.
  var p = 0 # the first coordinate after the end of the segment before the gap
  for i, g in segs:
    if i == 0:
      result.add g
      continue
    let before = segs[i - 1]
    while p < coords.len and coords[p].t <= before.endT:
      inc p
    if p > 0 and p < coords.len and
        joinable(
          Gap(
            seconds: g.startT - before.endT,
            metres: haversine(
              coords[p - 1].lon, coords[p - 1].lat, coords[p].lon, coords[p].lat
            ),
            stoppedBy: before.endedBy,
            restartedBy: g.startedBy,
          )
        ):
      result[^1].endT = g.endT
      result[^1].endedBy = g.endedBy
    else:
      result.add g

proc sortedUnique(raw: var seq[RawCoord], ws: var seq[Warning]): seq[Coord] =
  ## Time order; of several in one second the last (by appearance) is kept.
  raw.sort do(a, b: RawCoord) -> int:
    result = cmp(a.c.t, b.c.t)
    if result == 0:
      result = cmp(a.index, b.index)
  for i, rc in raw:
    if result.len > 0 and result[^1].t == rc.c.t:
      ws.add wkDuplicateTime,
        rc.offset, fmt"several records at second {rc.c.t}; the last is kept"
      result[^1] = rc.c
    else:
      result.add rc.c

func cleaningWarnings*(c: Cleaned, ws: var seq[Warning]) =
  ## One warning of each kind for what the cleaning did to an activity: how many, and the first second.
  var count: array[Fault, int]
  var first: array[Fault, int64]
  for d in c.dropped:
    if count[d.fault] == 0 or int64(d.t) < first[d.fault]:
      first[d.fault] = int64(d.t)
    inc count[d.fault]
  for f in Fault:
    if count[f] > 0:
      let kind =
        case f
        of fStale: wkStalePosition
        of fSpike: wkBadPosition
        of fFirstFix: wkPoorFirstFix
      ws.add kind, 0, fmt"{count[f]} dropped ({$f}); the first at second {first[f]}"
  if c.splits.len > 0:
    ws.add wkPositionJump,
      0,
      fmt"{c.splits.len} jumps that did not return: split at second {int64(c.splits[0])} (and later)"

func splitAt*(segs: seq[Segment], times: seq[UnixTime]): seq[Segment] =
  ## The stretches cut where a jump did not return: a coordinate at `t` is the first of the new stretch.
  result = segs
  for t in times:
    for i in 0 ..< result.len:
      if result[i].startT < t and t <= result[i].endT:
        let tail = Segment(startT: t, endT: result[i].endT, endedBy: result[i].endedBy)
        result[i].endT = UnixTime(int64(t) - 1)
        result.insert(tail, i + 1)
        break

proc uniqueSamples(raw: var seq[RawSample]): Table[string, seq[Sample]] =
  ## By channel, in time order; of several in one second the last (by appearance) is kept.
  ## (The duplicate seconds are already warned about for the coordinates.)
  raw.sort do(a, b: RawSample) -> int:
    result = cmp(a.s.t, b.s.t)
    if result == 0:
      result = cmp(a.index, b.index)
  for x in raw:
    let list = addr result.mgetOrPut(x.channel, @[])
    if list[].len > 0 and list[][^1].t == x.s.t:
      list[][^1] = x.s
    else:
      list[].add x.s

proc readActivities*(
    p: Profile, data: sink seq[byte], ws: var seq[Warning], channels: seq[string] = @[]
): seq[ActivityData] {.raises: [FitError, ImportError].} =
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
    notActivity = false ## the file says it is not an activity (its `file_id` type)
  try:
    timed "decode: file":
      for ev in r.events(p):
        if ev.kind != evRecord:
          continue
        template rec(): untyped =
          ev.record # (not `let`: that would copy the whole record)

        case rec.name
        of "record":
          if rec.timestamp.isNone or rec.timestamp.get < minCalendarFit:
            ws.add wkInvalidTime, ev.offset, "record without a calendar time"
            continue
          let rc = coordOf(rec, fitToUnix(rec.timestamp.get), count, ev.offset)
          if rc.isSome:
            raw.add rc.get
          for name in channels:
            let v = rec.firstNum(name)
            if v.isSome:
              rawSamples.add RawSample(
                channel: name,
                s: Sample(t: fitToUnix(rec.timestamp.get), v: v.get),
                index: count,
              )
          inc count
        of "event":
          if nameOf(p, rec, "event") == "timer" and rec.timestamp.isSome and
              rec.timestamp.get >= minCalendarFit:
            let kind = nameOf(p, rec, "event_type")
            if kind == "start" or kind.startsWith("stop"):
              timer.add TimerEvent(
                t: fitToUnix(rec.timestamp.get),
                running: kind == "start",
                trigger: triggerOf(nameOf(p, rec, "timer_trigger")),
              )
        of "file_id":
          let kind = nameOf(p, rec, "type") # (a type the profile lacks is its number)
          if kind.len > 0 and kind != "activity":
            notActivity = true
        of "session":
          sessions.add sessionOf(p, rec, sessions.len)
        of "activity":
          let local = rec.firstInt("local_timestamp")
          if offsetS.isNone and local.isSome and rec.timestamp.isSome:
            # (the field may be declared wider than 32 bits and hold anything: subtract only two real times)
            if not isFitTime(FitTime(local.get)):
              ws.add wkInvalidTime,
                ev.offset,
                fmt"activity: local_timestamp {local.get} is not a time (ignored)"
            else:
              let diff = int(local.get - int64(rec.timestamp.get))
              if abs(diff) <= maxUtcOffsetS:
                offsetS = some(diff)
              else:
                ws.add wkInvalidTime,
                  ev.offset,
                  fmt"activity: local time {diff} s from UTC is not a time zone (ignored)"
        else:
          discard
  finally:
    ws.add r.warnings
  if sessions.len == 0:
    if notActivity:
      raiseImport(
        ifMonitor,
        "a monitor file (all-day wear data or the like): no activity is expected",
      )
    raiseImport(ifNoActivity, "no activity in this file (it has no session message)")
  sessions.sort do(a, b: ActivityData) -> int:
    result = cmp(a.startT, b.startT)
    if result == 0:
      result = cmp(a.session, b.session)
  let coords = sortedUnique(raw, ws)
  var k = 0 # the session the coordinates are being given to
  for c in coords:
    while k + 1 < sessions.len and sessions[k + 1].startT <= c.t:
      inc k
    sessions[k].coords.add c
  # clean the positions of each session (before the stretches are worked out from them)
  var splits = newSeq[seq[UnixTime]](sessions.len)
  for i, s in sessions.mpairs:
    var cleaned: Cleaned
    timed "import: clean positions":
      cleaned = cleanCoords(s.coords)
    s.coords = cleaned.kept
    splits[i] = cleaned.splits
    cleaningWarnings(cleaned, ws)
  # the other fields go to sessions the same way
  for name, list in uniqueSamples(rawSamples):
    var first = 0 # the samples of a session are those before the next one starts
    for k in 0 ..< sessions.len:
      let limit =
        if k + 1 < sessions.len:
          sessions[k + 1].startT
        else:
          UnixTime(high(int64))
      var after = first
      while after < list.len and list[after].t < limit:
        inc after
      if after > first:
        sessions[k].samples[name] = list[first ..< after]
      first = after
  # timer events go to sessions the way coordinates do; then the segments
  timer.sort do(a, b: TimerEvent) -> int:
    cmp(a.t, b.t)
  var perSession = newSeq[seq[TimerEvent]](sessions.len)
  k = 0
  for e in timer:
    while k + 1 < sessions.len and sessions[k + 1].startT <= e.t:
      inc k
    perSession[k].add e
  for i, s in sessions.mpairs:
    s.utcOffsetS = offsetS
    s.segments = segmentsOf(s.startT, s.endT, perSession[i])
    cover(s.segments, s.coords, ws)
    s.segments = splitAt(joinStretches(s.segments, s.coords), splits[i])
  sessions
