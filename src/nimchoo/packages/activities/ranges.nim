## Ranges typed on the command line: `40-` (40 or more), `10-50`, `-5` (up to 5), and
## "around" ranges `42~2` (40 to 44), `2h~15m`, `latest~10%`, for distances and for active
## times.  Pure.
##
## An end has its unit, read by the shared readers (`ui/units`): a distance `40km` or `500m`, a time as the program prints it
## (see packages/ui/interval.nim): `45s`, `22m`, `1h30m`, `2d`.  A unit may be left out of a range, but **whenever the program
## fills one in it asks** (`fillUnits`: `42~2km` is suggested as `42km~2km`, `10-50` as `10km-50km`): only a range with
## every unit written goes through.
## Both ends of a range are inclusive, and either may be left out (not both).

import std/[math, options, sequtils, strutils]
import ../ui/units

{.push raises: [].}

type
  Referent* = enum
    ## An activity a criterion is measured against, found when the command runs: the
    ## newest of those that meet the other criteria, or the one that was selected before.
    rfLatest
    rfPrevious

  EndParser* = proc(s: string): Option[float] {.nimcall, noSideEffect, raises: [].}

  Tol* = object
    ## How far from a centre: an amount (metres, seconds) or a percentage of the centre.
    amount*: float
    percent*: bool

  Around* = object
    ## `centre~tolerance`; the centre is a value, or an activity found when the command runs.
    tol*: Tol
    case byReference*: bool
    of false:
      centre*: float
    of true:
      refers*: Referent

  NumRange* = object ## Metres or seconds.
    lo*, hi*: Option[float]

func isOpen*(r: NumRange): bool =
  ## Whether the range has no ends: anything is in it.
  r.lo.isNone and r.hi.isNone

func metresEnd*(s: string): Option[float] =
  ## An end of a distance range (`40km`, `500m`) in metres: the shared reader (`ui/units`).
  let d = units.parseDistance(s.strip)
  if d.isSome:
    some(d.get.inMetres)
  else:
    none(float)

func secondsEnd*(s: string): Option[float] =
  ## An end of a time range (`1h30m`, `45s`, as the program prints them) in seconds: the shared reader (`ui/units`).
  let t = parseTimeSpan(s.strip)
  if t.isSome:
    some(t.get.inSeconds)
  else:
    none(float)

type Side = object
  ## One side of a range or of an `around`: `42km`, `15m`, `10%`, `latest`, `2h30m`, or nothing.
  text: string
  number: string
    ## the digits (and point) it starts with; "" if it does not start with a number
  unit: string ## what follows the number

func side(s: string): Side =
  var x: float
  var rest: string
  if unitNumber(s, x, rest):
    let u = rest.len
    Side(text: s, number: s[0 ..< s.len - u], unit: rest)
  else:
    Side(text: s)

func sides(s: string): Option[tuple[sep: char, parts: seq[Side]]] =
  ## The two sides of `a~b` or of `a-b` (`-b` and `a-` too), and the separator; none if it is neither.
  let sep = if '~' in s: '~' else: '-'
  let parts = s.split(sep)
  if parts.len != 2:
    return none(tuple[sep: char, parts: seq[Side]])
  some((sep: sep, parts: parts.mapIt(side(it))))

func isAmount(x: Side): bool =
  ## Whether the side is a number that may carry a unit (not `latest`, a percentage or nothing).
  x.number.len > 0 and x.unit != "%"

func isSingleUnit(x: Side): bool =
  x.isAmount and x.unit.len > 0 and x.unit.allIt(it notin {'0' .. '9', '.'})

type UnitsBelow* = openArray[tuple[unit, below: string]]
  ## for each unit, the next one down (`km` -> `m`; the last has none: it is its own)

const
  distanceUnitsBelow* = [("km", "m"), ("m", "m")]
  timeUnitsBelow* = [("d", "h"), ("h", "m"), ("m", "s"), ("s", "s")]

func below(units: UnitsBelow, unit: string): string =
  for (u, b) in units:
    if u == unit:
      return b
  unit

