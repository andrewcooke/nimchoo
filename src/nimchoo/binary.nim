## Low-level FIT binary support: CRC, base type decoding, bad values, time
## conversion and the file header.  Pure functions over bytes; nothing here
## needs the profile (beyond the `BaseType` enum) or any parser state.
##
## Conventions: `Option` for values that are legitimately absent (bad values,
## unknown base type numbers); `FitError` only when we cannot continue;
## diagnostics are returned rather than logged.

import std/[options, strutils, times, unicode]
import ./errors
import ./profile
export errors

type
  RawKind* = enum rkInt, rkFloat, rkString

  RawValues* = object
    ## Unscaled, unmapped values read from a field.
    case kind*: RawKind
    of rkInt: ints*: seq[int64]  ## uint64 values above int64.high are bit-cast
    of rkFloat: floats*: seq[float]
    of rkString: strings*: seq[string]

  FileHeader* = object
    size*: int                 ## byte 0 (12 or 14)
    protocolVersion*: int      ## byte 1
    profileVersion*: int       ## bytes 2-3
    dataSize*: int             ## bytes 4-7
    dataType*: string          ## bytes 8-11, should be ".FIT"
    checksum*: Option[uint16]  ## bytes 12-13, if present and non-zero

proc readBytes*(path: string): seq[byte] =
  ## Whole file as bytes.
  let s = readFile(path)
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

# --- CRC

const crcTable: array[16, uint16] = [
  0x0000'u16, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
  0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]

func crc16*(data: openArray[byte], start: uint16 = 0): uint16 {.raises: [].} =
  ## FIT CRC.  Pass the previous result as `start` to continue incrementally.
  result = start
  for b in data:
    var tmp = crcTable[result and 0xf]
    result = (result shr 4) and 0xfff
    result = result xor tmp xor crcTable[b and 0xf]
    tmp = crcTable[result and 0xf]
    result = (result shr 4) and 0xfff
    result = result xor tmp xor crcTable[(b shr 4) and 0xf]

# --- base types

func size*(bt: BaseType): int {.raises: [].} =
  ## Bytes per element (strings and bytes count as 1).
  case bt
  of btEnum, btSint8, btUint8, btString, btUint8z, btByte: 1
  of btSint16, btUint16, btUint16z: 2
  of btSint32, btUint32, btFloat32, btUint32z: 4
  of btFloat64, btSint64, btUint64, btUint64z: 8

func isSigned*(bt: BaseType): bool {.raises: [].} =
  bt in {btSint8, btSint16, btSint32, btSint64}

func baseTypeOf*(b: byte): Option[BaseType] {.raises: [].} =
  ## Base type from the byte in a definition message: low 5 bits are the
  ## number; bit 7 (endian ability) is ignored.
  let n = int(b and 0x1f)
  if n <= ord(high(BaseType)): some(BaseType(n)) else: none(BaseType)

