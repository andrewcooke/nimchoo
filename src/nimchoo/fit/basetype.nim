## The FIT base types (what a field's bytes are: uint16, string, ...), their
## "bad value" markers, and decoding values of a base type from bytes.
##
## Conventions: `Option` for values that are legitimately absent (a bad
## value, an unknown base type number).

import std/[options, strutils, unicode]
import ./bytes

{.push raises: [].}

type
  BaseType* = enum
    ## Order follows the FIT base type numbers.
    btEnum = "enum", btSint8 = "sint8", btUint8 = "uint8",
    btSint16 = "sint16", btUint16 = "uint16",
    btSint32 = "sint32", btUint32 = "uint32",
    btString = "string", btFloat32 = "float32", btFloat64 = "float64",
    btUint8z = "uint8z", btUint16z = "uint16z", btUint32z = "uint32z",
    btByte = "byte", btSint64 = "sint64", btUint64 = "uint64",
    btUint64z = "uint64z"

  RawKind* = enum rkInt, rkFloat, rkString

  RawValues* = object
    ## Unscaled, unmapped values read from a field.
    case kind*: RawKind
    of rkInt: ints*: seq[int64]  ## uint64 values above int64.high are bit-cast
    of rkFloat: floats*: seq[float]
    of rkString: strings*: seq[string]

func size*(bt: BaseType): int {.raises: [].} =
  ## Bytes per element (strings and bytes count as 1).
  case bt
  of btEnum, btSint8, btUint8, btString, btUint8z, btByte: 1
  of btSint16, btUint16, btUint16z: 2
  of btSint32, btUint32, btFloat32, btUint32z: 4
  of btFloat64, btSint64, btUint64, btUint64z: 8

func isSigned*(bt: BaseType): bool {.raises: [].} =
  bt in {btSint8, btSint16, btSint32, btSint64}

func baseTypeOf*(b: byte): Option[BaseType] {.raises: [].} =
  ## Base type from the byte in a definition message: low 5 bits are the
  ## number; bit 7 (endian ability) is ignored.
  let n = int(b and 0x1f)
  if n <= ord(high(BaseType)): some(BaseType(n)) else: none(BaseType)

func invalid*(bt: BaseType): uint64 {.raises: [].} =
  ## The "bad value" marker, as the raw unsigned value.
  let bits = 8 * bt.size
  let ones = if bits == 64: high(uint64) else: (1'u64 shl bits) - 1
  case bt
  of btUint8z, btUint16z, btUint32z, btUint64z: 0'u64
  of btSint8, btSint16, btSint32, btSint64: ones shr 1
  else: ones  # unsigned, enum, byte, floats (all bits set)

func isBad*(bt: BaseType, data: openArray[byte],
            endian: Endianness): bool {.raises: [].} =
  ## True if every element is the bad marker (or there are none).  Strings
  ## are never bad.
  if bt == btString: return false
  let sz = bt.size
  let marker = invalid(bt)
  let n = data.len div sz
  if n == 0: return true
  for i in 0 ..< n:
    if getUint(data, i * sz, sz, endian) != marker:
      return false
  true

func splitStrings(s: string): seq[string] {.raises: [].} =
  var s = s
  while s.len > 0 and s[^1] == '\0': s.setLen(s.len - 1)
  s.split('\0')

func decodeString*(data: openArray[byte]): seq[string] {.raises: [].} =
  var s = newString(data.len)
  for i, b in data: s[i] = char(b)
  if validateUtf8(s) == -1:
    splitStrings(s)
  else:
    # close to what the Garmin CSV generates (as in choochoo)
    for i, b in data: s[i] = char(b mod 0x7f)
    splitStrings(s)

func readInt*(bt: BaseType, data: openArray[byte], i: int, endian: Endianness): int64 {.raises: [].} =
  ## Element `i` of `data` as an integer (a uint64 above int64.high is bit-cast).
  let sz = bt.size
  if bt.isSigned: getInt(data, i * sz, sz, endian)
  else: cast[int64](getUint(data, i * sz, sz, endian))

func readFloat*(bt: BaseType, data: openArray[byte], i: int, endian: Endianness): float {.raises: [].} =
  ## Element `i` of `data` as a float (for the float base types).
  let sz = bt.size
  let u = getUint(data, i * sz, sz, endian)
  if sz == 4: float(cast[float32](uint32(u))) else: cast[float64](u)

func decode*(bt: BaseType, data: openArray[byte], endian: Endianness,
             checkBad = true): Option[RawValues] {.raises: [].} =
  ## All elements in `data`.  None if every element is bad (unless `checkBad`
  ## is false).  Isolated bad elements in an array are returned raw (as the SDK
  ## CSV does).
  if bt == btString:
    return some(RawValues(kind: rkString, strings: decodeString(data)))
  if checkBad and isBad(bt, data, endian): return none(RawValues)
  let sz = bt.size
  let n = data.len div sz
  case bt
  of btFloat32, btFloat64:
    var xs = newSeq[float](n)
    for i in 0 ..< n:
      let u = getUint(data, i * sz, sz, endian)
      xs[i] = if sz == 4: float(cast[float32](uint32(u))) else: cast[float64](u)
    some(RawValues(kind: rkFloat, floats: xs))
  else:
    var xs = newSeq[int64](n)
    let signed = bt.isSigned
    for i in 0 ..< n:
      xs[i] = if signed: getInt(data, i * sz, sz, endian)
              else: cast[int64](getUint(data, i * sz, sz, endian))
    some(RawValues(kind: rkInt, ints: xs))