func fillUnits*(s: string, default: string, units: UnitsBelow): Option[string] =
  ## Where a range or an `around` lacks a unit, the text with it filled in; none if every unit is there or nothing can be
  ## filled (the reader then accepts or refuses the text).  The program asks about every unit it fills in (`pkUnit`); this is
  ## what it suggests:
  ##
  ## * `a~b`: a spread with no unit takes the centre's if its number is not larger than the centre's (`42km~2` -> `42km~2km`),
  ##   else the unit below it (`42km~200` -> `42km~200m`); a centre with no unit takes the spread's (`42~2km` -> `42km~2km`);
  ##   neither has one: the default on both (`40~2` -> `40km~2km`); a centre `latest` or `previous` has a spread alone
  ##   (`latest~5` -> `latest~5km`; a percentage needs no unit);
  ## * `a-b`: a side with no unit takes the other's (`10-50km` -> `10km-50km`); neither: the default on both; an open range
  ##   (`40-`, `-5`) has the default.
  ##
  ## Only a single unit is borrowed (not `2h30m`): which of its units would be meant?
  let sd = sides(s)
  if sd.isNone:
    return none(string)
  let p = sd.get.parts
  var parts = @[p[0].text, p[1].text]
  var filled = false
  func put(parts: var seq[string], k: int, unit: string, filled: var bool) =
    parts[k] = p[k].text & unit
    filled = true

  let bare =
    [p[0].isAmount and p[0].unit.len == 0, p[1].isAmount and p[1].unit.len == 0]
  if sd.get.sep == '~' and p[0].number.len == 0 and p[0].text.len > 0:
    # (a reference: only the spread can lack a unit)
    if bare[1]:
      parts.put(1, default, filled)
  elif bare[0] or bare[1]:
    for k in 0 .. 1:
      if not bare[k]:
        continue
      if p[1 - k].isSingleUnit:
        let u = p[1 - k].unit
        if sd.get.sep == '~' and k == 1:
          # a spread: the centre's unit, or the one below it if the spread's number is larger
          var big = false
          try:
            big = parseFloat(p[1].number) > parseFloat(p[0].number)
          except ValueError:
            discard
          parts.put(k, (if big: below(units, u) else: u), filled)
        else:
          parts.put(k, u, filled)
      elif bare[1 - k] or p[1 - k].text.len == 0:
        parts.put(k, default, filled)
  if filled:
    some(parts.join($sd.get.sep))
  else:
    none(string)

func isBackwards*(s: string, parseEnd: EndParser): bool =
  ## Whether `s` is a range whose ends can be read but whose first end is larger.
  let parts = s.split('-')
  if parts.len != 2 or parts[0].len == 0 or parts[1].len == 0:
    return false
  let lo = parseEnd(parts[0])
  let hi = parseEnd(parts[1])
  lo.isSome and hi.isSome and lo.get > hi.get

func parseRange*(s: string, parseEnd: EndParser): Option[NumRange] =
  ## "a-b", "a-", "-b": the ends are read by `parseEnd`.  None if there is not exactly
  ## one hyphen, an end cannot be read, both are missing, or the range is backwards.
  let parts = s.split('-')
  if parts.len != 2:
    return none(NumRange)
  var r: NumRange
  if parts[0].len > 0:
    r.lo = parseEnd(parts[0])
    if r.lo.isNone:
      return none(NumRange)
  if parts[1].len > 0:
    r.hi = parseEnd(parts[1])
    if r.hi.isNone:
      return none(NumRange)
  if r.isOpen:
    return none(NumRange)
  if r.lo.isSome and r.hi.isSome and r.lo.get > r.hi.get:
    return none(NumRange)
  some(r)

func parseTol*(s: string, parseEnd: EndParser): Option[Tol] =
  ## "2" / "15m" (an amount, read by `parseEnd`) or "10%" (digits and a dot, then %).
  if s.endsWith("%"):
    let digits = s[0 ..< s.len - 1]
    if digits.len == 0 or digits.anyIt(it notin {'0' .. '9', '.'}) or
        digits.count('.') > 1 or digits[0] == '.':
      return none(Tol)
    try:
      return some(Tol(amount: parseFloat(digits), percent: true))
    except ValueError:
      return none(Tol)
  let v = parseEnd(s)
  if v.isSome:
    some(Tol(amount: v.get))
  else:
    none(Tol)

func parseReferent*(s: string): Option[Referent] =
  ## "latest" and "previous" (any case); none for anything else.
  case s.toLowerAscii
  of "latest":
    some(rfLatest)
  of "previous":
    some(rfPrevious)
  else:
    none(Referent)

func parseAround*(s: string, parseEnd: EndParser): Option[Around] =
  ## "42~2", "2h~15m", "latest~10%", "previous~5": exactly one "~", a centre (a value, or
  ## the word `latest` or `previous`) and a tolerance.
  let parts = s.split('~')
  if parts.len != 2:
    return none(Around)
  let t = parseTol(parts[1], parseEnd)
  let referent = parseReferent(parts[0])
  if referent.isSome:
    if t.isNone:
      return none(Around)
    return some(Around(byReference: true, refers: referent.get, tol: t.get))
  let c = parseEnd(parts[0])
  if c.isNone or t.isNone:
    return none(Around)
  some(Around(byReference: false, centre: c.get, tol: t.get))

func around*(centre: float, t: Tol): NumRange =
  ## The range `centre` plus and minus the tolerance (a percentage is of the centre);
  ## it does not go below zero.
  let d =
    if t.percent:
      centre * t.amount / 100.0
    else:
      t.amount
  NumRange(lo: some(max(0.0, centre - d)), hi: some(centre + d))
