import std/[options, unittest]
import nimchoo/packages/fit/basetype
import ../support/fitbuilder

func ints(bt: BaseType, data: seq[byte], e = littleEndian): seq[int64] =
  ## The elements of an integer field.
  for i in 0 ..< data.len div bt.size:
    result.add readInt(bt, data, i, e)

func floats(bt: BaseType, data: seq[byte], e: Endianness): seq[float] =
  for i in 0 ..< data.len div bt.size:
    result.add readFloat(bt, data, i, e)

suite "base type byte":
  test "known":
    check baseTypeFromByte(0x84).get == btUint16
    check baseTypeFromByte(0x07).get == btString
    check baseTypeFromByte(0x00).get == btEnum
    check baseTypeFromByte(0x10).get == btUint64z
  test "unknown":
    check baseTypeFromByte(0x1f).isNone
    check baseTypeFromByte(0x11).isNone

suite "integers":
  test "unsigned, both endians":
    check ints(btUint16, b(0x34, 0x12)) == @[0x1234'i64]
    check ints(btUint16, b(0x12, 0x34), bigEndian) == @[0x1234'i64]
    check ints(btUint32, b(1, 2, 3, 4)) == @[0x04030201'i64]
    check ints(btUint32, b(1, 2, 3, 4), bigEndian) == @[0x01020304'i64]
    check ints(btUint64, b(1, 0, 0, 0, 0, 0, 0, 0)) == @[1'i64]
    check ints(btUint8, b(200)) == @[200'i64]
  test "signed":
    check ints(btSint8, b(0x80)) == @[-128'i64]
    check ints(btSint8, b(0xfe)) == @[-2'i64]
    check ints(btSint16, b(0x00, 0x80)) == @[-32768'i64]
    check ints(btSint16, b(0x80, 0x00), bigEndian) == @[-32768'i64]
    check ints(btSint32, b(0xff, 0xff, 0xff, 0xff)) == @[-1'i64]
    check ints(btSint64, b(0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff)) == @[-1'i64]
  test "arrays":
    check ints(btUint8, b(1, 2, 3)) == @[1'i64, 2, 3]
    check ints(btUint16, b(1, 0, 2, 0)) == @[1'i64, 2]
    check ints(btUint16, b(1, 0, 2, 0, 9)) == @[1'i64, 2] # trailing partial
  test "enum and byte":
    check ints(btEnum, b(5)) == @[5'i64]
    check ints(btByte, b(7)) == @[7'i64]

suite "bad values":
  test "single bad values":
    check isBad(btUint8, b(0xff), littleEndian)
    check isBad(btEnum, b(0xff), littleEndian)
    check isBad(btByte, b(0xff), littleEndian)
    check isBad(btSint8, b(0x7f), littleEndian)
    check isBad(btUint16, b(0xff, 0xff), bigEndian)
    check isBad(btSint16, b(0xff, 0x7f), littleEndian)
    check isBad(btSint16, b(0x7f, 0xff), bigEndian)
    check isBad(btUint32, b(0xff, 0xff, 0xff, 0xff), littleEndian)
    check isBad(btSint32, b(0xff, 0xff, 0xff, 0x7f), littleEndian)
    check isBad(
      btUint64, b(0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff), littleEndian
    )
  test "zero is bad for z types only":
    check isBad(btUint8z, b(0), littleEndian)
    check isBad(btUint16z, b(0, 0), littleEndian)
    check isBad(btUint32z, b(0, 0, 0, 0), bigEndian)
    check not isBad(btUint8, b(0), littleEndian)
    check ints(btUint8z, b(1)) == @[1'i64]
  test "neighbours of the marker are fine":
    check ints(btSint8, b(0x80)) == @[-128'i64]
    check ints(btUint8, b(0xfe)) == @[254'i64]
  test "arrays: all bad is none, isolated bad stays raw":
    check isBad(btUint8, b(0xff, 0xff), littleEndian)
    check ints(btUint8, b(1, 0xff, 3)) == @[1'i64, 255, 3]
    check isBad(btUint8, b(0xff, 0xff), littleEndian)
    check not isBad(btUint8, b(1, 0xff), littleEndian)
  test "empty is bad, except strings":
    check isBad(btUint8, newSeq[byte](), littleEndian)
    check not isBad(btString, b(0xff), littleEndian)

suite "floats":
  test "float32":
    # 1.5 = 0x3fc00000
    check floats(btFloat32, b(0, 0, 0xc0, 0x3f), littleEndian) == @[1.5]
    check floats(btFloat32, b(0x3f, 0xc0, 0, 0), bigEndian) == @[1.5]
  test "float64":
    check floats(btFloat64, b(0, 0, 0, 0, 0, 0, 0xf8, 0x3f), littleEndian) == @[1.5]
    check floats(btFloat64, b(0x3f, 0xf8, 0, 0, 0, 0, 0, 0), bigEndian) == @[1.5]
  test "all ones is bad":
    check isBad(btFloat32, b(0xff, 0xff, 0xff, 0xff), littleEndian)
    check isBad(btFloat64, b(0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff), bigEndian)

suite "floats that are not finite":
  # judged from the bits, so that a NaN never meets arithmetic
  test "float32: the marker, other NaNs and infinities are told apart from numbers":
    check elementKind(btFloat32, b(0, 0, 0xc0, 0x3f), 0, littleEndian) == ekValue
    check elementKind(btFloat32, b(0, 0, 0, 0), 0, littleEndian) == ekValue
    check elementKind(btFloat32, b(1, 0, 0, 0), 0, littleEndian) == ekValue # subnormal
    check elementKind(btFloat32, b(0xff, 0xff, 0xff, 0xff), 0, littleEndian) == ekBad
    check elementKind(btFloat32, b(0, 0, 0xc0, 0x7f), 0, littleEndian) == ekNonFinite
      # quiet NaN
    check elementKind(btFloat32, b(1, 0, 0x80, 0x7f), 0, littleEndian) == ekNonFinite
      # signalling NaN
    check elementKind(btFloat32, b(0, 0, 0x80, 0x7f), 0, littleEndian) == ekNonFinite
      # +inf
    check elementKind(btFloat32, b(0, 0, 0x80, 0xff), 0, littleEndian) == ekNonFinite
      # -inf
    check elementKind(btFloat32, b(0x7f, 0x80, 0, 0), 0, bigEndian) == ekNonFinite
  test "float64":
    check elementKind(btFloat64, b(0, 0, 0, 0, 0, 0, 0xf8, 0x3f), 0, littleEndian) ==
      ekValue
    check elementKind(btFloat64, b(1, 0, 0, 0, 0, 0, 0xf0, 0x7f), 0, littleEndian) ==
      ekNonFinite
    check elementKind(btFloat64, b(0, 0, 0, 0, 0, 0, 0xf0, 0x7f), 0, littleEndian) ==
      ekNonFinite
    check elementKind(
      btFloat64, b(0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff), 0, bigEndian
    ) == ekBad
  test "the element asked for":
    check elementKind(btFloat32, b(0, 0, 0xc0, 0x3f, 0, 0, 0x80, 0x7f), 1, littleEndian) ==
      ekNonFinite

suite "strings":
  func strs(data: seq[byte]): seq[string] =
    decodeString(data)
  test "trailing nuls stripped":
    check strs(b(ord('a'), ord('b'), ord('c'), 0, 0)) == @["abc"]
  test "embedded nuls split":
    check strs(b(ord('a'), 0, ord('b'))) == @["a", "b"]
  test "utf8":
    check strs(b(0xc3, 0xa9, 0)) == @["é"]
  test "invalid utf8 falls back to mod 0x7f":
    check strs(b(ord('a'), 0xff, 0)) == @["a\x01"]
  test "empty":
    check strs(b(0, 0)) == @[""]

suite "every base type, from its table of facts":
  func bytesOf(v: uint64, size: int, e: Endianness): seq[byte] =
    for i in 0 ..< size:
      let shift =
        if e == littleEndian:
          8 * i
        else:
          8 * (size - 1 - i)
      result.add byte((v shr shift) and 0xff)

  test "the marker is bad, in both byte orders, and is the only bad value of its size":
    for bt in BaseType:
      if bt == btString:
        continue
      for e in [littleEndian, bigEndian]:
        let marker = bytesOf(invalid(bt), bt.size, e)
        check isBad(bt, marker, e)
        check bt.elementKind(marker, 0, e) == ekBad
        # a neighbour of the marker is a value (floats: some value; z types: 1 is not their marker)
        let other = bytesOf(if invalid(bt) == 1: 2 else: 1, bt.size, e)
        check not isBad(bt, other, e)
        check bt.elementKind(other, 0, e) == ekValue
  test "a marker among values: only that element is bad":
    for bt in BaseType:
      if bt in {btString, btFloat32, btFloat64}:
        continue
      let data =
        bytesOf(1, bt.size, littleEndian) & bytesOf(invalid(bt), bt.size, littleEndian)
      check not isBad(bt, data, littleEndian)
      check bt.elementKind(data, 0, littleEndian) == ekValue
      check bt.elementKind(data, 1, littleEndian) == ekBad
  test "names and bytes find the same types":
    for bt in BaseType:
      check baseTypeFromName($bt) == some(bt)
      check baseTypeFromByte(byte(ord(bt))) == some(bt)
    check baseTypeFromName("uint9").isNone and baseTypeFromName("").isNone
