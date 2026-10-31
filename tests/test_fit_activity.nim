import std/[options, sequtils, unittest]
import nimchoo/errors
import nimchoo/fit/[activity, bytes, reader, records]
import nimchoo/profile/load
import nimchoo/warnings
import ./fitbuilder

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"
  multisport = "../choochoo/data/test/source/python-fitparse/" &
    "activity-large-fenxi2-multisport.fit"
  base = 900_000_000    ## a FIT time (2018)
  unixBase = int64(base) + 631_065_600'i64
  north45 = 536_870_912       ## 45 degrees in semicircles (2^29)
  west90 = -1_073_741_824     ## -90 degrees (-2^30)

let p = loadProfile(profilePath)

# --- messages for hand-built files

let recordDefn = defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T),
                               (1, 4, sint32T), (78, 4, uint32T)])
let bareDefn = defn(3, 20, @[(253, 4, uint32T)])      # a record with no position
let sessionDefn = defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T),
                                (5, 1, enumT), (6, 1, enumT), (7, 4, uint32T),
                                (8, 4, uint32T), (9, 4, uint32T), (11, 2, uint16T)])
let activityDefn = defn(2, 34, @[(253, 4, uint32T), (5, 4, uint32T)])

func at(t: int, lat = north45, lon = west90, alt = 3500): seq[byte] =
  ## A record at FIT time `t` (altitude 3500 is 200 m).
  b(0) & le32(t) & le32(lat) & le32(lon) & le32(alt)

func bare(t: int): seq[byte] = b(3) & le32(t)

func session(start, finish: int, sport = 2, sub = 0): seq[byte] =
  ## A session: cycling, generic by default; 2 s elapsed and timer, 10 m, 5 kcal.
  b(1) & le32(finish) & le32(start) & b(sport, sub) & le32(2000) & le32(2000) &
    le32(1000) & le16(5)

func activityMsg(t, local: int): seq[byte] = b(2) & le32(t) & le32(local)

proc activities(body: seq[byte]): (seq[ActivityData], seq[Warning]) =
  var ws: seq[Warning]
  let a = readActivities(p, fitFile(body), ws)
  (a, ws)

func kinds(ws: seq[Warning]): seq[WarningKind] = ws.mapIt(it.kind)

suite "activities: a session and its coordinates":
  test "summary and coordinates":
    let body = recordDefn & at(base) & at(base + 1) & at(base + 2) &
      sessionDefn & session(base, base + 2)
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
    let body = bareDefn & bare(base) & bare(base + 1) &
      recordDefn & at(base + 2) &
      sessionDefn & session(base, base + 2)
    let (a, _) = activities(body)
    check a[0].coords.mapIt(it.t) == @[unixBase + 2]

  test "an activity with no positions at all":
    let (a, ws) = activities(bareDefn & bare(base) & bare(base + 1) &
                             sessionDefn & session(base, base + 1))
    check a.len == 1
    check a[0].coords.len == 0
    check ws.len == 0

  test "the local time offset comes from the activity message":
    let body = recordDefn & at(base) & sessionDefn & session(base, base) &
      activityDefn & activityMsg(base, base - 10_800)
    check activities(body)[0][0].utcOffsetS == some(-10_800)

suite "activities: times":
  test "records in the same second keep the last, with a warning":
    let body = recordDefn & at(base, lat = north45) &
      at(base, lat = north45 div 2) & at(base + 1) &
      sessionDefn & session(base, base + 1)
    let (a, ws) = activities(body)
    check a[0].coords.len == 2
    check a[0].coords[0].lat == 22.5
    check ws.kinds == @[wkDuplicateTime]

  test "records out of order are put in order":
    let body = recordDefn & at(base + 2) & at(base) & at(base + 1) &
      sessionDefn & session(base, base + 2)
    check activities(body)[0][0].coords.mapIt(it.t) ==
      @[unixBase, unixBase + 1, unixBase + 2]

  test "times that are not calendar times are dropped, with a warning":
    let body = recordDefn & at(5) & at(base) & at(0x0fffffff) &
      sessionDefn & session(base, base)
    let (a, ws) = activities(body)
    check a[0].coords.mapIt(it.t) == @[unixBase]
    check ws.kinds == @[wkInvalidTime, wkInvalidTime]

  test "the first calendar time is accepted":
    let (a, _) = activities(recordDefn & at(0x10000000) &
                            sessionDefn & session(0x10000000, 0x10000000))
    check a[0].coords.len == 1

suite "activities: refusing files":
  test "no session":
    expect ImportError:
      discard activities(recordDefn & at(base))

  test "a session that starts at no calendar time":
    expect ImportError:
      discard activities(recordDefn & at(base) & sessionDefn & session(100, base))

  test "a file that cannot be read":
    expect FitError:
      discard activities(b(0x03, 1))

suite "activities: several sessions":
  test "records go to the last session that started at or before them":
    # the session messages are in the file in reverse order of start time
    let body = recordDefn & at(base - 5) & at(base + 10) & at(base + 99) &
      at(base + 100) & at(base + 150) &
      sessionDefn & session(base + 100, base + 150, sport = 1) &
      session(base, base + 99, sport = 2)
    let (a, _) = activities(body)
    check a.len == 2
    check a[0].startT == unixBase
    check a[0].session == 1                # its position in the file
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
    check a[0].startT == 1535373814        # 2018-08-27T12:43:34Z
    check a[0].utcOffsetS == some(-10_800)
    check a[0].coords.len == 2099
    check abs(a[0].coords[0].lat - (-398821890.0 * 180.0 / 2147483648.0)) < 1e-9
    check a[0].coords[0].t == a[0].startT
    check abs(a[0].distanceM.get - 11978.11) < 1e-6
    check a[0].coords[0].alt.isNone        # this device recorded no altitude

  test "a multisport file: every position goes to exactly one session":
    var ws: seq[Warning]
    let a = readActivities(p, readBytes(multisport), ws)
    check a.len == 7
    var n = 0                              # records with a position, counted again
    var r = initReader(p, readBytes(multisport))
    for rec in r.records(p):
      if rec.name == "record" and rec.timestamp.isSome and
          rec.timestamp.get >= minCalendarFit and
          rec.field("position_lat").isSome and rec.field("position_long").isSome:
        inc n
    var total = 0
    for k, s in a:
      total += s.coords.len
      if s.coords.len > 0:
        check s.coords[0].t >= s.startT or k == 0
        if k + 1 < a.len: check s.coords[^1].t < a[k + 1].startT
    check total + ws.filterIt(it.kind == wkDuplicateTime).len == n
