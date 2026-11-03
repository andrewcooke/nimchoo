import std/[math, options, strutils, times, unittest]
import nimchoo/ff/[curve, stats]
import nimchoo/model/calc
import nimchoo/ui/style

proc near(a, b: float, eps = 1e-9): bool = abs(a - b) <= eps

# a value for every hour of ten days (UTC), rising for five days and falling for five
proc series(): seq[Hourly] =
  for h in 0 ..< 240:
    let day = h div 24
    let v = if day < 5: float(day) * 10.0 + 10 else: float(9 - day) * 10.0 + 10   # 10 20 30 40 50 | 40 30 20 10 0 ... by day
    result.add (int64(h) * 3600, v)

suite "ff stats: standing among the earlier days":
  let u = utc()
  test "the value, and how many of the days before were higher":
    let s = series()
    # the last hour of day 7: its value is 20; the earlier days (0 to 6) ended at 10 20 30 40 50 40 30
    let asOf = int64(7 * 24 + 23) * 3600
    let st = standingAt(s, asOf, int64(7 * 24) * 3600, u).get
    check st.value == float(9 - 7) * 10.0 + 10
    check st.earlier == 7 and st.higher == 4                  # 30, 40, 50, 40 are higher than 20
  test "the highest value so far: none were higher; the lowest: all":
    let s = series()
    let top = standingAt(s, int64(4 * 24 + 23) * 3600, int64(4 * 24) * 3600, u).get
    check top.higher == 0 and top.earlier == 4
    let low = standingAt(s, int64(9 * 24 + 23) * 3600, int64(9 * 24) * 3600, u).get
    check low.higher == 8 and low.earlier == 9                 # (day 0 ended equal: not higher)
  test "the first day has nothing to compare with; an hour that is not there has no standing":
    let s = series()
    check standingAt(s, 5 * 3600, 0, u).get.earlier == 0
    check standingAt(s, int64(999) * 3600, 0, u).isNone
  test "equal values are not higher":
    var s: seq[Hourly]
    for h in 0 ..< 72: s.add (int64(h) * 3600, 5.0)
    let st = standingAt(s, int64(2 * 24 + 5) * 3600, int64(2 * 24) * 3600, u).get
    check st.earlier == 2 and st.higher == 0

suite "ff stats: the line":
  test "wording of the share":
    check top(Standing(value: 1, earlier: 120, higher: 0)) == "top 0%"
    check top(Standing(value: 1, earlier: 3, higher: 3)) == "top 100%"
    check top(Standing(value: 1, earlier: 200, higher: 8)) == "top 4%"
    check top(Standing(value: 1, earlier: 1000, higher: 2)) == "top <1%"
    check top(Standing(value: 1, earlier: 1000, higher: 999)) == "top >99%"
    check top(Standing(value: 1, earlier: 0, higher: 0)) == "top 0%"
  test "one line, with the numbers coloured: fitness green, fatigue red":
    let l = statLine("2026-11-03 15:00", some(Standing(value: 71.4894, earlier: 200, higher: 8)),
                     some(Standing(value: 3.0, earlier: 200, higher: 100)), 1, 5)
    check l.text == "2026-11-03 15:00  fitness: 71.5 (top 4%),  fatigue: 15.0 (top 50%)"     # (scaled by 5; the share is not)
    var coloured: seq[(string, Color)]
    for sp in l:
      if sp.look.fg != cNone: coloured.add (sp.text, sp.look.fg)
    check coloured == @[("71.5 (top 4%)", cGreen), ("15.0 (top 50%)", cRed)]
    check l.render(false) == l.text and l.render(true) != l.text
  test "no earlier days: the value only; no value yet: a dash":
    let l = statLine("x", some(Standing(value: 1, earlier: 0, higher: 0)), none(Standing), 1, 1)
    check l.text == "x  fitness: 1.0,  fatigue: -"
