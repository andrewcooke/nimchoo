## Ranges typed on the command line: `40-` (40 or more), `10-50`, `-5` (up to 5), and
## "around" ranges `42~2` (40 to 44), `2h~15m`, `latest~10%`, for distances and for active
## times.  Pure.
##
## A distance is in kilometres (`5`, `2.5`, `5km`) or metres (`500m`).  A time is
## written as the program prints it (see ui/interval.nim): `45s`, `22m`, `1h30m`, `2d`,
## units d h m s, largest first, each at most once, with a unit on every number.
## Both ends of a range are inclusive, and either may be left out (not both).

import std/[math, options, sequtils, strutils]

{.push raises: [].}

type
  EndParser* = proc(s: string): Option[float] {.nimcall, noSideEffect, raises: [].}

  Tol* = object
    ## How far from a centre: an amount (metres, seconds) or a percentage of the centre.
    amount*: float
    percent*: bool

  Around* = object
    ## `centre~tolerance`; no centre means `latest` (found when the command runs).
    centre*: Option[float]
    tol*: Tol

  NumRange* = object
    ## Metres or seconds.
    lo*, hi*: Option[float]

func isOpen*(r: NumRange): bool = r.lo.isNone and r.hi.isNone

func parseDistance*(s: string): Option[float] =
  ## "5", "2.5", "5km" -> kilometres; "500m" -> metres.  Result in metres.
  var text = s.strip.toLowerAscii
  var factor = 1000.0
  if text.endsWith("km"):
    text = text[0 ..< text.len - 2]
  elif text.endsWith("m"):
    text = text[0 ..< text.len - 1]
    factor = 1.0
  if text.len == 0 or text[0] notin {'0' .. '9'}: return none(float)
  if text.anyIt(it notin {'0' .. '9', '.'}) or text.count('.') > 1: return none(float)   # (not 1e3)
  try:
    let v = parseFloat(text)
    if v >= 0: some(v * factor) else: none(float)
  except ValueError:
    none(float)

func parseInterval*(s: string): Option[float] =
  ## "1h30m", "45s", "2d03h07m" -> seconds; none if it is not in that notation.
  const units = "dhms"
  const seconds = [86400.0, 3600.0, 60.0, 1.0]
  let text = s.strip.toLowerAscii
  if text.len == 0: return none(float)
  var total = 0.0
  var number = 0                          # the digits read since the last unit
  var count = 0                           # how many digits
  var last = -1                           # the index in `units` of the last unit seen
  for c in text:
    if c in {'0' .. '9'}:
      number = number * 10 + (ord(c) - ord('0'))
      inc count
      if count > 9: return none(float)
    else:
      let u = units.find(c)
      if u < 0 or count == 0 or u <= last: return none(float)
      total += float(number) * seconds[u]
      number = 0
      count = 0
      last = u
  if count > 0: return none(float)        # a number with no unit
  some(total)

func isBackwards*(s: string, parseEnd: EndParser): bool =
  ## Whether `s` is a range whose ends can be read but whose first end is larger.
  let parts = s.split('-')
  if parts.len != 2 or parts[0].len == 0 or parts[1].len == 0: return false
  let lo = parseEnd(parts[0])
  let hi = parseEnd(parts[1])
  lo.isSome and hi.isSome and lo.get > hi.get

func parseRange*(s: string, parseEnd: EndParser): Option[NumRange] =
  ## "a-b", "a-", "-b": the ends are read by `parseEnd`.  None if there is not exactly
  ## one hyphen, an end cannot be read, both are missing, or the range is backwards.
  let parts = s.split('-')
  if parts.len != 2: return none(NumRange)
  var r: NumRange
  if parts[0].len > 0:
    r.lo = parseEnd(parts[0])
    if r.lo.isNone: return none(NumRange)
  if parts[1].len > 0:
    r.hi = parseEnd(parts[1])
    if r.hi.isNone: return none(NumRange)
  if r.isOpen: return none(NumRange)
  if r.lo.isSome and r.hi.isSome and r.lo.get > r.hi.get: return none(NumRange)
  some(r)

func parseTol*(s: string, parseEnd: EndParser): Option[Tol] =
  ## "2" / "15m" (an amount, read by `parseEnd`) or "10%" (digits and a dot, then %).
  if s.endsWith("%"):
    let digits = s[0 ..< s.len - 1]
    if digits.len == 0 or digits.anyIt(it notin {'0' .. '9', '.'}) or digits.count('.') > 1 or
       digits[0] == '.':
      return none(Tol)
    try:
      return some(Tol(amount: parseFloat(digits), percent: true))
    except ValueError:
      return none(Tol)
  let v = parseEnd(s)
  if v.isSome: some(Tol(amount: v.get)) else: none(Tol)

func parseAround*(s: string, parseEnd: EndParser): Option[Around] =
  ## "42~2", "2h~15m", "latest~10%": exactly one "~", a centre (a value, or the word
  ## `latest`) and a tolerance.
  let parts = s.split('~')
  if parts.len != 2: return none(Around)
  var a: Around
  if parts[0].toLowerAscii == "latest":
    a.centre = none(float)
  else:
    let c = parseEnd(parts[0])
    if c.isNone: return none(Around)
    a.centre = c
  let t = parseTol(parts[1], parseEnd)
  if t.isNone: return none(Around)
  a.tol = t.get
  some(a)

func around*(centre: float, t: Tol): NumRange =
  ## The range `centre` plus and minus the tolerance (a percentage is of the centre);
  ## it does not go below zero.
  let d = if t.percent: centre * t.amount / 100.0 else: t.amount
  NumRange(lo: some(max(0.0, centre - d)), hi: some(centre + d))
