## How numbers are written with their units, for the descriptions every module makes of its own things (see AGENTS.md,
## "describing things"): the unit follows the number with no space ("36.7km", as in "4h41m", see interval.nim).  Pure.

import std/[math, strutils]

{.push raises: [].}

const notRecorded* = "-" ## said of a value that is not there

func kmNumber*(metres: float): string =
  ## "102.7": kilometres to a tenth, with commas from 1,000.
  let tenths = int(round(metres / 100.0))
  insertSep($(tenths div 10), ',') & "." & $(tenths mod 10)

func km*(metres: float): string =
  ## "102.7km": the unit follows the number with no space.
  kmNumber(metres) & "km"

func humanBytes*(n: int64): string =
  ## "1.4MB", "85kB", "12B": no space before the unit.
  if n >= 1_000_000:
    formatFloat(float(n) / 1e6, ffDecimal, 1) & "MB"
  elif n >= 1_000:
    $(n div 1_000) & "kB"
  else:
    $n & "B"
