import std/[options, sequtils, unittest]
import nimchoo/errors
import nimchoo/fit/[bytes, crc, header]
import nimchoo/warnings
import ./fitbuilder

const
  sdkDir = "../choochoo/data/test/source/sdk/"
  personalDir = "../choochoo/data/test/source/personal/"

func hasKind(ps: seq[Warning], k: WarningKind): bool =
  ps.anyIt(it.kind == k)

suite "crc":
  test "whole valid file has zero residue":
    for path in [sdkDir & "Activity.fit", personalDir & "2018-03-04-qdp.fit"]:
      check crc16(readBytes(path)) == 0

  test "incremental":
    let d = readBytes(sdkDir & "Activity.fit")
    check crc16(d[50 .. ^1], crc16(d[0 .. 49])) == crc16(d)

  test "empty":
    check crc16(newSeq[byte]()) == 0

suite "file header":
  test "valid files":
    for path in [sdkDir & "Activity.fit", personalDir & "2018-03-04-qdp.fit"]:
      let d = readBytes(path)
      let h = readHeader(d)
      check h.dataType == ".FIT"
      check h.size in [12, 14]
      check h.dataSize + h.size + 2 == d.len
      check problems(h, d).len == 0

  test "too short":
    expect FitError:
      discard readHeader(b(12, 16, 0))

  test "corrupt data byte":
    var d = readBytes(sdkDir & "Activity.fit")
    let h = readHeader(d)
    d[h.size + 10] = d[h.size + 10] xor 0xff
    let ps = problems(h, d)
    check ps.len == 1
    check ps.hasKind(wkFileChecksum)

  test "corrupt data type":
    var d = readBytes(sdkDir & "Activity.fit")
    d[8] = byte('X')
    let ps = problems(readHeader(d), d)
    check ps.hasKind(wkDataType)

  test "truncated file":
    let d = readBytes(sdkDir & "Activity.fit")
    let cut = d[0 ..< d.len - 5]
    let ps = problems(readHeader(cut), cut)
    check ps.hasKind(wkDataSize)
    check ps.hasKind(wkFileChecksum)

  test "corrupt header checksum":
    var d = readBytes(personalDir & "2018-03-04-qdp.fit")
    let h = readHeader(d)
    if h.checksum.isSome:
      d[4] = d[4] xor 1  # data size changes, so header crc is now wrong
      check problems(readHeader(d), d).hasKind(wkHeaderChecksum)
