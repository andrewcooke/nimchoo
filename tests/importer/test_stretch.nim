import std/[options, unittest]
import nimchoo/packages/fit/time
import nimchoo/packages/importer/stretch

func auto(seconds: int64, metres: float): Gap =
  Gap(seconds: seconds, metres: metres, stoppedBy: trAuto, restartedBy: trAuto)

const
  pause = some(bkPause)
  carried = some(bkCarried)
  manual = some(bkManual)
  blink = none(BreakKind)

func span(a, b: int64): Span =
  Span(startT: UnixTime(a), endT: UnixTime(b))

func brk(a, b: int64, kind: BreakKind): Break =
  Break(startT: UnixTime(a), endT: UnixTime(b), kind: kind)

suite "the breaks of a ride: what a gap of the timer was":
  test "where the rider did not move it is a pause, however long":
    check auto(1, 0).kindOf == pause
    check auto(90, 4).kindOf == pause
    check auto(759, 9).kindOf == pause # a drink stop on a climb
    check auto(3 * 3600, 29.9).kindOf == pause
    check auto(0, 29.9).kindOf == pause
  test "thirty metres or more is not a pause, whatever the time: carried":
    check auto(3 * 3600, 30.0).kindOf == carried
    check auto(600, 120).kindOf == carried
    check auto(22560, 5057).kindOf == carried # the train
  test "a short gap in which the rider carried on at riding speed is a blink: no break":
    check auto(29, 400).kindOf == blink # 13.8 m/s
    check auto(5, 70).kindOf == blink # 14 m/s
    check auto(3, 40).kindOf == blink # 13.3 m/s: speed is metres per second
    check auto(1, 14).kindOf == pause # (under 30 m: a pause, whatever the speed)
  test "but not too fast, and not once the gap is not short":
    check auto(29, 435).kindOf == carried # 15.0 m/s exactly
    check auto(15, 1436).kindOf == carried # a GPS jump
    check auto(30, 400).kindOf == carried # 13.3 m/s, but the gap is not short
    check auto(120, 100).kindOf == carried
    check auto(0, 40).kindOf == carried # no time at all is read as one second: 40 m/s
  test "the device must have stopped the timer, else it is manual; the restart may be by hand":
    for stop in Trigger:
      for restart in Trigger:
        let g = Gap(seconds: 1, metres: 0, stoppedBy: stop, restartedBy: restart)
        check g.kindOf ==
          (if stop == trAuto and restart in {trAuto, trManual}: pause else: manual)
  test "a restart by hand is judged like any other: by how far and how fast":
    check Gap(seconds: 97, metres: 0, stoppedBy: trAuto, restartedBy: trManual).kindOf ==
      pause
    check Gap(seconds: 97, metres: 40, stoppedBy: trAuto, restartedBy: trManual).kindOf ==
      carried
    check Gap(seconds: 20, metres: 200, stoppedBy: trAuto, restartedBy: trManual).kindOf ==
      blink
  test "with no positions, a pause if the device stopped the timer, else manual":
    check unmeasuredKind(trAuto, trAuto) == bkPause
    check unmeasuredKind(trAuto, trManual) == bkPause
    check unmeasuredKind(trManual, trAuto) == bkManual
    check unmeasuredKind(trOther, trOther) == bkManual
  test "the longest jump the speed rule can call a blink is bounded by its constants":
    check quickS.float * ridingMps == 450.0
    check auto(quickS - 1, 450).kindOf == carried
  test "a negative gap is a bug, not an answer":
    expect AssertionDefect:
      discard auto(-1, 0).kindOf
    expect AssertionDefect:
      discard auto(1, -1).kindOf
  test "each user takes its kinds: stretches end at manual, carried and error; time at manual, carried and pause":
    check stretchBreaks == {bkManual, bkCarried, bkError}
    check timeBreaks == {bkManual, bkCarried, bkPause}

suite "the stretches of riding: the riding cut at its breaks":
  test "no break is one stretch; a pause joins; manual, carried and error cut":
    check stretchesOf(span(0, 100), @[]) == @[span(0, 100)]
    check stretchesOf(span(0, 100), @[brk(10, 20, bkPause)]) == @[span(0, 100)]
    check stretchesOf(
      span(0, 100),
      @[
        brk(10, 20, bkManual),
        brk(30, 40, bkPause),
        brk(49, 50, bkError),
        brk(60, 70, bkCarried),
      ],
    ) == @[span(0, 10), span(20, 49), span(50, 60), span(70, 100)]
