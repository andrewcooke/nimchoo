## Damage for FIT files, for the fuzzer (tests/fit/test_fuzz.nim).  Some of it
## is blind (bit flips, truncation, splices); most of it knows the structure of
## the file: a walker finds the records, the definitions and their fields, and
## the mutations change what the decoder trusts (field sizes, base types, field
## counts, byte order, message numbers, developer flags, local types, compressed
## timestamps, values), duplicate, drop and swap whole records.  Afterwards the
## header's length and the CRCs are usually repaired, so that the damage is seen
## by the decoder and not just reported as a bad checksum.

import std/[random, sequtils]
import nimchoo/fit/crc

type
  FieldAt* = object
    num*, size*, base*: int
    at*: int ## offset of the field's entry in a definition, or of its bytes in a data message

  Rec* = object
    start*, len*: int
    isDef*: bool
    local*: int
    hasDev*: bool
    archAt*, globalAt*, countAt*, devCountAt*: int ## -1 if not a definition (or no developer part)
    entries*: seq[FieldAt] ## definition: its field entries, developer ones last
    values*: seq[FieldAt] ## data message: its fields, in order

  Walk* = object
    recs*: seq[Rec]
    complete*: bool ## the walk reached the end of the data

  Defn = object
    known: bool
    sizes: seq[(int, int, int)] ## (number, size, base type) of every field, developer ones too

proc walk*(d: seq[byte]): Walk =
  ## The records of the first file in `d`, as far as they can be followed.
  if d.len < 16 or d[0] < 12:
    return
  let first = int(d[0])
  var dataSize = 0
  for i in 0 ..< 4:
    dataSize += int(d[4 + i]) shl (8 * i)
  let stop = min(d.len - 2, first + dataSize)
  var defs: array[16, Defn]
  var pos = first
  while pos < stop:
    let h = int(d[pos])
    var rec = Rec(
      start: pos, archAt: -1, globalAt: -1, countAt: -1, devCountAt: -1
    )
    if (h and 0x80) == 0 and (h and 0x40) != 0:
      rec.isDef = true
      rec.local = h and 15
      rec.hasDev = (h and 0x20) != 0
      if pos + 6 > stop:
        return
      rec.archAt = pos + 2
      rec.globalAt = pos + 3
      rec.countAt = pos + 5
      var at = pos + 6
      let n = int(d[pos + 5])
      if at + 3 * n + (if rec.hasDev: 1 else: 0) > stop:
        return
      var defn = Defn(known: true)
      for _ in 0 ..< n:
        let f = FieldAt(num: int(d[at]), size: int(d[at + 1]), base: int(d[at + 2]), at: at)
        rec.entries.add f
        defn.sizes.add (f.num, f.size, f.base)
        at += 3
      if rec.hasDev:
        rec.devCountAt = at
        let m = int(d[at])
        inc at
        if at + 3 * m > stop:
          return
        for _ in 0 ..< m:
          let f = FieldAt(num: int(d[at]), size: int(d[at + 1]), base: int(d[at + 2]), at: at)
          rec.entries.add f
          defn.sizes.add (f.num, f.size, 0)
          at += 3
      defs[rec.local] = defn
      rec.len = at - pos
    else:
      rec.local = if (h and 0x80) != 0: (h shr 5) and 3 else: h and 15
      if not defs[rec.local].known:
        return
      var at = pos + 1
      for (num, size, base) in defs[rec.local].sizes:
        rec.values.add FieldAt(num: num, size: size, base: base, at: at)
        at += size
      if at > stop:
        return
      rec.len = at - pos
    result.recs.add rec
    pos += rec.len
  result.complete = pos == stop

proc fixup*(d: var seq[byte]) =
  ## Make the header's data size and both CRCs true again (the file CRC
  ## replaces the last two bytes, which a truncation will have damaged).
  if d.len < 16:
    return
  let header = min(int(d[0]), d.len - 2)
  let size = uint32(max(0, d.len - header - 2))
  for i in 0 ..< 4:
    d[4 + i] = byte((size shr (8 * i)) and 0xff)
  if header >= 14:
    let h = crc16(d.toOpenArray(0, 11))
    d[12] = byte(h and 0xff)
    d[13] = byte(h shr 8)
  let c = crc16(d.toOpenArray(0, d.len - 3))
  d[d.len - 2] = byte(c and 0xff)
  d[d.len - 1] = byte(c shr 8)

