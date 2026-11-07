import std/[strutils, unittest]
import nimchoo/ui/[live, style]

const
  hide = "\e[?25l"
  show = "\e[?25h"
  erase = "\e[2K"
  below = "\e[J"

type Fake = ref object
  now: int64
  w, h: int
  written: seq[string]

proc newFake(w = 80, h = 24): Fake =
  Fake(w: w, h: h)

proc live(f: Fake, colour = false): Live =
  newLive(
    write = proc(s: string) {.closure, raises: [].} =
      f.written.add(s),
    now = proc(): int64 {.closure, raises: [].} =
      f.now,
    size = proc(): tuple[w, h: int] {.closure, raises: [].} =
      (f.w, f.h),
    colour = colour,
  )

func lines(xs: varargs[string]): seq[Line] =
  for x in xs:
    result.add plain(x)

suite "live region: when to draw":
  test "not before the first delay, then not more often than the interval":
    let f = newFake()
    let l = f.live
    check not l.due
    f.now = 149
    check not l.due
    f.now = 150
    check l.due
    l.show lines("x")
    f.now = 249
    check not l.due
    f.now = 250
    check l.due

  test "a thousand updates in a second make nine frames":
    let f = newFake()
    let l = f.live
    for i in 1 .. 1000:
      f.now = int64(i)
      if l.due:
        l.show lines("frame")
    check f.written.len == 9 # at 150, 250, ... 950 ms

suite "live region: what is drawn":
  test "the first frame hides the cursor and writes each line":
    let f = newFake()
    let l = f.live
    l.show lines("one", "two")
    check f.written == @[hide & erase & "one\n" & erase & "two\n" & below]

  test "the next frame goes back up over the region":
    let f = newFake()
    let l = f.live
    l.show lines("one", "two")
    l.show lines("ONE", "TWO")
    check f.written[1] == "\e[2A" & erase & "ONE\n" & erase & "TWO\n" & below

  test "a region that shrinks leaves nothing behind":
    let f = newFake()
    let l = f.live
    l.show lines("a", "b", "c")
    l.show lines("a")
    check f.written[1] == "\e[3A" & erase & "a\n" & below # erase-below clears b, c

  test "permanent lines go above the region, in order, once":
    let f = newFake()
    let l = f.live
    l.show lines("status")
    l.print plain("failed one")
    l.print plain("failed two")
    l.show lines("status")
    check f.written[1] ==
      "\e[1A" & erase & "failed one\n" & erase & "failed two\n" & erase & "status\n" &
      below
    l.show lines("status")
    check f.written[2] == "\e[1A" & erase & "status\n" & below

  test "the region is cut to the height, and its lines to the width":
    let f = newFake(w = 10, h = 5)
    let l = f.live
    var many: seq[Line]
    for i in 1 .. 10:
      many.add plain("a rather long line number " & $i)
    l.show many
    let drawn = f.written[0].split("\n")
    check drawn.len == 5 # four lines (h - 1) and the rest
    check drawn[0].endsWith("a rather…") # 9 columns: width - 1

  test "permanent lines are not cut":
    let f = newFake(w = 10)
    let l = f.live
    l.print plain("a failure message much longer than the width")
    l.show lines("x")
    check f.written[0].contains("a failure message much longer than the width")

  test "colour is used only when asked for":
    let f = newFake()
    f.live(colour = false).show @[@[span("x", red)]]
    f.live(colour = true).show @[@[span("x", red)]]
    check not f.written[0].contains("\e[31m")
    check f.written[1].contains("\e[31mx\e[0m")

suite "live region: finishing":
  test "the region is removed and the cursor comes back":
    let f = newFake()
    let l = f.live
    l.show lines("one", "two")
    l.finish
    check f.written[1] == "\e[2A" & below & show

  test "queued lines are printed even if no frame was ever drawn":
    let f = newFake()
    let l = f.live
    l.print plain("failed early")
    l.finish
    check f.written == @[erase & "failed early\n" & below] # cursor never hidden

  test "queued lines are printed when finishing, above where the region was":
    let f = newFake()
    let l = f.live
    l.show lines("status")
    l.print plain("last failure")
    l.finish
    check f.written[1] == "\e[1A" & erase & "last failure\n" & below & show

  test "keep leaves the last frame on screen, even if none was shown":
    let f = newFake()
    let l = f.live
    l.keep lines("one", "two")
    check f.written.len == 1
    check f.written[0].contains("one") and f.written[0].endsWith(below & show)
    check not f.written[0].contains("\e[2A")

  test "keep replaces the frame drawn before, and the next output starts below it":
    let f = newFake()
    let l = f.live
    l.show lines("a", "b")
    l.keep lines("A", "B")
    check f.written[1].startsWith("\e[2A")
    l.show lines("c") # a new region: no cursor-up over the kept lines
    check not f.written[2].contains("\e[2A")

  test "after finishing it can be used again":
    let f = newFake()
    let l = f.live
    l.show lines("a")
    l.finish
    l.show lines("b")
    check f.written[2].startsWith(hide)
