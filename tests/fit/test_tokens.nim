import std/[options, os, sequtils, sets, strutils, unittest]
import nimchoo/errors
import nimchoo/fit/[bytes, crc]
import nimchoo/profile/load
import nimchoo/fit/tokens
import ../support/fitbuilder

const dataDirs = ["../choochoo/data/test/source/sdk",
                  "../choochoo/data/test/source/personal"]

proc tokenize(data: seq[byte], ts16 = initHashSet[(int, int)]()):
    (Tokenizer, seq[Token]) =
  var t = initTokenizer(data, ts16)
  var toks: seq[Token]
  for tok in t.tokens: toks.add tok
  (t, toks)

func kinds(toks: seq[Token]): seq[TokenKind] =
  for tok in toks: result.add tok.kind

suite "tokenizer: hand-built files":
  test "definition, data, compressed timestamp, checksum":
    let body = defn(0, 20, @[(253, 4, uint32T), (3, 1, uint8T)]) &
      @[byte(0x00)] & le32(1000) & b(77) &    # data: timestamp 1000, field 77
      defn(1, 21, @[(5, 1, uint8T)]) &
      @[byte(0x80 or (1 shl 5) or 0x0a)] & b(9)  # compressed, local 1, offset 10
    let (t, toks) = tokenize(fitFile(body))
    check toks.kinds == @[tokHeader, tokDefinition, tokData, tokDefinition,
                          tokData, tokChecksum]
    check t.warnings.len == 0
    # byte ranges are contiguous and cover the file
    var pos = 0
    for tok in toks:
      check tok.offset == pos
      pos += tok.len
    check pos == t.data.len
    let d = t.defs[toks[1].defn]
    check d.globalNum == 20
    check d.endian == littleEndian
    check d.size == 1 + 4 + 1
    check d.fields[0].offset == 1
    check d.fields[1].offset == 5
    check d.timestampField == 0
    check toks[2].len == 6
    check toks[2].timestamp == some(1000'i64)
    check not toks[2].compressed
    # 1000 = 0x3e8, low 5 bits = 8; offset 10 >= 8, so no rollover
    check toks[4].compressed
    check toks[4].timestamp == some(1002'i64)
    check toks[5].checksum == uint16(crc16(t.data[0 ..< t.data.len - 2]))

  test "compressed timestamp rollover":
    # timestamp 0x3f = low bits 31; offset 2 < 31 so rolls into next block
    let body = defn(0, 20, @[(253, 4, uint32T)]) & @[byte(0)] & le32(0x3f) &
      defn(1, 21, @[(5, 1, uint8T)]) & @[byte(0x80 or (1 shl 5) or 2)] & b(0)
    let (_, toks) = tokenize(fitFile(body))
    check toks[^2].timestamp == some(0x22'i64 + 0x20)

  test "big-endian definition":
    let body = defn(0, 20, @[(253, 4, uint32T)], big = true) &
      @[byte(0)] & be32(0x01020304)
    let (t, toks) = tokenize(fitFile(body))
    check t.defs[0].endian == bigEndian
    check t.defs[0].globalNum == 20
    check toks[2].timestamp == some(0x01020304'i64)

  test "developer fields add to the data size":
    let body = defn(0, 20, @[(3, 1, uint8T)], dev = @[(0, 2, 0), (1, 4, 0)]) &
      @[byte(0)] & b(1) & b(2, 3) & b(4, 5, 6, 7)
    let (t, toks) = tokenize(fitFile(body))
    check toks.kinds == @[tokHeader, tokDefinition, tokData, tokChecksum]
    check t.defs[0].size == 1 + 1 + 2 + 4
    check t.defs[0].devFields.len == 2
    check t.defs[0].devFields[1].offset == 4
    check t.defs[0].devFields[1].devIndex == 0
    check toks[2].len == 8

  test "redefinition keeps earlier definitions":
    let body = defn(0, 20, @[(3, 1, uint8T)]) & b(0, 1) &
      defn(0, 21, @[(3, 2, uint16T)]) & b(0, 1, 2)
    let (t, toks) = tokenize(fitFile(body))
    check t.defs.len == 2
    check toks[2].defn == 0
    check toks[4].defn == 1
    check t.defs[1].globalNum == 21

  test "timestamp_16":
    let ts16 = toHashSet([(20, 7)])
    let body = defn(0, 20, @[(253, 4, uint32T)]) & @[byte(0)] & le32(0x15c5c) &
      defn(1, 20, @[(7, 2, uint16T)]) &
      @[byte(1)] & le16(0x5e5e) &         # increment
      @[byte(1)] & le16(0x5a5a)           # small decrement: warns
    let (t, toks) = tokenize(fitFile(body), ts16)
    check toks[4].timestamp == some(0x15c5c'i64 + 0x202)
    check toks[5].timestamp == some(0x15c5c'i64 + 0x202 - 0x404)
    check t.warnings.len == 1
    check t.warnings[0].kind == wkTimestamp16Backwards

  test "chained files":
    let one = fitFile(defn(0, 20, @[(3, 1, uint8T)]) & b(0, 1))
    let (t, toks) = tokenize(one & one)
    check toks.kinds == @[tokHeader, tokDefinition, tokData, tokChecksum,
                          tokHeader, tokDefinition, tokData, tokChecksum]
    check t.defs.len == 2

  test "chained files: definitions do not carry over":
    let one = fitFile(defn(0, 20, @[(3, 1, uint8T)]) & b(0, 1))
    let two = fitFile(b(0, 1))  # data with no definition
    var t = initTokenizer(one & two, initHashSet[(int, int)]())
    expect FitError:
      for tok in t.tokens: discard

  test "data size 0 in header falls back to end of file":
    var d = fitFile(defn(0, 20, @[(3, 1, uint8T)]) & b(0, 1))
    d[4 .. 7] = b(0, 0, 0, 0)
    let (t, toks) = tokenize(d)
    check toks.kinds == @[tokHeader, tokDefinition, tokData, tokChecksum]
    check t.warnings.anyIt(it.kind == wkDataSizeIgnored)

suite "tokenizer: errors":
  func raisesWith(data: seq[byte], text: string): bool =
    var t = initTokenizer(data, initHashSet[(int, int)]())
    try:
      for tok in t.tokens: discard
    except FitError as e:
      return text in e.msg
    false

  test "data for undefined local type":
    check fitFile(b(0x03, 1, 2)).raisesWith("no definition for local message type 3")
  test "truncated data message":
    let body = defn(0, 20, @[(3, 4, uint32T)]) & b(0, 1, 2)
    check fitFile(body).raisesWith("truncated data message")
  test "truncated definition":
    check fitFile(b(0x40, 0, 0, 20, 0, 5, 1)).raisesWith("truncated definition")
  test "compressed timestamp before any timestamp":
    let body = defn(0, 20, @[(3, 1, uint8T)]) & b(0x80, 1)
    check fitFile(body).raisesWith("compressed timestamp with no preceding")
  test "error message includes offset":
    check fitFile(b(0x03, 1)).raisesWith("at offset 12")
  test "too short":
    check raisesWith(b(12, 16, 0), "too short")

suite "tokenizer: real files":
  test "sdk and personal files tokenize cleanly":
    var n = 0
    for dir in dataDirs:
      for path in walkFiles(dir / "*.fit"):
        inc n
        let data = readBytes(path)
        var t = initTokenizer(data, initHashSet[(int, int)]())
        var toks: seq[Token]
        try:
          for tok in t.tokens: toks.add tok
        except FitError as e:
          checkpoint path
          fail()
          echo path, ": ", e.msg
          continue
        var pos = 0
        for tok in toks:
          check tok.offset == pos
          pos += tok.len
        check pos == data.len
        check toks[^1].kind == tokChecksum
        check t.warnings.len == 0
    check n > 20

  test "monitoring file: timestamp_16 messages get timestamps":
    # (absolute timestamps in this file are not monotonic - monitoring_info
    # is stamped ~61h before the device_info that precedes it - so we only
    # check that timestamp_16 expansion works without going backwards)
    let p = loadProfile("../choochoo/data/sdk/Profile.xlsx")
    let data = readBytes(dataDirs[0] / "MonitoringFile.fit")
    var t = initTokenizer(data, p.timestamp16Fields)
    var seen = 0
    for tok in t.tokens:
      if tok.kind == tokData and tok.timestamp.isSome and
          t.defs[tok.defn].timestampField >= 0 and
          t.defs[tok.defn].fields[t.defs[tok.defn].timestampField].number != 253:
        inc seen
    check seen > 0
    check t.warnings.len == 0
