## Damage for text and for bytes in general, for the fuzzers of the readers of xml and zip (tests/util/*/test_fuzz.nim):
## blind changes of bytes and lengths, and changes that know what XML is made of (numbers, tags, entities, quotes).

import std/[random, strutils]

const
  limits = [
    "0", "-1", "1", "2", "255", "256", "65535", "65536", "2147483647", "2147483648",
    "4294967295", "4294967296", "9223372036854775807", "9223372036854775808",
    "99999999999999999999",
  ]
  xmlBits = [
    "<", ">", "</", "/>", "&", "&amp;", "\"", "'", "=", " ", "<!--", "]]>", "<![CDATA["
  ]
  entities =
    ["&#0;", "&#x110000;", "&#99999999999;", "&#x;", "&bogus;", "&amp", "&#xD800;"]

proc blindDamage*(r: var Rand, s: string): string =
  ## One change of bytes: flipped, set, cut short, a piece removed, repeated, moved or rotated.
  result = s
  if result.len == 0:
    return
  let at = r.rand(result.high)
  case r.rand(7)
  of 0:
    result[at] = char(ord(result[at]) xor (1 shl r.rand(7)))
  of 1:
    result[at] = char(r.rand(255))
  of 2:
    result.setLen(at)
  of 3:
    result.delete(at .. min(result.high, at + r.rand(0 .. 30)))
  of 4:
    let b = min(result.high, at + r.rand(0 .. 40))
    result.insert(result[at .. b], r.rand(result.len))
  of 5:
    let b = min(result.high, at + r.rand(1 .. 60))
    let piece = result[at .. b]
    result.delete(at .. b)
    result.insert(piece, r.rand(result.len))
  else:
    let b = min(result.high, at + r.rand(1 .. 60))
    let len = b - at + 1
    if len > 1:
      let k = r.rand(1 .. len - 1)
      let original = result
      for i in 0 ..< len:
        result[at + (i + k) mod len] = original[at + i]

proc numberAt(s: string, from0: int): Slice[int] =
  ## The first run of digits at or after `from0` (empty slice, 1 .. 0, if none).
  var i = from0
  while i < s.len and s[i] notin Digits:
    inc i
  if i >= s.len:
    return 1 .. 0
  var j = i
  while j + 1 < s.len and s[j + 1] in Digits:
    inc j
  i .. j

proc damageText*(r: var Rand, s: string): string =
  ## One to three changes of a piece of XML (or any text): half of them blind, the rest changes of a number, an
  ## entity, a piece of markup or a quoted value.
  result = s
  for _ in 0 ..< r.rand(1 .. 3):
    if result.len == 0:
      break
    let at = r.rand(result.high)
    case r.rand(5)
    of 0, 1:
      result = r.blindDamage(result)
    of 2:
      # a number becomes a limit value (indexes, sizes, references: "A1" has one too)
      let n = result.numberAt(at)
      if n.len > 0:
        result[n] = r.sample(limits)
      else:
        result = r.blindDamage(result)
    of 3: # markup or an entity where there was none
      result.insert(
        if r.rand(1) == 0:
          r.sample(xmlBits)
        else:
          r.sample(entities),
        at,
      )
    of 4:
      # the contents of a quoted value are replaced by another quoted value, or by nothing
      let q = result.find('"', at)
      let q2 =
        if q < 0:
          -1
        else:
          result.find('"', q + 1)
      if q >= 0 and q2 > q:
        result[q + 1 ..< q2] =
          if r.rand(2) == 0:
            ""
          else:
            r.sample(limits)
      else:
        result = r.blindDamage(result)
    else: # a letter of a name changes (a tag, an attribute, a column)
      var i = at
      while i < result.len and result[i] notin Letters:
        inc i
      if i < result.len:
        result[i] = r.sample("ABZaz_:")
