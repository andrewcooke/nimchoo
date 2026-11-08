import std/unittest
import nimchoo/importer/stretch

func auto(seconds: int64, metres: float): Gap =
  Gap(seconds: seconds, metres: metres, stoppedBy: trAuto, restartedBy: trAuto)

suite "stretches: when timer segments join":
  test "a pause where the rider did not move joins, however long":
    check auto(1, 0).joinable
    check auto(90, 4).joinable
    check auto(759, 9).joinable # a drink stop on a climb
    check auto(3 * 3600, 29.9).joinable
  test "thirty metres or more is not a pause, whatever the time":
    check not auto(3 * 3600, 30.0).joinable
    check not auto(600, 120).joinable
    check not auto(22560, 5057).joinable # the train
  test "a short gap in which the rider carried on at riding speed joins":
    check auto(29, 400).joinable # 13.8 m/s
    check auto(5, 70).joinable # 14 m/s
    check auto(1, 14).joinable # a second: speed is metres per second
    check auto(0, 29.9).joinable
  test "but not too fast, and not once the gap is not short":
    check not auto(29, 435).joinable # 15.0 m/s exactly
    check not auto(15, 1436).joinable # a GPS jump
    check not auto(30, 400).joinable # 13.3 m/s, but the gap is not short
    check not auto(120, 100).joinable
    check not auto(0, 40).joinable # no time at all is read as one second: 40 m/s
  test "a timer stopped or restarted by hand never joins":
    for stop in Trigger:
      for restart in Trigger:
        if stop == trManual or restart == trManual:
          check not Gap(seconds: 1, metres: 0, stoppedBy: stop, restartedBy: restart).joinable
        else:
          check Gap(seconds: 1, metres: 0, stoppedBy: stop, restartedBy: restart).joinable
  test "the longest jump the speed rule can join is bounded by its constants":
    check quickS.float * ridingMps == 450.0
    check not auto(quickS - 1, 450).joinable
  test "a negative gap is a bug, not an answer":
    expect AssertionDefect:
      discard auto(-1, 0).joinable
    expect AssertionDefect:
      discard auto(1, -1).joinable
