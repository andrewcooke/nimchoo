import std/[math, unittest]
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

  test "a frame's name is the channel's as one word":
    check frameName(chHeartRate) == "heartrate"
    check frameName(chDistance) == "distance"
