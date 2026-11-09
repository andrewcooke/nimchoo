## The FIT base types (what a field's bytes are: uint16, string, ...), their
## "bad value" markers, and decoding values of a base type from bytes.
##
## Conventions: `Option` for values that are legitimately absent (a bad
## value, an unknown base type number).

import std/[options, strutils, unicode]
import ../packages/util/bytes/bytes

{.push raises: [].}

type BaseType* = enum
  ## Order follows the FIT base type numbers.
  btEnum = "enum"
  btSint8 = "sint8"
  btUint8 = "uint8"
  btSint16 = "sint16"
  btUint16 = "uint16"
  btSint32 = "sint32"
  btUint32 = "uint32"
  btString = "string"
  btFloat32 = "float32"
  btFloat64 = "float64"
  btUint8z = "uint8z"
  btUint16z = "uint16z"
  btUint32z = "uint32z"
  btByte = "byte"
  btSint64 = "sint64"
  btUint64 = "uint64"
  btUint64z = "uint64z"

type
  NumberKind = enum
    nkUnsigned
    nkSigned
    nkFloat
    nkText

  Facts = object
    ## Everything fixed about a base type.  The only place these are written.
    size: int ## bytes per element (a string's and a byte's count as 1)
    number: NumberKind
    marker: uint64
      ## the "bad value" marker, as the raw unsigned value (unused for text, which has none)

func allOnes(size: int): uint64 =
  ## All bits of an element of `size` bytes set.
  if size >= 8:
    high(uint64)
  else:
    (1'u64 shl (8 * size)) - 1

func unsigned(size: int): Facts =
  Facts(size: size, number: nkUnsigned, marker: allOnes(size))

func signed(size: int): Facts =
  Facts(size: size, number: nkSigned, marker: allOnes(size) shr 1)

func zeroBad(size: int): Facts =
  Facts(size: size, number: nkUnsigned, marker: 0)

func real(size: int): Facts =
  Facts(size: size, number: nkFloat, marker: allOnes(size))

const facts: array[BaseType, Facts] = [
  btEnum: unsigned(1),
  btSint8: signed(1),
  btUint8: unsigned(1),
  btSint16: signed(2),
  btUint16: unsigned(2),
  btSint32: signed(4),
  btUint32: unsigned(4),
  btString: Facts(size: 1, number: nkText),
  btFloat32: real(4),
  btFloat64: real(8),
  btUint8z: zeroBad(1),
  btUint16z: zeroBad(2),
  btUint32z: zeroBad(4),
  btByte: unsigned(1),
  btSint64: signed(8),
  btUint64: unsigned(8),
  btUint64z: zeroBad(8),
]

func size*(bt: BaseType): int {.raises: [].} =
  ## Bytes per element (strings and bytes count as 1).
  facts[bt].size

func isSigned*(bt: BaseType): bool {.raises: [].} =
  ## Whether the type holds signed whole numbers.
  facts[bt].number == nkSigned

func invalid*(bt: BaseType): uint64 {.raises: [].} =
  ## The "bad value" marker, as the raw unsigned value.
  facts[bt].marker

func baseTypeFromByte*(b: byte): Option[BaseType] {.raises: [].} =
  ## Base type from the byte in a definition message: low 5 bits are the
  ## number; bit 7 (endian ability) is ignored.
  let n = int(b and 0x1f)
  if n <= ord(high(BaseType)):
    some(BaseType(n))
  else:
    none(BaseType)

func baseTypeFromName*(name: string): Option[BaseType] {.raises: [].} =
  ## Base type from its name in the profile ("uint16").
  for b in BaseType:
    if $b == name:
      return some(b)

type ElementKind* = enum
  ekValue ## an ordinary value
  ekBad ## the type's "bad value" marker: the file says "no value"
  ekNonFinite
    ## a float that is a NaN other than the marker, or an infinity: not a measurement

func elementKind*(
    bt: BaseType, data: openArray[byte], i: int, endian: Endianness
): ElementKind {.raises: [].} =
  ## What element `i` is, from its bits alone.  Every type is asked this before its value is interpreted (a bool or a
  ## scaled number alike), so that no type reads the marker as a value.  (A NaN must not meet float arithmetic: a
  ## signalling one raises an exception with checks on, and quietly spreads with them off.)  Text has no marker.
  if facts[bt].number == nkText:
    return ekValue
  let sz = bt.size
  let u = getUint(data, i * sz, sz, endian)
  if u == facts[bt].marker:
    return ekBad
  if facts[bt].number == nkFloat:
    let exponentOnes =
      if sz == 4:
        ((u shr 23) and 0xff) == 0xff
      else:
        ((u shr 52) and 0x7ff) == 0x7ff
    if exponentOnes:
      return ekNonFinite
  ekValue

func isBad*(
    bt: BaseType, data: openArray[byte], endian: Endianness
): bool {.raises: [].} =
  ## True if every element is the bad marker (or there are none).  Strings
  ## are never bad.
  if bt == btString:
    return false
  let n = data.len div bt.size
  if n == 0:
    return true
  for i in 0 ..< n:
    if bt.elementKind(data, i, endian) != ekBad:
      return false
  true

func splitStrings(s: string): seq[string] {.raises: [].} =
  var s = s
  while s.len > 0 and s[^1] == '\0':
    s.setLen(s.len - 1)
  s.split('\0')

func decodeString*(data: openArray[byte]): seq[string] {.raises: [].} =
  ## The strings in a field of text (zero-terminated; several if it holds several).  Text that is not UTF-8 is made 7-bit,
  ## as the Garmin CSV does.
  var s = newString(data.len)
  for i, b in data:
    s[i] = char(b)
  if validateUtf8(s) == -1:
    splitStrings(s)
  else:
    # close to what the Garmin CSV generates (as in choochoo)
    for i, b in data:
      s[i] = char(b mod 0x7f)
    splitStrings(s)

func readInt*(
    bt: BaseType, data: openArray[byte], i: int, endian: Endianness
): int64 {.raises: [].} =
  ## Element `i` of `data` as an integer (a uint64 above int64.high is bit-cast).
  let sz = bt.size
  if bt.isSigned:
    getInt(data, i * sz, sz, endian)
  else:
    cast[int64](getUint(data, i * sz, sz, endian))

func readFloat*(
    bt: BaseType, data: openArray[byte], i: int, endian: Endianness
): float {.raises: [].} =
  ## Element `i` of `data` as a float.  Only for elements that `elementKind` says
  ## are finite.
  let sz = bt.size
  let u = getUint(data, i * sz, sz, endian)
  if sz == 4:
    float(cast[float32](uint32(u)))
  else:
    cast[float64](u)
