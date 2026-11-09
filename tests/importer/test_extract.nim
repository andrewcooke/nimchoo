import std/[options, os, sequtils, strutils, unittest]
import nimchoo/core/errors
import nimchoo/packages/importer/extract
import nimchoo/packages/importer/stretch
import nimchoo/packages/fit/reader
import nimchoo/packages/fit/records
import nimchoo/packages/fit/time
import nimchoo/packages/util/bytes/bytes
import nimchoo/packages/fit/load
import nimchoo/packages/util/warnings/warnings
import ../support/fitbuilder

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"
  multisport =
    "../choochoo/data/test/source/python-fitparse/" &
    "activity-large-fenxi2-multisport.fit"
  base = 900_000_000 ## a FIT time (2018)
  unixBase = UnixTime(int64(base) + 631_065_600'i64)
  north45 = 536_870_912 ## 45 degrees in semicircles (2^29)
  west90 = -1_073_741_824 ## -90 degrees (-2^30)

let p = loadProfile(profilePath)

# --- messages for hand-built files

let recordDefn =
  defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T), (78, 4, uint32T)])
let bareDefn = defn(3, 20, @[(253, 4, uint32T)]) # a record with no position
let sessionDefn = defn(
  1,
  18,
  @[
    (253, 4, uint32T),
    (2, 4, uint32T),
    (5, 1, enumT),
    (6, 1, enumT),
    (7, 4, uint32T),
    (8, 4, uint32T),
    (9, 4, uint32T),
    (11, 2, uint16T),
  ],
)
let activityDefn = defn(2, 34, @[(253, 4, uint32T), (5, 4, uint32T)])

func at(t: int, lat = north45, lon = west90, alt = 3500): seq[byte] =
  ## A record at FIT time `t` (altitude 3500 is 200 m).
  b(0) & le32(t) & le32(lat) & le32(lon) & le32(alt)

func bare(t: int): seq[byte] =
  b(3) & le32(t)

func session(start, finish: int, sport = 2, sub = 0): seq[byte] =
  ## A session: cycling, generic by default; 2 s elapsed and timer, 10 m, 5 kcal.
  b(1) & le32(finish) & le32(start) & b(sport, sub) & le32(2000) & le32(2000) &
    le32(1000) & le16(5)

func activityMsg(t, local: int): seq[byte] =
  b(2) & le32(t) & le32(local)

proc activities(body: seq[byte]): (seq[ActivityData], seq[Warning]) =
  var ws: seq[Warning]
  let a = readActivities(p, fitFile(body), ws)
  (a, ws)

func kinds(ws: seq[Warning]): seq[WarningKind] =
  ws.mapIt(it.kind)

suite "activities: a session and its coordinates":
  test "summary and coordinates":
    let body =
      recordDefn & at(base) & at(base + 1) & at(base + 2) & sessionDefn &
      session(base, base + 2)
    let (a, ws) = activities(body)
    check ws.len == 0
    check a.len == 1
    check a[0].session == 0
    check a[0].startT == unixBase
    check a[0].endT == unixBase + 2
    check a[0].sport == "cycling"
    check a[0].subSport == "generic"
    check a[0].elapsedS == some(2.0)
    check a[0].timerS == some(2.0)
    check a[0].distanceM == some(10.0)
    check a[0].calories == some(5)
    check a[0].utcOffsetS.isNone
    check a[0].coords.mapIt(it.t) == @[unixBase, unixBase + 1, unixBase + 2]
    check a[0].coords[0].lat == 45.0
    check a[0].coords[0].lon == -90.0
    check a[0].coords[0].alt == some(200.0)

  test "a record without a position makes no coordinate":
    let body =
      bareDefn & bare(base) & bare(base + 1) & recordDefn & at(base + 2) & sessionDefn &
      session(base, base + 2)
    let (a, _) = activities(body)
    check a[0].coords.mapIt(it.t) == @[unixBase + 2]

  test "an activity with no positions at all":
    let (a, ws) = activities(
      bareDefn & bare(base) & bare(base + 1) & sessionDefn & session(base, base + 1)
    )
    check a.len == 1
    check a[0].coords.len == 0
    check ws.len == 0

  test "the local time offset comes from the activity message":
    let body =
      recordDefn & at(base) & sessionDefn & session(base, base) & activityDefn &
      activityMsg(base, base - 10_800)
    check activities(body)[0][0].utcOffsetS == some(-10_800)

