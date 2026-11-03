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

suite "ff stats: the lines":
  test "wording of the share":
    check share(Standing(value: 1, earlier: 120, higher: 0)) == "none of the 120 earlier days"
    check share(Standing(value: 1, earlier: 3, higher: 3)) == "all of the 3 earlier days"
    check share(Standing(value: 1, earlier: 1, higher: 0)) == "none of the 1 earlier day"
    check share(Standing(value: 1, earlier: 200, higher: 8)) == "4% of the 200 earlier days"
    check share(Standing(value: 1, earlier: 1000, higher: 2)) == "<1% of the 1000 earlier days"
    check share(Standing(value: 1, earlier: 1000, higher: 999)) == ">99% of the 1000 earlier days"
  test "the lines: when, then fitness in green and fatigue in red":
    let ls = statLines("as of 14:00 on 2026-11-03", some(Standing(value: 71.4894, earlier: 200, higher: 8)),
                       some(Standing(value: 3.0, earlier: 200, higher: 100)), 1, 5)
    check ls.len == 3
    check ls[0].text == "as of 14:00 on 2026-11-03:"
    check ls[1].text == "  fitness    71.49   (higher on 4% of the 200 earlier days)"
    check ls[2].text == "  fatigue    15.00   (higher on 50% of the 200 earlier days)"      # (scaled by 5; the share is not)
    check ls[1][0].look.fg == cGreen and ls[2][0].look.fg == cRed
    check ls[1].render(false) == ls[1].text and ls[1].render(true) != ls[1].text
  test "no earlier days, and no value yet":
    let ls = statLines("x", some(Standing(value: 1, earlier: 0, higher: 0)), none(Standing), 1, 1)
    check ls[1].text.endsWith("(no earlier days to compare with)")
    check ls[2].text.endsWith("nothing yet")
