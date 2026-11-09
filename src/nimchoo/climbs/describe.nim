## How a climb is said, wherever one is shown (`nch climbs` ...): like `__str__`.  The climbs module owns
## climbs, so it says them; a command that shows one uses this and makes no format of its own.
##
##     Cerro San Luis (4/5)  4 0.5km +89m 17.8%
##
## Its name (as shown, with the number among those that share it), its category, its length, its gain and its gradient.
## No space between a number and its unit.  `climbCells` gives the parts, to be lined up in the columns of a table;
## `climbLine` one line.  Pure.

import std/strutils
import ../packages/ui/units

{.push raises: [].}

type ClimbInfo* = object
  name*: string ## as shown ("Cerro San Luis (4/5)"), cut to fit if need be by the caller
  category*: string ## "4", "3", "2", "1" or "HC"; "" if too small to have one
  lengthM*, gainM*, gradient*: float ## metres, metres, percent

func gainText*(metres: float): string =
  ## "+89m".
  "+" & $int(metres + 0.5) & "m"

func gradientText*(percent: float): string =
  ## "17.8%".
  formatFloat(percent, ffDecimal, 1) & "%"

func climbCells*(c: ClimbInfo): seq[string] =
  ## The parts of a climb, to be lined up in columns: name, category, length, gain, gradient.
  @[
    c.name,
    if c.category.len > 0: c.category else: notRecorded,
    km(c.lengthM),
    gainText(c.gainM),
    gradientText(c.gradient),
  ]

func climbLine*(c: ClimbInfo): string =
  ## The climb on one line: "Cerro San Luis (4/5)  4 0.5km +89m 17.8%".
  let x = climbCells(c)
  x[0] & "  " & x[1] & " " & x[2] & " " & x[3] & " " & x[4]
