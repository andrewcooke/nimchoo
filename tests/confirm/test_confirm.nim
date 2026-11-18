import std/[sequtils, strutils, unittest]
import nimchoo/packages/confirm/confirm
import nimchoo/packages/ui/live
import nimchoo/packages/ui/style
import ../support/styles

suite "confirm: the countdown":
  test "the countdown line is bad, with the number emphasised":
    let l = countdownLine("74 activities for all users", 4)
    check l.text == "deleting 74 activities for all users in 4 s ... (Ctrl-C to cancel)"
    check l.allIt($it.styles[0] == "bad")
    check l[1].text == "4" and emphasised(l[1])

  test "it counts down once a second, then takes the line away":
    var written: seq[string]
    var waits: seq[int]
    let l = newLive(
      write = proc(s: string) {.closure, raises: [].} =
        written.add(s),
      now = proc(): int64 {.closure, raises: [].} =
        0,
      size = proc(): tuple[w, h: int] {.closure, raises: [].} =
        (100, 24),
      paint = Paint(colour: false),
    )
    countdown(
      l,
      "x",
      3,
      proc(ms: int) {.closure, raises: [].} =
        waits.add(ms),
    )
    check waits == @[1000, 1000, 1000]
    check written.len == 4 # three frames, then the removal
    check written[0].contains("in 3 s") and written[1].contains("in 2 s") and
      written[2].contains("in 1 s")
    check written[3].endsWith("\e[?25h") # the cursor is back
