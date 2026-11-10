## Damage for zip files, for the fuzzers (tests/util/zip/test_fuzz.nim, tests/util/xlsx/test_fuzz.nim): blind changes, and
## changes to the numbers that a zip reader trusts, in the local headers, the central directory and the end record.

import std/[random, strutils]
import ./textmutate

const sizes = [
  0, 1, 2, 3, 0x7f, 0x80, 0xff, 0x100, 0x7fff, 0x8000, 0xffff, 0x10000, 0x7fffffff,
  0x80000000, 0xfffffffe, 0xffffffff,
]

type Field = tuple[offset, width: int] ## in a record that starts at its signature

const
  endRecord = [
    (10, 2), # entries in the directory
    (12, 4), # size of the directory
    (16, 4), # where the directory starts
    (20, 2), # length of the comment
  ]
  central = [
    (10, 2), # compression
    (16, 4), # crc
    (20, 4), # compressed size
    (24, 4), # size
    (28, 2), # length of the name
    (30, 2), # length of the extra field
    (32, 2), # length of the comment
    (42, 4), # where the local header is
  ]
  local = [
    (8, 2), # compression
    (18, 4), # compressed size
    (22, 4), # size
    (26, 2), # length of the name
    (28, 2), # length of the extra field
  ]

proc putLe(s: var string, at, width: int, v: int) =
  for i in 0 ..< width:
    if at + i < s.len:
      s[at + i] = char((v shr (8 * i)) and 0xff)

proc signatures(s: string, sig: string): seq[int] =
  var i = s.find(sig)
  while i >= 0:
    result.add i
    i = s.find(sig, i + 1)

proc damageZip*(r: var Rand, z: string): string =
  ## One to three changes of a zip file held in a string.
  result = z
  for _ in 0 ..< r.rand(1 .. 3):
    if r.rand(2) == 0:
      result = r.blindDamage(result)
      continue
    let (sig, fields) =
      case r.rand(2)
      of 0:
        ("PK\5\6", @endRecord)
      of 1:
        ("PK\1\2", @central)
      else:
        ("PK\3\4", @local)
    let at = result.signatures(sig)
    if at.len == 0:
      result = r.blindDamage(result)
      continue
    let (offset, width) = r.sample(fields)
    let place = r.sample(at) + offset
    let current = block:
      var v = 0
      for i in 0 ..< width:
        if place + i < result.len:
          v += ord(result[place + i]) shl (8 * i)
      v
    result.putLe(
      place,
      width,
      case r.rand(3)
      of 0:
        r.sample(sizes)
      of 1:
        current + 1
      of 2:
        max(0, current - 1)
      else:
        current * 2,
    )
