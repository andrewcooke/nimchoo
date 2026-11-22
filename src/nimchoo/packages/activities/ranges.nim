## Ranges typed on the command line: `40-` (40 or more), `10-50`, `-5` (up to 5), and
## "around" ranges `42~2` (40 to 44), `2h~15m`, `latest~10%`, for distances and for active
## times.  Pure.
##
## An end has its unit, read by the shared readers (`ui/units`): a distance `40km` or `500m`, a time as the program prints it
## (see packages/ui/interval.nim): `45s`, `22m`, `1h30m`, `2d`.  **A unit needs to be given only once** in a range, on either
## side (`sharedUnit`): `42~2km`, `10km-50`; with none anywhere, the command asks (`addDefaultUnit`).
## Both ends of a range are inclusive, and either may be left out (not both).

import std/[math, options, sequtils, strutils]
import ../ui/units

{.push raises: [].}

type
  Reference* = enum
    ## An activity a criterion is measured against, found when the command runs: the
    ## newest of those that meet the other criteria, or the one that was selected before.
    refNone
    refLatest
    refPrevious

  EndParser* = proc(s: string): Option[float] {.nimcall, noSideEffect, raises: [].}

  Tol* = object
    ## How far from a centre: an amount (metres, seconds) or a percentage of the centre.
    amount*: float
    percent*: bool

  Around* = object
    ## `centre~tolerance`; the centre is a value, or (`refers` is not refNone) an activity
    ## found when the command runs.
    centre*: Option[float]
    refers*: Reference
    tol*: Tol

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

func sharedUnit*(s: string): string =
  ## A unit needs to be given only once in a range: `42~2km`, `42km~2` and `42km~2000m` are the same, and so are `10-50km`,
  ## `10km-50` and `10km-50km`.  The side with no unit takes that of the other if it is a single one (`km`, `m`, `h`: not
  ## `2h30m`, which would not say which of its units is meant).  Anything else is left as it was, for the reader to refuse.
  let sd = sides(s)
  if sd.isNone:
    return s
  let p = sd.get.parts
  var parts = @[p[0].text, p[1].text]
  for k in 0 .. 1:
    if p[k].isAmount and p[k].unit.len == 0 and p[1 - k].isSingleUnit:
      parts[k] = p[k].text & p[1 - k].unit
  parts.join($sd.get.sep)

func addDefaultUnit*(s: string, unit: string): Option[string] =
  ## When no number of a range or an `around` has a unit (`40-`, `10-50`, `42~2`, `latest~5`), the text with `unit` added to
  ## the first number (`40km-`: a unit given once is enough); none if some number has a unit or there is no number to
  ## add it to (the text is then for the reader to accept or refuse).
  let sd = sides(s)
  if sd.isNone:
    return none(string)
  let p = sd.get.parts
  var first = -1
  for k in 0 .. 1:
    if p[k].isAmount:
      if p[k].unit.len > 0:
        return none(string)
      if first < 0:
        first = k
  if first < 0:
    return none(string)
  var parts = @[p[0].text, p[1].text]
  parts[first] = parts[first] & unit
  some(parts.join($sd.get.sep))

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

func parseReference*(s: string): Reference =
  ## "latest" and "previous" (any case); refNone for anything else.
  case s.toLowerAscii
  of "latest": refLatest
  of "previous": refPrevious
  else: refNone

func parseAround*(s: string, parseEnd: EndParser): Option[Around] =
  ## "42~2", "2h~15m", "latest~10%", "previous~5": exactly one "~", a centre (a value, or
  ## the word `latest` or `previous`) and a tolerance.
  let parts = s.split('~')
  if parts.len != 2:
    return none(Around)
  var a: Around
  a.refers = parseReference(parts[0])
  if a.refers != refNone:
    a.centre = none(float)
  else:
    let c = parseEnd(parts[0])
    if c.isNone:
      return none(Around)
    a.centre = c
  let t = parseTol(parts[1], parseEnd)
  if t.isNone:
    return none(Around)
  a.tol = t.get
  some(a)

func around*(centre: float, t: Tol): NumRange =
  ## The range `centre` plus and minus the tolerance (a percentage is of the centre);
  ## it does not go below zero.
  let d =
    if t.percent:
      centre * t.amount / 100.0
    else:
      t.amount
  NumRange(lo: some(max(0.0, centre - d)), hi: some(centre + d))
