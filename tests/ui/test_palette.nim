import std/unittest
import nimchoo/packages/ui/palette

suite "palette: the colours of the web pages, named in one place":
  test "there are six, in the order white, grey, red, green, yellow, blue":
    check ord(high(Color)) == 5
    check @[white, grey, red, green, yellow, blue] ==
      @[Color(0), Color(1), Color(2), Color(3), Color(4), Color(5)]
  test "each has a web colour, and they differ":
    for c in Color:
      check hex(c).len == 7 and hex(c)[0] == '#'
    check hex(green) != hex(red) and hex(white) != hex(grey) and hex(blue) != hex(
      yellow
    )
