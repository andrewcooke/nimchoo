import std/[sequtils, strutils, unittest]
import nimchoo/selection/bits

proc roundTrip(ids: seq[int64], maxId = 1112'i64): bool =
  let d = decodeBits(encodeBits(ids), maxId)
  d.problem == "" and d.ids == ids

suite "bits: a set of activities as a string":
  test "the empty set is the empty string":
    check encodeBits(newSeq[int64]()) == ""
    check decodeBits("", 10).ids.len == 0 and decodeBits("", 10).problem == ""
  test "round trips: one, a run, all, scattered, a run and singles":
    check roundTrip(@[1'i64]) and roundTrip(@[1112'i64]) and roundTrip(@[156'i64])
    check roundTrip(toSeq(1'i64 .. 1112'i64))
    check roundTrip(toSeq(200'i64 .. 260'i64))
    check roundTrip(@[156'i64, 159, 165, 582, 682, 696, 705, 718, 724, 733])
    check roundTrip(@[1'i64, 2, 3, 10, 11, 500, 1000, 1001, 1002, 1112])
  test "order and repeats do not matter":
    check encodeBits([733'i64, 156, 156, 582, 0, -4]) == encodeBits([156'i64, 582, 733])
  test "the strings use only the URL-safe alphabet":
    for s in [
      encodeBits(toSeq(1'i64 .. 1112'i64)),
      encodeBits(@[156'i64, 159, 165, 582, 682]),
      encodeBits(toSeq(countup(3'i64, 1100, 7))),
    ]:
      check s.allIt(it in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_'})
  test "short for the usual selections":
    check encodeBits(toSeq(1'i64 .. 1112'i64)).len <= 6 # everything
    check encodeBits(toSeq(1000'i64 .. 1060'i64)).len <= 8 # a date range
    check encodeBits(@[1112'i64]).len <= 5 # one ride
    check encodeBits(@[156'i64, 159, 165, 582, 682, 696, 705, 718, 724, 733]).len <= 20
      # ten scattered
  test "a scatter of many is no longer than the bitmap":
    var ids: seq[int64]
    for i in 1'i64 .. 1112:
      if i mod 3 != 0:
        ids.add i
    check encodeBits(ids).len <= (1112 + 20) div 6 + 2
    check roundTrip(ids)
  test "random sets round trip":
    var seed = 20261106'u32
    proc next(): uint32 =
      seed = seed * 1664525'u32 + 1013904223'u32
      seed shr 8

    for round in 0 ..< 60:
      let density = int(next() mod 40) + 1
      var ids: seq[int64]
      for i in 1'i64 .. 2000:
        if int(next() mod 100) < density:
          ids.add i
      if ids.len > 0:
        check roundTrip(ids, 2000)

suite "bits: an address is not trusted":
  test "characters that are not in the alphabet":
    check decodeBits("ab+d", 1112).problem.contains("cannot be in")
    check decodeBits("a b", 1112).problem.contains("cannot be in")
  test "cut off, or with more than it says":
    let s = encodeBits(@[156'i64, 159, 165, 582, 682, 696, 705, 718, 724, 733])
    check decodeBits(s[0 ..< s.len - 4], 1112).problem != ""
    check decodeBits(s & "AAAAAAAA", 1112).problem != ""
  test "an id beyond the last one is refused":
    check decodeBits(encodeBits(@[500'i64]), 100).problem.contains("beyond")
    check decodeBits(encodeBits(toSeq(1'i64 .. 300'i64)), 100).problem.contains(
      "beyond"
    )
    check decodeBits(encodeBits(toSeq(countup(1'i64, 300, 2))), 100).problem.contains(
      "beyond"
    ) # a bitmap
  test "far too long, or far too many runs, is refused before anything is made":
    check decodeBits("A".repeat(maxChars + 1), 1112).problem.contains("too many")
    check decodeBits("A", 1112).problem != "" # (a number of zeros that never ends)
    check decodeBits("_".repeat(40), 1112).problem != ""
  test "it never crashes on anything":
    var seed = 7'u32
    for round in 0 ..< 400:
      var s = ""
      for i in 0 ..< int((seed shr 12) mod 30) + 1:
        seed = seed * 1664525'u32 + 1013904223'u32
        s.add "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"[
          int((seed shr 10) mod 64)
        ]
      discard decodeBits(s, 5000)
