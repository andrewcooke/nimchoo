import std/unittest
import nimchoo/fit/bytes
import ../support/fitbuilder

suite "byte primitives":
  test "canRead":
    let d = b(1, 2, 3, 4)
    check d.canRead(0, 4)
    check d.canRead(3, 1)
    check d.canRead(4, 0)
    check not d.canRead(3, 2)
    check not d.canRead(-1, 1)
    check not d.canRead(0, -1)
    check not d.canRead(5, 0)

  test "getUint at an offset, both endians":
    let d = b(9, 0x12, 0x34, 0x56, 0x78)
    check d.getUint(1, 2) == 0x3412'u64
    check d.getUint(1, 2, bigEndian) == 0x1234'u64
    check d.getUint(1, 4) == 0x78563412'u64
    check d.getUint(1, 4, bigEndian) == 0x12345678'u64
    check d.getUint(0, 1) == 9'u64
    check d.getUint(2, 0) == 0'u64

  test "getUint of eight bytes":
    let d = b(1, 0, 0, 0, 0, 0, 0, 0x80)
    check d.getUint(0, 8) == 0x8000000000000001'u64
    check d.getUint(0, 8, bigEndian) == 0x0100000000000080'u64

  test "getInt sign-extends":
    check b(0xff).getInt(0, 1) == -1
    check b(0x80).getInt(0, 1) == -128
    check b(0x7f).getInt(0, 1) == 127
    check b(0x00, 0x80).getInt(0, 2) == -32768
    check b(0x80, 0x00).getInt(0, 2, bigEndian) == -32768
    check b(0xff, 0xff, 0xff, 0xff).getInt(0, 4) == -1
    check b(0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff).getInt(0, 8) == -1

  test "getBits":
    # 0xABC = 1010 1011 1100; little endian bytes BC 0A
    let d = b(0xbc, 0x0a)
    check d.getBits(littleEndian, 0, 4) == 0xc'u64
    check d.getBits(littleEndian, 4, 4) == 0xb'u64
    check d.getBits(littleEndian, 8, 4) == 0xa'u64
    check d.getBits(littleEndian, 0, 12) == 0xabc'u64
    check d.getBits(littleEndian, 12, 8) == 0'u64 # beyond the data: zeros
    check b(0x0a, 0xbc).getBits(bigEndian, 0, 12) == 0xabc'u64
    check d.getBits(littleEndian, 3, 0) == 0'u64

  test "reading a file":
    expect IOError:
      discard readBytes("/no/such/file.fit")
