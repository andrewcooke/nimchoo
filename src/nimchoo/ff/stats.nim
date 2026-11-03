## What `nch ff` says about the latest values of the curves, in a few lines: the value, and the
## share of the earlier days on which it was higher (so "1%" means only 1% of earlier days were
## higher: a high value for that curve).  Fitness is green and fatigue red, as in the chart.
## Pure: lines of styled spans (see ui/style.nim), drawn with or without colour by the caller.

import std/[options, strutils]
import ../ui/style
import ./curve

{.push raises: [].}

func share*(s: Standing): string =
  ## "none of the 120 earlier days", "4% of the 120 earlier days", "all of the 3 earlier days".
  let days = $s.earlier & " earlier " & (if s.earlier == 1: "day" else: "days")
  if s.higher == 0: "none of the " & days
  elif s.higher == s.earlier: "all of the " & days
  else:
    let pc = 100.0 * float(s.higher) / float(s.earlier)
    (if pc < 0.5: "<1%" elif pc >= 99.5: ">99%" else: $int(pc + 0.5) & "%") & " of the " & days

func curveLine(name: string, colour: Color, standing: Option[Standing], scale: float): Line =
  result.add span("  " & name.alignLeft(8), colour, bold = true)
  if standing.isNone:
    result.add plain("nothing yet")
    return
  let s = standing.get
  result.add span(formatFloat(s.value * scale, ffDecimal, 2).align(8), colour, bold = true)
  result.add plain(
    if s.earlier == 0: "   (no earlier days to compare with)"
    else: "   (higher on " & share(s) & ")")

func statLines*(asOf: string, fitness, fatigue: Option[Standing], fitnessScale, fatigueScale: float): seq[Line] =
  ## The lines: when the values are for, then the two curves.  (The values are multiplied by
  ## the scales, as in the file; the comparison does not depend on them.)
  @[plain(asOf & ":"),
    curveLine("fitness", cGreen, fitness, fitnessScale),
    curveLine("fatigue", cRed, fatigue, fatigueScale)]
