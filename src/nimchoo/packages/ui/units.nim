## How numbers are written with their units, for the descriptions every module makes of its own things (the rules are in the
## `ui` package's documentation): the unit follows the number with no space ("36.7km", as in "4h41m", see interval.nim).  Pure.

import std/[math, options, strutils]

{.push raises: [].}

type
  Distance* = distinct float ## a distance in metres: finite and more than zero
  TimeSpan* = distinct float ## a length of time in seconds: finite and more than zero

func inMetres*(d: Distance): float =
  ## The distance in metres.
  float(d)

func inKm*(d: Distance): float =
  ## The distance in kilometres.
  float(d) / 1000.0

func inSeconds*(t: TimeSpan): float =
  ## The length of time in seconds.
  float(t)

func inDays*(t: TimeSpan): float =
  ## The length of time in days.
  float(t) / 86400.0

func `==`*(a, b: Distance): bool {.borrow.}
func `==`*(a, b: TimeSpan): bool {.borrow.}

func unitNumber*(s: string, number: var float, unit: var string): bool =
  ## Split "1.5km" into 1.5 and "km": the number is digits with at most one point (no sign, no exponent, no `nan` or `inf`:
  ## a value the user types is a plain quantity) and finite; the unit is what follows (it may be empty, and is then not checked).
  var n = 0
  var points = 0
  while n < s.len and (s[n] in {'0' .. '9'} or (s[n] == '.' and points == 0)):
    if s[n] == '.':
      inc points
    inc n
  if n == 0 or s[0] == '.' and n == 1:
    return false
  try:
    number = parseFloat(s[0 ..< n])
  except ValueError:
    return false
  unit = s[n .. ^1]
  classify(number) in {fcNormal, fcSubnormal, fcZero}

func parseDistance*(s: string): Option[Distance] =
  ## A distance with its unit, `1.5km` or `100m`, as the program writes them (`km`): more than zero and finite; none for
  ## anything else, a missing or unknown unit included.  (In a distance `m` is metres; in a duration, minutes.)
  var x: float
  var unit: string
  if not unitNumber(s, x, unit):
    return none(Distance)
  let metres =
    case unit
    of "km":
      x * 1000.0
    of "m":
      x
    else:
      return none(Distance)
  if metres > 0.0 and classify(metres) in {fcNormal, fcSubnormal}:
    some(Distance(metres))
  else:
    none(Distance)

func parseTimeSpan*(s: string): Option[TimeSpan] =
  ## A length of time with its units, as `interval` writes them: `60s`, `42d`, `2h30m`, `2d03h07m` (units `d`, `h`, `m`
  ## and `s`, the largest first, each at most once; in a duration `m` is minutes): more than zero and finite; none for
  ## anything else, a missing or unknown unit included.
  const unitSeconds = [('d', 86400.0), ('h', 3600.0), ('m', 60.0), ('s', 1.0)]
  var rest = s
  var total = 0.0
  var at = 0 # the units up to this index are used
  while rest.len > 0:
    var n = 0
    while n < rest.len and rest[n] in {'0' .. '9', '.'}:
      inc n
    if n == rest.len:
      return none(TimeSpan) # a number with no unit
    var x: float
    var ignore: string
    if not unitNumber(rest[0 .. n], x, ignore) or ignore.len != 1:
      return none(TimeSpan)
    var found = -1
    for k in at ..< unitSeconds.len:
      if unitSeconds[k][0] == rest[n]:
        found = k
    if found < 0:
      return none(TimeSpan)
    at = found + 1
    total += x * unitSeconds[found][1]
    rest = rest[n + 1 .. ^1]
  if s.len > 0 and total > 0.0 and classify(total) in {fcNormal, fcSubnormal}:
    some(TimeSpan(total))
  else:
    none(TimeSpan)

const notRecorded* = "-" ## said of a value that is not there

func count*(n: int64): string =
  ## "1,113": a count, with commas from 1,000 (every count the program shows is written so).
  insertSep($n, ',')

func counted*(n: int64, one, many: string): string =
  ## "1 activity", "1,113 activities": a count and what it counts, singular for one.
  count(n) & " " & (if n == 1: one else: many)

func kmNumber*(metres: float): string =
  ## "102.7": kilometres to a tenth, with commas from 1,000.
  let tenths = int(round(metres / 100.0))
  count(tenths div 10) & "." & $(tenths mod 10)

func km*(metres: float): string =
  ## "102.7km": the unit follows the number with no space.
  kmNumber(metres) & "km"

func plainNumber*(x: float): string =
  ## Without a pointless decimal part (to four places): 5.0 -> "5", 1.25 -> "1.25".
  formatFloat(x, ffDecimal, 4).strip(leading = false, chars = {'0'}).strip(
    leading = false, chars = {'.'}
  )

func humanBytes*(n: int64): string =
  ## "1.4MB", "85kB", "12B": no space before the unit.
  if n >= 1_000_000:
    formatFloat(float(n) / 1e6, ffDecimal, 1) & "MB"
  elif n >= 1_000:
    $(n div 1_000) & "kB"
  else:
    $n & "B"