suite "activities: times":
  test "records in the same second keep the last, with a warning":
    let body =
      recordDefn & at(base, lat = north45) & at(base, lat = north45 div 2) & at(
        base + 1
      ) & sessionDefn & session(base, base + 1)
    let (a, ws) = activities(body)
    check a[0].coords.len == 2
    check a[0].coords[0].lat == 22.5
    check ws.kinds == @[wkDuplicateTime]

  test "records out of order are put in order":
    let body =
      recordDefn & at(base + 2) & at(base) & at(base + 1) & sessionDefn &
      session(base, base + 2)
    check activities(body)[0][0].coords.mapIt(it.t) ==
      @[unixBase, unixBase + 1, unixBase + 2]

  test "times that are not calendar times are dropped, with a warning":
    let body =
      recordDefn & at(5) & at(base) & at(0x0fffffff) & sessionDefn & session(base, base)
    let (a, ws) = activities(body)
    check a[0].coords.mapIt(it.t) == @[unixBase]
    check ws.kinds == @[wkInvalidTime, wkInvalidTime]

  test "the first calendar time is accepted":
    let (a, _) = activities(
      recordDefn & at(0x10000000) & sessionDefn & session(0x10000000, 0x10000000)
    )
    check a[0].coords.len == 1

suite "activities: refusing files":
  test "no session":
    try:
      discard activities(recordDefn & at(base))
      check false
    except ImportError as e:
      check e.kind == ifNoActivity

  test "no session in a file that says it is not an activity: a monitor file":
    let fileIdDefn = defn(4, 0, @[(0, 1, enumT)])
    func fileId(kind: int): seq[byte] =
      b(4, kind)
    for kind in [32, 15, 44]:
      # monitoring_b, monitoring_a, a type the profile does not have
      try:
        discard activities(fileIdDefn & fileId(kind) & recordDefn & at(base))
        check false
      except ImportError as e:
        check e.kind == ifMonitor
    try: # an activity file with no session is still a failure
      discard activities(fileIdDefn & fileId(4) & recordDefn & at(base))
      check false
    except ImportError as e:
      check e.kind == ifNoActivity
    # a session wins: a file with a session is read whatever it says it is
    check activities(
      fileIdDefn & fileId(32) & recordDefn & at(base) & at(base + 1) & sessionDefn &
        session(base, base + 1)
    )[0].len == 1

  test "a session that starts at no calendar time":
    try:
      discard activities(recordDefn & at(base) & sessionDefn & session(100, base))
      check false
    except ImportError as e:
      check e.kind == ifBadTime

  test "a session start declared wider than 32 bits and out of range is a bad time, not an overflow":
    let wide =
      defn(1, 18, @[(253, 4, uint32T), (2, 8, sint64T), (5, 1, enumT), (6, 1, enumT)])
    for hi in [0x7FFFFFFF'i64, 0x80000000'i64]:
      try:
        discard activities(
          recordDefn & at(base) & wide & b(1) & le32(base) & le32(0xFFFFFFFF'i64) &
            le32(hi) & b(2, 0)
        )
        check false
      except ImportError as e:
        check e.kind == ifBadTime

  test "a file that cannot be read":
    expect FitError:
      discard activities(b(0x03, 1))

suite "activities: several sessions":
  test "records go to the last session that started at or before them":
    # the session messages are in the file in reverse order of start time
    let body =
      recordDefn & at(base - 5) & at(base + 10) & at(base + 99) & at(base + 100) &
      at(base + 150) & sessionDefn & session(base + 100, base + 150, sport = 1) &
      session(base, base + 99, sport = 2)
    let (a, _) = activities(body)
    check a.len == 2
    check a[0].startT == unixBase
    check a[0].session == 1 # its position in the file
    check a[0].sport == "cycling"
    check a[0].coords.mapIt(it.t - unixBase) == @[-5'i64, 10, 99]
    check a[1].startT == unixBase + 100
    check a[1].session == 0
    check a[1].sport == "running"
    check a[1].coords.mapIt(it.t - unixBase) == @[100'i64, 150]

suite "activities: real files":
  test "a ride":
    var ws: seq[Warning]
    let a = readActivities(p, readBytes(ride), ws)
    check a.len == 1
    check ws.len == 0
    check a[0].sport == "cycling"
    check a[0].startT == UnixTime(1535373814) # 2018-08-27T12:43:34Z
    check a[0].utcOffsetS == some(-10_800)
    check a[0].coords.len == 2099
    check abs(a[0].coords[0].lat - (-398821890.0 * 180.0 / 2147483648.0)) < 1e-9
    check a[0].coords[0].t == a[0].startT
    check abs(a[0].distanceM.get - 11978.11) < 1e-6
    check a[0].coords[0].alt.isNone # this device recorded no altitude

  test "a multisport file: every position goes to exactly one session":
    var ws: seq[Warning]
    let a = readActivities(p, readBytes(multisport), ws)
    check a.len == 7
    var n = 0 # records with a position, counted again
    var r = initReader(p, readBytes(multisport))
    for rec in r.records(p):
      if rec.name == "record" and rec.timestamp.isSome and
          rec.timestamp.get >= minCalendarFit and rec.field("position_lat").isSome and
          rec.field("position_long").isSome:
        inc n
    var total = 0
    for k, s in a:
      total += s.coords.len
      if s.coords.len > 0:
        check s.coords[0].t >= s.startT or k == 0
        if k + 1 < a.len:
          check s.coords[^1].t < a[k + 1].startT
    check total + ws.filterIt(it.kind == wkDuplicateTime).len == n

# --- segments

func ev(t: int64, running: bool): TimerEvent =
  TimerEvent(t: UnixTime(t), running: running)
func seg(a, b: int64): Segment =
  Segment(startT: UnixTime(a), endT: UnixTime(b))
func seg(a, b: UnixTime): Segment =
  Segment(startT: a, endT: b)
func spans(gs: seq[Segment]): seq[Segment] =
  ## Only the times (the triggers a file's events give are not the point of most tests).
  gs.mapIt(seg(it.startT, it.endT))

suite "segments: from timer events":
  const (s0, s1) = (UnixTime(100), UnixTime(200)) # the session

  test "no timer events: the whole session":
    check segmentsOf(s0, s1, @[]) == @[seg(100, 200)]

  test "pairs of start and stop":
    check segmentsOf(
      s0, s1, @[ev(100, true), ev(120, false), ev(150, true), ev(200, false)]
    ) == @[seg(100, 120), seg(150, 200)]

  test "a start while running is ignored":
    check segmentsOf(s0, s1, @[ev(100, true), ev(110, true), ev(120, false)]) ==
      @[seg(100, 120)]

  test "a stop while stopped is ignored":
    check segmentsOf(
      s0,
      s1,
      @[ev(100, true), ev(120, false), ev(130, false), ev(150, true), ev(200, false)],
    ) == @[seg(100, 120), seg(150, 200)]

  test "a first event that is a stop: running since the session began":
    check segmentsOf(s0, s1, @[ev(120, false), ev(150, true)]) ==
      @[seg(100, 120), seg(150, 200)]

  test "still running at the end: it stops with the session":
    check segmentsOf(s0, s1, @[ev(100, true), ev(120, false), ev(150, true)]) ==
      @[seg(100, 120), seg(150, 200)]

  test "a stop and a start in the same second are no pause":
    check segmentsOf(
      s0, s1, @[ev(100, true), ev(120, false), ev(120, true), ev(140, false)]
    ) == @[seg(100, 140)]

  test "a pause of one second is a pause":
    check segmentsOf(
      s0, s1, @[ev(100, true), ev(120, false), ev(121, true), ev(140, false)]
    ) == @[seg(100, 120), seg(121, 140)]

  test "events outside the session are clipped":
    check segmentsOf(
      s0, s1, @[ev(50, true), ev(150, false), ev(160, true), ev(300, false)]
    ) == @[seg(100, 150), seg(160, 200)]
    check segmentsOf(s0, s1, @[ev(250, true), ev(260, false)]).len == 0 # after it

let timerDefn = defn(4, 21, @[(253, 4, uint32T), (0, 1, enumT), (1, 1, enumT)])

func timer(t: int, kind: int): seq[byte] =
  ## A timer event at FIT time `t`; kind 0 is a start, 1 a stop, 4 a stop_all.
  b(4) & le32(t) & b(0, kind)

func ev(t: int64, running: bool, trigger: Trigger): TimerEvent =
  TimerEvent(t: UnixTime(t), running: running, trigger: trigger)

suite "segments: who started and stopped the timer":
  const (s0, s1) = (UnixTime(100), UnixTime(200))

  test "each segment says who started and stopped it":
    let segs = segmentsOf(
      s0,
      s1,
      @[
        ev(100, true, trManual),
        ev(120, false, trAuto),
        ev(150, true, trOther),
        ev(180, false, trManual),
      ],
    )
    check segs.mapIt((it.startedBy, it.endedBy)) ==
      @[(trManual, trAuto), (trOther, trManual)]

  test "the trigger of the event that counts is the one kept":
    # the second start is ignored (already running), the second stop too
    let segs = segmentsOf(
      s0,
      s1,
      @[
        ev(100, true, trAuto),
        ev(110, true, trManual),
        ev(120, false, trManual),
        ev(125, false, trAuto),
      ],
    )
    check segs.mapIt((it.startedBy, it.endedBy)) == @[(trAuto, trManual)]

func auto(a, b: int64): Segment =
  Segment(startT: UnixTime(a), endT: UnixTime(b), startedBy: trAuto, endedBy: trAuto)

const metre = 107 ## semicircles in a metre of latitude (2^31 / 180 degrees / 111 km)

func coord(t: int64, metres: float): Coord =
  ## A position `metres` north of 45 degrees south.
  Coord(t: UnixTime(t), lon: -90.0, lat: -45.0 + metres / 111_195.0)

suite "segments: joining stretches":
  test "an auto-pause where the rider stayed is joined, a chain of them too":
    let segs = @[auto(0, 10), auto(40, 50), auto(90, 100)]
    let coords = @[
      coord(0, 0),
      coord(10, 10),
      coord(40, 12),
      coord(50, 20),
      coord(90, 21),
      coord(100, 30),
    ]
    check joinStretches(segs, coords).spans == @[seg(0, 100)]

  test "a gap that moved is kept, and the ones either side are judged on their own":
    let segs = @[auto(0, 10), auto(40, 50), auto(90, 100)]
    let coords = @[
      coord(0, 0),
      coord(10, 10),
      coord(40, 12),
      coord(50, 20),
      coord(90, 5000),
      coord(100, 5010),
    ]
    check joinStretches(segs, coords).spans == @[seg(0, 50), seg(90, 100)]

  test "a manual stop is kept apart however close":
    var segs = @[auto(0, 10), auto(40, 50)]
    segs[0].endedBy = trManual
    let coords = @[coord(0, 0), coord(10, 0), coord(40, 0), coord(50, 0)]
    check joinStretches(segs, coords).len == 2

  test "no position on one side: nothing to measure, the segments stay apart":
    let segs = @[auto(0, 10), auto(40, 50)]
    check joinStretches(segs, @[coord(0, 0), coord(10, 0)]).len == 2 # none after
    check joinStretches(segs, @[coord(40, 0), coord(50, 0)]).len == 2 # none before
    check joinStretches(segs, @[]).len == 2

  test "a segment without positions is looked through":
    # a short segment with no fix: the positions either side are what show where the rider was
    let segs = @[auto(0, 10), auto(20, 30), auto(40, 50)]
    let coords = @[coord(0, 0), coord(10, 1), coord(40, 2), coord(50, 3)]
    check joinStretches(segs, coords).spans == @[seg(0, 50)]

  test "the stretch ends the way its last segment ended":
    var segs = @[auto(0, 10), auto(40, 50)]
    segs[1].endedBy = trManual
    let joined =
      joinStretches(segs, @[coord(0, 0), coord(10, 0), coord(40, 0), coord(50, 0)])
    check joined.len == 1
    check joined[0].endedBy == trManual

  test "nothing to join, or one segment":
    check joinStretches(@[], @[]).len == 0
    check joinStretches(@[auto(0, 10)], @[coord(0, 0)]) == @[auto(0, 10)]

let timerTDefn =
  defn(5, 21, @[(253, 4, uint32T), (0, 1, enumT), (1, 1, enumT), (3, 1, enumT)])

func timerT(t: int, kind: int, trigger: int): seq[byte] =
  ## A timer event with its trigger; kind 0 is a start, 4 a stop_all; trigger 0 is
  ## manual, 1 auto.
  b(5) & le32(t) & b(0, kind, trigger)

func pos(t, metres: int): seq[byte] =
  at(t, lat = north45 + metres * metre)

proc stretchesOf(body: seq[byte]): seq[Segment] =
  let (a, _) = activities(body)
  a[0].segments

suite "segments: stretches in files":
  # two timer segments, [base, base+10] and [base+50, base+70], with a gap of 40 s
  proc twoSegments(
      restartTrigger, metresMoved: int, gap = 40, stopTrigger = 1
  ): seq[byte] =
    let t2 = base + 10 + gap
    recordDefn & pos(base, 0) & pos(base + 10, 10) & pos(t2 + 10, 10 + metresMoved) &
      pos(t2 + 20, 20 + metresMoved) & timerTDefn & timerT(base, 0, 1) &
      timerT(base + 10, 4, stopTrigger) & timerT(t2, 0, restartTrigger) &
      timerT(t2 + 20, 4, 1) & sessionDefn & session(base, t2 + 20)

  test "an auto-pause where the rider stayed is one stretch":
    check stretchesOf(twoSegments(1, 5)).spans == @[seg(unixBase, unixBase + 70)]

  test "stopped by the device and restarted by hand: one stretch":
    check stretchesOf(twoSegments(0, 5)).len == 1

  test "stopped by hand: two stretches, even if the rider did not move":
    check stretchesOf(twoSegments(0, 0, stopTrigger = 0)).len == 2
    check stretchesOf(twoSegments(1, 0, stopTrigger = 0)).len == 2

  test "an auto-pause in which the rider moved 500 m: two stretches":
    check stretchesOf(twoSegments(1, 500)).len == 2

  test "a short pause at riding speed (200 m in 20 s) is one stretch":
    check stretchesOf(twoSegments(1, 200, gap = 20)).len == 1

  test "a short pause at the speed of a car (600 m in 20 s) is two":
    check stretchesOf(twoSegments(1, 600, gap = 20)).len == 2

  test "a trigger the file does not give: two stretches, as before":
    let body =
      recordDefn & pos(base, 0) & pos(base + 10, 0) & pos(base + 60, 0) &
      pos(base + 70, 0) & timerDefn & timer(base, 0) & timer(base + 10, 4) &
      timer(base + 50, 0) & timer(base + 70, 4) & sessionDefn & session(base, base + 70)
    check stretchesOf(body).len == 2

suite "segments: in files":
  test "segments from the events of a file":
    let body =
      recordDefn & at(base) & at(base + 1) & at(base + 5) & at(base + 6) & timerDefn &
      timer(base, 0) & timer(base + 1, 4) & timer(base + 5, 0) & timer(base + 6, 4) &
      sessionDefn & session(base, base + 6)
    let (a, ws) = activities(body)
    check a[0].segments.spans ==
      @[seg(unixBase, unixBase + 1), seg(unixBase + 5, unixBase + 6)]
    check ws.len == 0

  test "no timer events: one segment for the session":
    let (a, _) = activities(
      recordDefn & at(base) & at(base + 2) & sessionDefn & session(base, base + 2)
    )
    check a[0].segments.spans == @[seg(unixBase, unixBase + 2)]

  test "a coordinate outside every segment extends the nearest, with a warning":
    # a record one second after the last stop and one in the middle of a pause
    let body =
      recordDefn & at(base) & at(base + 3) & at(base + 9) & timerDefn & timer(base, 0) &
      timer(base + 2, 4) & timer(base + 8, 0) & timer(base + 8, 4) & sessionDefn &
      session(base, base + 10)
    let (a, ws) = activities(body)
    check ws.kinds.count(wkOutsideSegment) == 2
    for c in a[0].coords:
      check a[0].segments.countIt(c.t >= it.startT and c.t <= it.endT) == 1

  test "each session has the segments of its own events":
    let body =
      recordDefn & at(base + 1) & at(base + 101) & timerDefn & timer(base, 0) &
      timer(base + 50, 4) & timer(base + 100, 0) & timer(base + 150, 4) & sessionDefn &
      session(base, base + 50) & session(base + 100, base + 150)
    let (a, _) = activities(body)
    check a.len == 2
    check a[0].segments.spans == @[seg(unixBase, unixBase + 50)]
    check a[1].segments.spans == @[seg(unixBase + 100, unixBase + 150)]

suite "segments: real files":
  test "the ride: its 20 timer segments are one stretch (auto-pauses the rider did not leave)":
    var ws: seq[Warning]
    let a = readActivities(p, readBytes(ride), ws)
    check a[0].segments.len == 1
    # the stretch covers the ride from the first start to the last stop: elapsed time, pauses included
    let span = a[0].segments[0].endT - a[0].segments[0].startT
    check abs(float(span) - a[0].elapsedS.get) <= 20.0
    check ws.kinds.count(wkOutsideSegment) == 0

  test "every coordinate of every importable test file is in exactly one segment":
    var files = 0
    for dir in ["sdk", "personal", "other", "python-fitparse"]:
      for path in walkFiles("../choochoo/data/test/source" / dir / "*"):
        if path.splitFile.ext.toLowerAscii != ".fit":
          continue
        var ws: seq[Warning]
        let a =
          try:
            readActivities(p, readBytes(path), ws)
          except NchError:
            continue
        inc files
        for act in a:
          for k, g in act.segments:
            check g.startT <= g.endT
            if k > 0:
              check g.startT > act.segments[k - 1].endT
          for c in act.coords:
            if act.segments.countIt(c.t >= it.startT and c.t <= it.endT) != 1:
              checkpoint path & ": coordinate at " & $c.t
              fail()
    check files > 30
