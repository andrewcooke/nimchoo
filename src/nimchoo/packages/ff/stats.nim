## What `nch ff` says about the latest values of the curves, in a line: each value, and the share
## of the earlier days on which it was higher ("top 1%" means only 1% of earlier days were higher:
## nearly the highest it has been).  Fitness is good and fatigue bad (each emphasised), as in the chart.
## Pure: lines of styled spans (see packages/ui/style.nim), drawn with or without colour by the caller.

import std/[options, strutils]
import ../ui/style

{.push raises: [].}

type Standing* = object ## A value of a curve, and how it compares with the days before.
  value*: float
  earlier*: int ## days before (with a value) to compare with
  higher*: int ## how many of those had a higher value

func standing*(value: float, earlier: openArray[float]): Standing =
  ## A value, and how many of the earlier days' values (each at the end of its day) were higher.
  result = Standing(value: value, earlier: earlier.len)
  for e in earlier:
    if e > value:
      inc result.higher

func top*(s: Standing): string =
  ## The share of the earlier days that were higher, as "top 4%": the smaller, the nearer the
  ## highest the curve has been.  "top <1%" if some were higher but fewer than 1 in 200; "top 0%" if
  ## none were.
  if s.earlier == 0 or s.higher == 0:
    return "top 0%"
  if s.higher == s.earlier:
    return "top 100%"
  let pc = 100.0 * float(s.higher) / float(s.earlier)
  "top " & (if pc < 0.5: "<1%" elif pc >= 99.5: ">99%" else: $int(pc + 0.5) & "%")

func curve(
    name: string, style: StyleName, standing: Option[Standing], scale: float
): Line =
  result.add plain(name & ": ")
  if standing.isNone:
    result.add plain("-")
    return
  let s = standing.get
  let value = formatFloat(s.value * scale, ffDecimal, 1)
  result.add Span(
    text:
      if s.earlier == 0:
        value
      else:
        value & " (" & top(s) & ")",
    styles: @[style, styleName"em"],
  )

func statLine*(
    label: string, fitness, fatigue: Option[Standing], fitnessScale, fatigueScale: float
): Line =
  ## One line: the label (when the values are for), then the two curves (the number and the "top" share
  ## emphasised, fitness good and fatigue bad).  The values are multiplied by the scales, as in the
  ## file; the share does not depend on them.
  result = plain(label & "  ")
  result.add curve("fitness", styleName"good", fitness, fitnessScale)
  result.add plain(",  ")
  result.add curve("fatigue", styleName"bad", fatigue, fatigueScale)