proc interesting(r: var Rand): uint32 =
  ## Values that break arithmetic: limits, off-by-ones, sign bits.
  r.sample([0'u32, 1, 2, 0x7f, 0x80, 0xff, 0x100, 0x7fff, 0x8000, 0xffff, 0x7fffffff'u32,
            0x80000000'u32, 0xfffffffe'u32, 0xffffffff'u32])

proc putLe(d: var seq[byte], at, size: int, v: uint64) =
  for i in 0 ..< size:
    if at + i < d.len:
      d[at + i] = byte((v shr (8 * min(i, 7))) and 0xff)

type Kind = enum
  kFlipBit
  kSetByte
  kTruncate
  kSplice
  kHeaderSize
  kHeaderLength
  kFieldSize
  kFieldBase
  kFieldNumber
  kFieldCount
  kArch
  kGlobalNumber
  kRecordHeader
  kDevCount
  kDuplicate
  kDelete
  kSwap
  kValue
  kTimestamp
  kCompressed

const weights: array[Kind, int] = [
  kFlipBit: 3, kSetByte: 3, kTruncate: 1, kSplice: 1, kHeaderSize: 1, kHeaderLength: 1,
  kFieldSize: 6, kFieldBase: 5, kFieldNumber: 2, kFieldCount: 3, kArch: 2,
  kGlobalNumber: 2, kRecordHeader: 4, kDevCount: 2, kDuplicate: 3, kDelete: 3,
  kSwap: 2, kValue: 6, kTimestamp: 5, kCompressed: 3,
]

proc pickKind(r: var Rand): Kind =
  var total = 0
  for w in weights:
    total += w
  var n = r.rand(total - 1)
  for k in Kind:
    if n < weights[k]:
      return k
    n -= weights[k]

proc splice(d: seq[byte], cutFrom, cutTo: int, insert: seq[byte]): seq[byte] =
  d[0 ..< cutFrom] & insert & d[cutTo ..< d.len]

proc mutateOnce(r: var Rand, d: seq[byte], others: seq[seq[byte]]): seq[byte] =
  result = d
  let w = walk(d)
  let defs = w.recs.filterIt(it.isDef)
  let datas = w.recs.filterIt(not it.isDef)
  var kind = r.pickKind()
  # a structural mutation needs the structure it changes; otherwise blind damage
  case kind
  of kFieldSize, kFieldBase, kFieldNumber, kFieldCount, kArch, kGlobalNumber, kDevCount:
    if defs.len == 0:
      kind = kFlipBit
  of kValue, kTimestamp, kCompressed:
    if datas.len == 0:
      kind = kFlipBit
  of kRecordHeader, kDuplicate, kDelete, kSwap:
    if w.recs.len < 2:
      kind = kFlipBit
  else:
    discard
  case kind
  of kFlipBit:
    result[r.rand(result.high)] = result[r.rand(result.high)] xor byte(1 shl r.rand(7))
  of kSetByte:
    result[r.rand(result.high)] = byte(r.interesting() and 0xff)
  of kTruncate:
    result.setLen(r.rand(12 .. result.high))
  of kSplice:
    let o = r.sample(others)
    if o.len > 16:
      let a = r.rand(o.high)
      let b = min(o.high, a + r.rand(1 .. 64))
      let at = r.rand(result.high)
      result = result.splice(at, at, o[a .. b])
  of kHeaderSize:
    result[0] = byte(r.interesting() and 0xff)
  of kHeaderLength:
    result.putLe(4, 4, r.interesting())
  of kFieldSize:
    let def = r.sample(defs)
    if def.entries.len > 0:
      let e = r.sample(def.entries)
      result[e.at + 1] = byte(
        case r.rand(3)
        of 0: r.interesting() and 0xff
        of 1: uint32(e.size + 1)
        of 2: uint32(max(0, e.size - 1))
        else: uint32(e.size * 2)
      )
  of kFieldBase:
    let def = r.sample(defs)
    if def.entries.len > 0:
      let e = r.sample(def.entries)
      result[e.at + 2] = byte(
        if r.rand(1) == 0:
          r.rand(0 .. 0x0d) + (if r.rand(1) == 0: 0x80 else: 0)
        else:
          int(r.interesting() and 0xff)
      )
  of kFieldNumber:
    let def = r.sample(defs)
    if def.entries.len > 0:
      result[r.sample(def.entries).at] =
        byte(r.sample([0'u32, 1, 2, 3, 4, 250, 253, 254, 255, uint32(r.rand(255))]))
  of kFieldCount:
    let def = r.sample(defs)
    let n = int(d[def.countAt])
    result[def.countAt] = byte(r.sample([0, 1, n - 1, n + 1, n + 2, 255]) and 0xff)
  of kArch:
    result[r.sample(defs).archAt] = byte(r.sample([0, 1, 2, 0x80, 0xff]))
  of kGlobalNumber:
    let def = r.sample(defs)
    let num =
      if r.rand(1) == 0:
        uint64(r.sample(defs.mapIt(int(d[it.globalAt]) + 256 * int(d[it.globalAt + 1]))))
      else:
        uint64(r.interesting() and 0xffff)
    result.putLe(def.globalAt, 2, num)
  of kRecordHeader:
    let rec = r.sample(w.recs)
    let h = int(result[rec.start])
    result[rec.start] = byte(
      case r.rand(5)
      of 0: h xor 0x40
      of 1: h xor 0x20
      of 2: h xor 0x80
      of 3: (h and 0xf0) or r.rand(15)
      of 4: h xor (1 shl r.rand(7))
      else: int(r.interesting() and 0xff)
    )
  of kDevCount:
    let withDev = defs.filterIt(it.devCountAt >= 0)
    if withDev.len > 0:
      let def = r.sample(withDev)
      result[def.devCountAt] = byte(r.sample([0, 1, 2, 3, 255]))
    else:
      let def = r.sample(defs)
      result[def.start] = result[def.start] or 0x20 # developer data announced, none described
  of kDuplicate:
    let a = r.sample(w.recs)
    let b = r.sample(w.recs)
    result = result.splice(b.start, b.start, d[a.start ..< a.start + a.len])
  of kDelete:
    let a = r.sample(w.recs)
    result = result.splice(a.start, a.start + a.len, @[])
  of kSwap:
    var i = r.rand(w.recs.high - 1)
    let a = w.recs[i]
    let b = w.recs[i + 1]
    result = d[0 ..< a.start] & d[b.start ..< b.start + b.len] &
      d[a.start ..< a.start + a.len] & d[b.start + b.len ..< d.len]
  of kValue:
    let rec = r.sample(datas)
    if rec.values.len > 0:
      let f = r.sample(rec.values)
      let v = uint64(r.interesting())
      result.putLe(f.at, f.size, v or (v shl 32))
  of kTimestamp:
    # the field that every consumer does arithmetic with
    let withTs = datas.filterIt(it.values.anyIt(it.num == 253 or it.num == 254))
    let rec = if withTs.len > 0: r.sample(withTs) else: r.sample(datas)
    let candidates = rec.values.filterIt(it.num == 253 or it.size == 4)
    if candidates.len > 0:
      result.putLe(r.sample(candidates).at, 4, uint64(r.interesting()))
  of kCompressed:
    let rec = r.sample(datas)
    if rec.local <= 3:
      result[rec.start] = byte(0x80 or (rec.local shl 5) or r.rand(31))

proc mutate*(r: var Rand, d: seq[byte], others: seq[seq[byte]]): seq[byte] =
  ## One to four mutations of `d`; usually the lengths and CRCs are repaired
  ## afterwards (not always: the checks of the header are to be fuzzed too).
  result = d
  for _ in 0 ..< r.rand(1 .. 4):
    if result.len < 16:
      break
    result = r.mutateOnce(result, others)
  if r.rand(9) != 0:
    result.fixup()