func invalid*(bt: BaseType): uint64 {.raises: [].} =
  ## The "bad value" marker, as the raw unsigned value.
  let bits = 8 * bt.size
  let ones = if bits == 64: high(uint64) else: (1'u64 shl bits) - 1
  case bt
  of btUint8z, btUint16z, btUint32z, btUint64z: 0'u64
  of btSint8, btSint16, btSint32, btSint64: ones shr 1
  else: ones  # unsigned, enum, byte, floats (all bits set)

func readUint*(data: openArray[byte], size: int,
               endian: Endianness): uint64 {.raises: [].} =
  ## First `size` bytes of `data` as an unsigned integer.
  for i in 0 ..< size:
    let b = if endian == littleEndian: data[size - 1 - i] else: data[i]
    result = (result shl 8) or uint64(b)

func readInt*(data: openArray[byte], size: int,
              endian: Endianness): int64 {.raises: [].} =
  ## First `size` bytes of `data` as a sign-extended integer.
  var u = readUint(data, size, endian)
  if size < 8 and (u and (1'u64 shl (8 * size - 1))) != 0:
    u = u or (high(uint64) shl (8 * size))
  cast[int64](u)

func isBad*(bt: BaseType, data: openArray[byte],
            endian: Endianness): bool {.raises: [].} =
  ## True if every element is the bad marker (or there are none).  Strings
  ## are never bad.
  if bt == btString: return false
  let sz = bt.size
  let marker = invalid(bt)
  let n = data.len div sz
  if n == 0: return true
  for i in 0 ..< n:
    if readUint(data.toOpenArray(i * sz, i * sz + sz - 1), sz, endian) != marker:
      return false
  true

func splitStrings(s: string): seq[string] {.raises: [].} =
  var s = s
  while s.len > 0 and s[^1] == '\0': s.setLen(s.len - 1)
  s.split('\0')

func decodeString(data: openArray[byte]): seq[string] {.raises: [].} =
  var s = newString(data.len)
  for i, b in data: s[i] = char(b)
  if validateUtf8(s) == -1:
    splitStrings(s)
  else:
    # close to what the Garmin CSV generates (as in choochoo)
    for i, b in data: s[i] = char(b mod 0x7f)
    splitStrings(s)

func decode*(bt: BaseType, data: openArray[byte], endian: Endianness,
             checkBad = true): Option[RawValues] {.raises: [].} =
  ## All elements in `data`.  None if every element is bad (unless `checkBad`
  ## is false).  Isolated bad elements in an array are returned raw (as the SDK
  ## CSV does).
  if bt == btString:
    return some(RawValues(kind: rkString, strings: decodeString(data)))
  if checkBad and isBad(bt, data, endian): return none(RawValues)
  let sz = bt.size
  let n = data.len div sz
  template part(i: int): untyped = data.toOpenArray(i * sz, i * sz + sz - 1)
  case bt
  of btFloat32, btFloat64:
    var xs = newSeq[float](n)
    for i in 0 ..< n:
      let u = readUint(part(i), sz, endian)
      xs[i] = if sz == 4: float(cast[float32](uint32(u))) else: cast[float64](u)
    some(RawValues(kind: rkFloat, floats: xs))
  else:
    var xs = newSeq[int64](n)
    let signed = bt.isSigned
    for i in 0 ..< n:
      xs[i] = if signed: readInt(part(i), sz, endian)
              else: cast[int64](readUint(part(i), sz, endian))
    some(RawValues(kind: rkInt, ints: xs))

# --- time

const fitEpoch* = 631_065_600'i64  ## 1989-12-31T00:00:00Z as unix time

func fitToUnix*(t: int64): int64 {.raises: [].} = t + fitEpoch

func fitToTime*(t: int64): Time {.raises: [].} = fromUnix(t + fitEpoch)

func expandTimestamp16*(t16: uint16, current: int64):
    tuple[time: int64, backwards: bool] {.raises: [].} =
  ## Full timestamp from the low 16 bits, given the latest full timestamp
  ## (FIT seconds).  A small backwards jump is treated as time moving back
  ## (`backwards` is set); otherwise we wrap forwards.
  let delta = int64(t16) - (current and 0xffff)
  if delta < 0 and abs(delta) < 0x8000:
    (current + delta, true)
  else:
    (current + (delta and 0xffff), false)

# --- file header

func u16le(data: openArray[byte], o: int): int =
  int(data[o]) or (int(data[o + 1]) shl 8)

func u32le(data: openArray[byte], o: int): int =
  u16le(data, o) or (u16le(data, o + 2) shl 16)

proc readHeader*(data: openArray[byte]): FileHeader {.raises: [FitError].} =
  ## Raises FitError only if the data is too short to hold a header; use
  ## `problems` to check consistency.
  if data.len < 12:
    raiseFit("too short for a FIT header (" & $data.len & " bytes)")
  result.size = int(data[0])
  result.protocolVersion = int(data[1])
  result.profileVersion = u16le(data, 2)
  result.dataSize = u32le(data, 4)
  for i in 8 ..< 12: result.dataType.add char(data[i])
  if result.size >= 14 and data.len >= 14:
    let c = uint16(u16le(data, 12))
    if c != 0: result.checksum = some(c)

func problems*(h: FileHeader, data: openArray[byte]): seq[string] =
  ## Inconsistencies in the header and the file checksums (empty if ok).
  if h.size < 12:
    result.add "Header size too small (" & $h.size & ")"
  elif h.size notin [12, 14]:
    result.add "Header size not standard (" & $h.size & "/12-14)"
  let expected = h.dataSize + h.size + 2
  if data.len != expected:
    result.add "Data size incorrect (" & $data.len & "/" & $h.dataSize & "+" &
      $h.size & "+2=" & $expected & ")"
  if h.dataType != ".FIT":
    result.add "Data type incorrect (" & escape(h.dataType) & ")"
  if h.checksum.isSome and data.len >= 12:
    let c = crc16(data.toOpenArray(0, 11))
    if c != h.checksum.get:
      result.add "Inconsistent header checksum (" & toHex(c, 4) & "/" &
        toHex(h.checksum.get, 4) & ")"
  if data.len >= 2:
    let stored = uint16(u16le(data, data.len - 2))
    let c = crc16(data.toOpenArray(0, data.len - 3))
    if c != stored:
      result.add "Bad file checksum (" & toHex(c, 4) & "/" & toHex(stored, 4) & ")"
