import std/[options, random, unittest]
import nimchoo/packages/util/bytes/leb128

func encoded(v: uint64): string =
  result.putUleb v

suite "LEB128":
  test "the standard encodings: 7 bits a byte, the lowest first, the top bit set while more follow":
    check encoded(0) == "\x00"
    check encoded(127) == "\x7F"
    check encoded(128) == "\x80\x01"
    check encoded(300) == "\xAC\x02"
    check encoded(16383) == "\xFF\x7F"
    check encoded(16384) == "\x80\x80\x01"
    check encoded(high(uint64)).len == 10

  test "what is written is read back, and the position moves past it":
    var r = initRand(7)
    var s = ""
    var values: seq[uint64]
    for i in 0 ..< 1000:
      let v = r.next() shr r.rand(63)
      values.add v
      s.putUleb v
    var pos = 0
    for v in values:
      check getUleb(s, pos) == some(v)
    check pos == s.len

  test "bytes that end inside a number, or a number too long for 64 bits, are none":
    var pos = 0
    check getUleb("\x80", pos).isNone
    pos = 0
    check getUleb("", pos).isNone
    pos = 0
    check getUleb("\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x02", pos).isNone
      # (past 64 bits)
    pos = 0
    check getUleb("\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01", pos) == some(high(uint64))
    pos = 0
    check getUleb("\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x00", pos).isNone

  test "zigzag: 0, -1, 1, -2, 2 ... are 0, 1, 2, 3, 4 ..., and back, to the ends":
    check [zigzag(0), zigzag(-1), zigzag(1), zigzag(-2), zigzag(2)] ==
      [0'u64, 1, 2, 3, 4]
    for v in [0'i64, 1, -1, 1000, -1000, high(int64), low(int64)]:
      check unzigzag(zigzag(v)) == v
