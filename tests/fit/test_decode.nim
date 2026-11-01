import std/[algorithm, options, os, sequtils, strutils, tables, unittest]
import nimchoo/fit/bytes
import nimchoo/fit/[reader, records]
import nimchoo/profile/load
import nimchoo/fit/tokens
import ../support/fitbuilder

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  sdkDir = "../choochoo/data/test/source/sdk/"
  dataDirs = [sdkDir, "../choochoo/data/test/source/personal/"]

let p = loadProfile(profilePath)

proc decodeAll(body: seq[byte]): (Reader, seq[Record]) =
  var r = initReader(p, fitFile(body))
  var recs: seq[Record]
  for rec in r.records(p): recs.add rec
  (r, recs)

func fv(r: Record, name: string): FieldValue =
  let f = r.field(name)
  doAssert f.isSome, "no field " & name & " in " & r.fields.mapIt(it.name).join(",")
  f.get

func names(r: Record): seq[string] = r.fields.mapIt(it.name)

func str(s: string, n: int): seq[byte] =
  ## `s` NUL-padded to `n` bytes.
  result = newSeq[byte](n)
  for i, c in s: result[i] = byte(c)

func csd(speed, dist: int): seq[byte] =
  ## compressed_speed_distance: 12 bits speed, 12 bits distance
  le32(speed or (dist shl 12))[0 .. 2]

