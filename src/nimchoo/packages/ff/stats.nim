## What `nch ff` says about the latest values of the curves, in a line: each value, and the share
## of the earlier days on which it was higher ("top 1%" means only 1% of earlier days were higher:
## nearly the highest it has been).  Fitness is green and fatigue red, as in the chart.
## Pure: lines of styled spans (see packages/ui/style.nim), drawn with or without colour by the caller.

import std/[options, strutils]
import ../ui/style
import ./curve

{.push raises: [].}

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
    name: string, colour: Color, standing: Option[Standing], scale: float
): Line =
  result.add plain(name & ": ")
  if standing.isNone:
    result.add plain("-")
    return
  let s = standing.get
  let value = formatFloat(s.value * scale, ffDecimal, 1)
  result.add span(
    if s.earlier == 0:
      value
    else:
      value & " (" & top(s) & ")",
    colour,
    bold = true,
  )

func statLine*(
    label: string, fitness, fatigue: Option[Standing], fitnessScale, fatigueScale: float
): Line =
  ## One line: the label (when the values are for), then the two curves (the number and the "top" share
  ## coloured: fitness green, fatigue red).  The values are multiplied by the scales, as in the
  ## file; the share does not depend on them.
  result = plain(label & "  ")
  result.add curve("fitness", green, fitness, fitnessScale)
  result.add plain(",  ")
  result.add curve("fatigue", red, fatigue, fatigueScale)
