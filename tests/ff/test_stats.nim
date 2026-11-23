import std/[options, sequtils, unittest]
import nimchoo/packages/ff/stats
import nimchoo/packages/ui/style

suite "ff stats: standing among the earlier days":
  test "the value, and how many of the days before were higher":
    let st = standing(20, [10.0, 20, 30, 40, 50, 40, 30])
    check st.value == 20 and st.earlier == 7 and st.higher == 5
      # 30, 40, 50, 40, 30 are higher than 20; an equal one is not
  test "the highest value so far: none were higher; the lowest: all":
    check standing(60, [10.0, 50]).higher == 0
    check standing(5, [10.0, 50]).higher == 2
  test "the first day has nothing to compare with":
    check standing(5, []) == Standing(value: 5, earlier: 0, higher: 0)

suite "ff stats: the line":
  test "wording of the share":
    check top(Standing(value: 1, earlier: 120, higher: 0)) == "top 0%"
    check top(Standing(value: 1, earlier: 3, higher: 3)) == "top 100%"
    check top(Standing(value: 1, earlier: 200, higher: 8)) == "top 4%"
    check top(Standing(value: 1, earlier: 1000, higher: 2)) == "top <1%"
    check top(Standing(value: 1, earlier: 1000, higher: 999)) == "top >99%"
    check top(Standing(value: 1, earlier: 0, higher: 0)) == "top 0%"
  test "one line, with the numbers emphasised: fitness good, fatigue bad":
    let l = statLine(
      "2026-11-03 15:00",
      some(Standing(value: 71.4894, earlier: 200, higher: 8)),
      some(Standing(value: 3.0, earlier: 200, higher: 100)),
      1,
      5,
    )
    check l.text == "2026-11-03 15:00  fitness: 71.5 (top 4%),  fatigue: 15.0 (top 50%)"
      # (scaled by 5; the share is not)
    var styled: seq[(string, seq[string])]
    for sp in l:
      if sp.styles.len > 0:
        styled.add (sp.text, sp.styles.mapIt($it))
    check styled ==
      @[("71.5 (top 4%)", @["good", "em"]), ("15.0 (top 50%)", @["bad", "em"])]
  test "no earlier days: the value only; no value yet: a dash":
    let l = statLine(
      "x", some(Standing(value: 1, earlier: 0, higher: 0)), none(Standing), 1, 1
    )
    check l.text == "x  fitness: 1.0,  fatigue: -"
