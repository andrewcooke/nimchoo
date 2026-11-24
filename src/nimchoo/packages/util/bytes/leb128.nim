## Whole numbers in as few bytes as they need: LEB128 (as WebAssembly, DWARF and protobuf's varints have it).  Each byte holds
## seven bits of the number, the lowest first; its top bit is set when another byte follows.  0 to 127 is one byte, up to
## 16,383 two, up to about two million three.  A signed number is first zigzagged (0, -1, 1, -2, 2 ... become 0, 1, 2, 3,
## 4 ...), so that a small one is small either way.  Pure.

import std/options

{.push raises: [].}

func putUleb*(s: var string, v: uint64) =
  ## Append `v`.
  var v = v
  while v >= 0x80'u64:
    s.add char((v and 0x7F) or 0x80)
    v = v shr 7
  s.add char(v)

func getUleb*(s: string, pos: var int): Option[uint64] =
  ## The number at `pos`, which is moved past it; none if the bytes end inside it or it is longer than a 64-bit number
  ## can be (the bytes are not LEB128 then).
  var
    v = 0'u64
    shift = 0
  while pos < s.len:
    let b = uint64(ord(s[pos]))
    inc pos
    if shift == 63 and b > 1:
      return none(uint64)
    v = v or ((b and 0x7F) shl shift)
    if b < 0x80:
      return some(v)
    shift += 7
    if shift > 63:
      return none(uint64)
  none(uint64)

func zigzag*(v: int64): uint64 =
  ## A signed number as an unsigned one, small for small either way.
  (cast[uint64](v) shl 1) xor cast[uint64](v shr 63)

func unzigzag*(u: uint64): int64 =
  ## The signed number `zigzag` made.
  cast[int64](u shr 1) xor -cast[int64](u and 1)