suite "decode: plain fields":
  test "ints, scaled floats, signed":
    let body = defn(0, 20, @[(253, 4, uint32T), (3, 1, uint8T), (5, 4, uint32T),
                             (78, 4, uint32T), (0, 4, sint32T)]) &
      b(0) & le32(1000) & b(150) & le32(12345) & le32(3000) & le32(-5)
    let (r, recs) = decodeAll(body)
    check recs.len == 1
    check r.warnings.len == 0
    let rec = recs[0]
    check rec.name == "record"
    check rec.number == 20
    check rec.timestamp == some(1000'i64)
    check rec.fv("timestamp").ints == @[1000'i64]
    check rec.fv("timestamp").typeName == "date_time"
    check rec.fv("timestamp").units == "s"
    check rec.fv("heart_rate").kind == vkInt
    check rec.fv("heart_rate").ints == @[150'i64]
    check rec.fv("heart_rate").units == "bpm"
    check rec.fv("heart_rate").number == 3
    check rec.fv("distance").floats == @[123.45]      # 12345 / 100
    check rec.fv("enhanced_altitude").floats == @[100.0]  # 3000 / 5 - 500
    check rec.fv("position_lat").ints == @[-5'i64]
    check rec.names == @["timestamp", "heart_rate", "distance",
                         "enhanced_altitude", "position_lat"]

  test "enumerations stay numeric; valueName gives the profile name":
    let body = defn(0, 21, @[(0, 1, enumT), (1, 1, enumT)]) & b(0, 0, 0)
    let (_, recs) = decodeAll(body)
    let ev = recs[0].fv("event")
    check ev.kind == vkInt
    check ev.ints == @[0'i64]
    check ev.typeName == "event"
    check valueName(p, ev) == "timer"
    check valueName(p, recs[0].fv("event_type")) == "start"

  test "bad values are left out":
    let body = defn(0, 20, @[(3, 1, uint8T), (4, 1, uint8T)]) & b(0, 0xff, 88)
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["cadence"]

  test "strings":
    let body = defn(0, 206, @[(3, 8, stringT)]) & b(0) & str("power", 8)
    let (_, recs) = decodeAll(body)
    check recs[0].fv("field_name").kind == vkString
    check recs[0].fv("field_name").strings == @["power"]

suite "decode: composite fields":
  test "component is decoded as its target field":
    let body = defn(0, 20, @[(2, 2, uint16T), (6, 2, uint16T)]) &
      b(0) & le16(3000) & le16(2500)
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["enhanced_altitude", "enhanced_speed"]
    check recs[0].fv("enhanced_altitude").floats == @[100.0]
    check recs[0].fv("enhanced_speed").floats == @[2.5]
    check recs[0].fv("enhanced_altitude").number == 78

  test "nested: outermost scale wins":
    # speed 1000 -> speed -> enhanced_speed, scaled by 100 (not 1000)
    let body = defn(0, 20, @[(8, 3, byteT)]) & b(0) & csd(1000, 160)
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["enhanced_speed", "distance"]
    check recs[0].fv("enhanced_speed").floats == @[10.0]
    check recs[0].fv("enhanced_speed").units == "m/s"
    check recs[0].fv("distance").floats == @[10.0]   # 160 / 16
    check recs[0].fv("distance").units == "m"

  test "composite larger than 8 bytes (hr.event_timestamp_12)":
    # 8 x 12 bits: 1, 2, ... 8 packed low bits first, giving one array; the
    # profile lists 10 components, the extra two do not fit and are ignored
    var big: seq[byte] = newSeq[byte](12)
    for i in 0 ..< 8:
      for k in 0 ..< 12:
        if (((i + 1) shr k) and 1) == 1:
          let bit = i * 12 + k
          big[bit div 8] = big[bit div 8] or byte(1 shl (bit mod 8))
    let msg = p.messages["hr"]
    let body = defn(0, msg.number, @[(10, 12, byteT)]) & b(0) & big
    let (r, recs) = decodeAll(body)
    check r.warnings.len == 0
    check recs[0].fields.len == 1
    check recs[0].fields[0].name == "event_timestamp"
    check recs[0].fields[0].floats ==
      @[1.0 / 1024, 2.0 / 1024, 3.0 / 1024, 4.0 / 1024, 5.0 / 1024,
        6.0 / 1024, 7.0 / 1024, 8.0 / 1024]

  test "big-endian composite":
    let body = defn(0, 20, @[(6, 2, uint16T)], big = true) & b(0) & be16(2500)
    let (_, recs) = decodeAll(body)
    check recs[0].fv("enhanced_speed").floats == @[2.5]

  test "bad composite is dropped":
    let body = defn(0, 20, @[(6, 2, uint16T)]) & b(0) & le16(0xffff)
    let (_, recs) = decodeAll(body)
    check recs[0].fields.len == 0

  test "one entry per name: the widest source wins (data over data16)":
    # event.data16 (16 bits, via a component) and event.data (32 bits) both
    # give timer_trigger; use different values to see which one is kept
    let body = defn(0, 21, @[(0, 1, enumT), (2, 2, uint16T), (3, 4, uint32T)]) &
      b(0, 0) & le16(4) & le32(9)
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["event", "timer_trigger"]
    check recs[0].fv("timer_trigger").ints == @[9'i64]
    check recs[0].fv("timer_trigger").bits == 32

  test "one entry per name: enhanced_altitude over altitude":
    let body = defn(0, 20, @[(2, 2, uint16T), (78, 4, uint32T)]) &
      b(0) & le16(3000) & le32(3500)
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["enhanced_altitude"]
    check recs[0].fv("enhanced_altitude").floats == @[200.0]  # 3500 / 5 - 500

  test "one entry per name: the narrow value is kept if the wide one is bad":
    let body = defn(0, 20, @[(2, 2, uint16T), (78, 4, uint32T)]) &
      b(0) & le16(3000) & le32(0xffffffff'i64)
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["enhanced_altitude"]
    check recs[0].fv("enhanced_altitude").floats == @[100.0]

  test "accumulated component rolls over":
    let body = defn(0, 20, @[(8, 3, byteT)]) &
      b(0) & csd(0, 160) & b(0) & csd(0, 100) & b(0) & csd(0, 200)
    let (_, recs) = decodeAll(body)
    check recs.mapIt(it.fv("distance").floats[0]) ==
      @[10.0, 4196.0 / 16, 4296.0 / 16]

  test "accumulators are per message":
    let body = defn(0, 20, @[(8, 3, byteT)]) & defn(1, 18, @[(3, 1, uint8T)]) &
      b(0) & csd(0, 160) & b(0) & csd(0, 100)
    let (_, recs) = decodeAll(body)
    check recs[1].fv("distance").floats == @[4196.0 / 16]

suite "decode: dynamic fields":
  test "subfield chosen by the referenced field":
    let body = defn(0, 23, @[(2, 2, uint16T), (4, 2, uint16T)]) &
      b(0) & le16(1) & le16(1000) &       # garmin
      b(0) & le16(263) & le16(1000) &     # favero
      b(0) & le16(9999) & le16(1000)      # unknown manufacturer
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["manufacturer", "garmin_product"]
    check recs[0].fv("garmin_product").ints == @[1000'i64]
    check recs[1].names == @["manufacturer", "favero_product"]
    check recs[2].names == @["manufacturer", "product"]

  test "reference may come later in the definition":
    let body = defn(0, 23, @[(4, 2, uint16T), (2, 2, uint16T)]) &
      b(0) & le16(1000) & le16(1)
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["garmin_product", "manufacturer"]

  test "session.total_cycles by sport":
    let body = defn(0, 18, @[(5, 1, enumT), (10, 4, uint32T)]) &
      b(0, 1) & le32(500) &    # running
      b(0, 2) & le32(500) &    # cycling
      b(0, 0) & le32(500)      # generic
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["sport", "total_strides"]
    check recs[1].names == @["sport", "total_strokes"]
    check recs[2].names == @["sport", "total_cycles"]
    check recs[2].fv("total_cycles").units == "cycles"

  test "composite whose target is dynamic (event.data16 -> data)":
    let body = defn(0, 21, @[(0, 1, enumT), (2, 2, uint16T)]) &
      b(0, 0) & le16(4) &      # timer: data is timer_trigger
      b(0, 3) & le16(4)        # no subfield for this event
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["event", "timer_trigger"]
    check recs[0].fv("timer_trigger").ints == @[4'i64]
    check recs[1].names == @["event", "data"]

suite "decode: timestamps":
  test "compressed timestamp header adds a timestamp field":
    let body = defn(0, 20, @[(253, 4, uint32T), (3, 1, uint8T)]) &
      b(0) & le32(1000) & b(150) &
      defn(1, 20, @[(3, 1, uint8T)]) &
      @[byte(0x80 or (1 shl 5) or 12)] & b(99)
    let (_, recs) = decodeAll(body)
    check recs[1].names == @["timestamp", "heart_rate"]
    check recs[1].fv("timestamp").ints == @[1004'i64]
    check recs[1].timestamp == some(1004'i64)

  test "timestamp_16 stays raw; the record gets the expanded time":
    let msg = p.messages["monitoring"]
    let n16 = msg.fields["timestamp_16"].number.get
    let body = defn(0, msg.number, @[(253, 4, uint32T)]) &
      b(0) & le32(0x15c5c) &
      defn(1, msg.number, @[(n16, 2, uint16T)]) & b(1) & le16(0x5e5e)
    let (r, recs) = decodeAll(body)
    check r.warnings.len == 0
    check recs[1].fv("timestamp_16").ints == @[0x5e5e'i64]
    check recs[1].fv("timestamp_16").typeName == "timestamp_16"
    check recs[1].timestamp == some(0x15c5c'i64 + 0x202)

suite "decode: unknown parts":
  test "unknown field number":
    let body = defn(0, 20, @[(3, 1, uint8T), (200, 1, uint8T)]) & b(0, 99, 7)
    let (_, recs) = decodeAll(body)
    check recs[0].names == @["heart_rate", ""]
    check recs[0].fields[1].number == 200
    check recs[0].fields[1].ints == @[7'i64]
    check recs[0].fields[1].typeName == "uint8"

  test "unknown message":
    let body = defn(0, 65000, @[(1, 1, uint8T)]) & b(0, 5)
    let (_, recs) = decodeAll(body)
    check recs[0].name == ""
    check recs[0].number == 65000
    check recs[0].fields.len == 1

suite "decode: developer fields":
  let described = defn(0, 206, @[(0, 1, uint8T), (1, 1, uint8T), (2, 1, uint8T),
                                 (3, 8, stringT), (8, 4, stringT)]) &
    b(0, 0, 1, 132) & str("power", 8) & str("W", 4)

  test "described developer field":
    let body = described &
      defn(1, 20, @[(3, 1, uint8T)], dev = @[(1, 2, 0)]) &
      b(1, 99) & le16(321)
    let (r, recs) = decodeAll(body)
    check r.warnings.len == 0
    check recs.len == 2
    check recs[1].names == @["heart_rate", "power"]
    let f = recs[1].fv("power")
    check f.dev
    check f.ints == @[321'i64]
    check f.units == "W"
    check f.typeName == "uint16"
    check f.number == 1

  test "undescribed developer field is skipped with a warning":
    let body = described &
      defn(1, 20, @[(3, 1, uint8T)], dev = @[(1, 2, 0), (2, 1, 0)]) &
      b(1, 99) & le16(321) & b(5)
    let (r, recs) = decodeAll(body)
    check recs[1].names == @["heart_rate", "power"]
    check r.warnings.len == 1
    check r.warnings[0].kind == wkUndescribedDevField
    check "developer field 2" in r.warnings[0].msg

suite "decode: real files":
  test "Activity.fit: first record matches the SDK CSV":
    var r = initReader(p, readBytes(sdkDir & "Activity.fit"))
    var first: Option[Record]
    for rec in r.records(p):
      if rec.name == "record":
        first = some(rec)
        break
    check first.isSome
    let rec = first.get
    check rec.fv("timestamp").ints == @[702940946'i64]
    check rec.fv("position_lat").ints == @[495280430'i64]
    check rec.fv("position_long").ints == @[-872696681'i64]
    check rec.fv("distance").floats == @[0.02]
    check abs(rec.fv("enhanced_altitude").floats[0] - 278.2) < 1e-9
    check rec.fv("enhanced_speed").floats == @[0.0]

  test "DeveloperData.fit: developer field matches the SDK CSV":
    var r = initReader(p, readBytes(sdkDir & "DeveloperData.fit"))
    var first: Option[Record]
    for rec in r.records(p):
      if rec.name == "record":
        first = some(rec)
        break
    check first.isSome
    let rec = first.get
    check rec.fv("heart_rate").ints == @[140'i64]
    check rec.fv("distance").floats == @[510.0]
    check abs(rec.fv("enhanced_speed").floats[0] - 47.488) < 1e-9
    let dough = rec.fv("doughnuts_earned")
    check dough.dev
    check dough.ints == @[1'i64]
    check dough.units == "doughnuts"

  test "sdk and personal files decode":
    var files, records = 0
    for dir in dataDirs:
      for path in walkFiles(dir / "*.fit"):
        inc files
        var r = initReader(p, readBytes(path))
        for rec in r.records(p): inc records
        if r.warnings.len > 0:
          checkpoint path & ": " & $r.warnings[0 ..< min(3, r.warnings.len)]
          fail()
    check files > 20
    check records > 1000

suite "decode: warnings":
  test "the reader merges tokenizer and decoder warnings in file order":
    # message 1: an undescribed developer field (a decoder warning); message 2
    # has the reserved bit set (a tokenizer warning, at a later offset)
    let body = defn(0, 20, @[(3, 1, uint8T)], dev = @[(1, 2, 0)]) &
      b(0, 99) & le16(7) &
      b(0x10, 98) & le16(8)
    let (r, _) = decodeAll(body)
    check r.warnings.mapIt(it.kind) == @[wkUndescribedDevField, wkReservedBit,
                                         wkUndescribedDevField]
    var offsets = r.warnings.mapIt(it.offset)
    check offsets == offsets.sorted
