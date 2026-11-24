import std/[math, unittest]
import nimchoo/packages/activities/activityframes
import nimchoo/packages/channels/kinds
import nimchoo/packages/plot/frames

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
  test "a line breaks where the readings stop for more than pauseS, and only there":
    let points = @[
      (1'i64, 1.0),
      (2'i64, 1.0),
      (12'i64, 1.0),
      (12'i64 + pauseS + 1, 1.0),
      (50'i64, 1.0),
    ]
    check shape(breakAtPauses(points)) ==
      @["1", "2", "12", "|", $(12 + pauseS + 1), "|", "50"]
        # (10 s apart, as smart recording is: no break)
    check shape(breakAtPauses(@[(1'i64, 1.0), (1'i64 + pauseS, 1.0)])) ==
      @["1", $(1 + pauseS)]
    check breakAtPauses(@[]).len == 0

  test "a frame's name is the channel's as one word":
    check frameName(chHeartRate) == "heartrate"
    check frameName(chDistance) == "distance"
