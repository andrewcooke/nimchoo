## How a climb is shown by name.  Names need not be unique: climbs that share a name (without regard to case) are shown
## with their number as a subscript, "Farellones₃", and only when the name is shared.  The number is kept with the climb
## (`sector.name_n`, given when the climb gets its name: the next one among those with that name) and never changes, so
## "Farellones₃" is always the same climb.  A climb with no name is "unnamed".  What a person types is "Farellones₃" or
## "Farellones 3" or "Farellones3" (`ordinalForms`).

import std/[options, sequtils, strutils, tables, unicode]
import ../text/fold/fold

{.push raises: [].}

const
  unnamed* = "unnamed"
  subscriptDigits =
    ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]

type Shown* = object
  id*: int64
  name*: string ## "" if it has none
  n*: int ## its number among the climbs with that name

func baseName(name: string): string =
  if name.strip.len == 0: unnamed else: name.strip

func groupKey*(name: string): string =
  ## What climbs of one name share (case and accents folded, "unnamed" for none): the key of their numbering.
  foldText(baseName(name))

func subscriptNumber*(n: int): string =
  ## 12 -> "₁₂".
  for c in $n:
    result.add subscriptDigits[ord(c) - ord('0')]

func endsWithSubscript*(s: string): bool =
  ## Whether the text ends in a subscript digit (the program adds those; a name given by a person may not).
  if s.len == 0:
    return false
  var last = Rune(0)
  for r in s.runes:
    last = r
  int(last) in 0x2080 .. 0x2089

func withoutSubscript*(s: string): string =
  ## "Morro La Cabra₁₂" -> "Morro La Cabra".
  var rs: seq[Rune]
  for r in s.runes:
    rs.add r
  var k = rs.len
  while k > 0 and int(rs[k - 1]) in 0x2080 .. 0x2089:
    dec k
  $rs[0 ..< k]

func displayNames*(climbs: openArray[Shown]): seq[string] =
  ## One text per climb, in the order given.
  var sizes = initCountTable[string]()
  for c in climbs:
    sizes.inc groupKey(c.name)
  result = newSeq[string](climbs.len)
  for i, c in climbs:
    let base = baseName(c.name)
    result[i] =
      if sizes[groupKey(c.name)] > 1:
        base & subscriptNumber(c.n)
      else:
        base

func climbNumber*(text: string): Option[int64] =
  ## A climb's number, if the text is a whole number and nothing else (`--names 62`): used when no climb's name holds it.
  let t = text.strip
  if t.len > 0 and t.len < 18 and t.allIt(it in {'0' .. '9'}):
    try:
      return some(parseBiggestInt(t))
    except ValueError:
      discard
  none(int64)

func ordinalForms*(text: string): seq[string] =
  ## The ways to read what a person typed: as it is, and, if it ends in a number ("Farellones 3", "Farellones3"), with
  ## that number as a subscript ("Farellones₃").  (Both, because a name can really end in a number: "Ruta 60".)
  let t = text.strip
  result = @[t]
  var i = t.len
  while i > 0 and t[i - 1] in {'0' .. '9'}:
    dec i
  if i < t.len and i > 0:
    let stem = t[0 ..< i].strip(leading = false)
    if stem.len > 0:
      try:
        result.add stem & subscriptNumber(parseInt(t[i .. ^1]))
      except ValueError:
        discard
