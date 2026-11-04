import std/unittest
import nimchoo/ui/[palette, style]

suite "palette: five colours, named in one place":
  test "there are five, in the order white, grey, red, green, yellow":
    check ord(high(Color)) == 4
    check @[white, grey, red, green, yellow] == @[Color(0), Color(1), Color(2), Color(3), Color(4)]
  test "each has a terminal code (white none) and a web colour":
    check terminalCode(white) == ""
    check terminalCode(grey) == "\e[38;5;240m"
    check terminalCode(red) == "\e[31m" and terminalCode(green) == "\e[32m" and terminalCode(yellow) == "\e[33m"
    for c in Color:
      check hex(c).len == 7 and hex(c)[0] == '#'
    check hex(green) != hex(red) and hex(white) != hex(grey)
  test "lines are drawn from the palette, with or without colour":
    let line = @[span("a", green), span("b", red, bold = true), span("c", grey), span("d")]
    check line.render(false) == "abcd"
    check line.render(true) == terminalCode(green) & "a" & resetCode &
      terminalCode(red) & "\e[1m" & "b" & resetCode & terminalCode(grey) & "c" & resetCode & "d"
