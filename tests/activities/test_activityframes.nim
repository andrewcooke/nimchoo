import std/[math, sequtils, unittest]
import nimchoo/core/[extension, ids]
import nimchoo/packages/db/statement
import nimchoo/packages/user/session
import ../support/[env, rideworld]
from nimchoo/registry import allFragments, allAccess, extensions
import nimchoo/packages/activities/activityframes
import nimchoo/packages/channels/kinds
import nimchoo/packages/plot/frames
import nimchoo/packages/fit/time
import nimchoo/packages/importer/stretch

func shape(points: seq[Point]): seq[string] =
  ## each point as its time, or "|" where the line breaks
  for (t, v) in points:
    result.add(
      if v.isNaN:
        "|"
      else:
        $t
    )

suite "activity: the frames of one activity":
  test "a line breaks across a manual stop, a car and a pause; not at a GPS error":
    func brk(a, b: int64, kind: BreakKind): Break =
      Break(startT: UnixTime(a), endT: UnixTime(b), kind: kind)
    let points = @[
      (1'i64, 1.0),
      (2'i64, 1.0),
      (10'i64, 1.0),
      (11'i64, 1.0),
      (20'i64, 1.0),
      (21'i64, 1.0),
      (30'i64, 1.0),
      (31'i64, 1.0),
      (40'i64, 1.0),
    ]
    let breaks = @[
      brk(2, 10, bkPause),
      brk(11, 20, bkManual),
      brk(21, 30, bkCarried),
      brk(30, 31, bkError),
    ]
    check shape(breakAt(points, breaks)) ==
      @["1", "2", "|", "10", "11", "|", "20", "21", "|", "30", "31", "40"]
    check shape(breakAt(points, @[])) ==
      @["1", "2", "10", "11", "20", "21", "30", "31", "40"]
    check breakAt(@[], breaks).len == 0

  test "the speed is drawn in km/h and the distance in km; the others in their own units":
    check shownAs(chSpeed) == ("km/h", 3.6)
    check shownAs(chDistance) == ("km", 0.001)
    check shownAs(chHeartRate) == ("bpm", 1.0)

  test "a frame's name is the channel's as one word":
    check frameName(chHeartRate) == "heartrate"
    check frameName(chDistance) == "distance"

suite "activity: cadence, and a run's steps":
  test "a ride's cadence is in rpm and it has no steps; a run's is drawn only as steps, twice as many":
    let w = world("activity-steps", ride = "2018-03-04-qdp.fit") # (one with cadence)
    let s = openSession(w.db, allFragments, access = allAccess)
    defer:
      s.close()
      useTestCache()
    let id = ActivityId(s.db.scalar(int64, "select id from activity"))
    var cadence, steps: PlotFrame
    for f in extensions.get(plotFramePoint):
      if f.subject == "activity" and f.name == "cadence":
        cadence = f
      if f.subject == "activity" and f.name == "steps":
        steps = f
    check cadence.unit == "rpm" and steps.unit == "steps/min"
    func values(d: PlotData): seq[float] =
      for x in d.series:
        for (t, v) in x.points:
          if not v.isNaN:
            result.add v
    let rpm = values(cadence.makeActivity(s, id))
    check rpm.len > 0 and values(steps.makeActivity(s, id)).len == 0
    s.db.execute("update activity set sport = 'running' where id = :id", id = id)
    check values(cadence.makeActivity(s, id)).len == 0
    check values(steps.makeActivity(s, id)) == rpm.mapIt(it * 2)
