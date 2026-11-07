import std/[options, unittest]
import nimchoo/proquint

suite "proquint: numbers as pronounceable words":
  test "the specification's example: 127.0.0.1 is lusab-babad":
    check proquint([0x7f'u8, 0, 0, 1]) == "lusab-babad"
    check fromProquint("lusab-babad") == some(@[0x7f'u8, 0, 0, 1])
  test "16 bits are one group; 48 bits are three":
    check proquint([0'u8, 0]) == "babab"
    check proquint([0xff'u8, 0xff]) == "zuzuz"
    check proquint([1'u8, 2, 3, 4, 5, 6]).len == 17
  test "they round trip":
    var seed = 99'u32
    for round in 0 ..< 200:
      var bytes: seq[byte]
      for i in 0 ..< 2 * (1 + round mod 4):
        seed = seed * 1664525'u32 + 1013904223'u32
        bytes.add byte(seed shr 16)
      check fromProquint(proquint(bytes)) == some(bytes)
  test "what is not a proquint is refused":
    for bad in [
      "", "lusab", "lusab-", "lusab-babad-", "lusabbabad", "lusab_babad", "LUSAB-babad",
      "lusac-babad", "lusab-babadd", "xxxxx",
    ]:
      if bad != "lusab":
        check fromProquint(bad).isNone
    check fromProquint("lusab").isSome
    check isProquint("lusab-babad-fuzoh") and not isProquint("lusab-bab")
