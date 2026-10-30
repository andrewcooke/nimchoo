## FIT tokenizer: splits a file into header, definition, data and checksum
## tokens, tracking the state needed to do so (active definitions, current
## timestamp).  Decoding field values is a later step.
##
## Tokens are small values (a byte range plus an index into `Tokenizer.defs`).
## Errors that stop tokenizing raise `FitError` (with the byte offset);
## everything else is recorded in `Tokenizer.warnings`.

import std/[options, sets]
import ../errors
import ./basetype
import ./bytes
import ./header
import ./time
import ../warnings
export warnings

{.push raises: [].}

const
  timestampFieldNo* = 253  ## global field number of `timestamp`

type
  FieldDef* = object
    number*, size*: int
    base*: Option[BaseType]  ## none if the base type byte is unknown
    offset*: int             ## from start of the data message (header = 0)

  DevFieldDef* = object
    number*, size*, devIndex*, offset*: int

  Definition* = object
    local*: int              ## local message type (0-15)
    endian*: Endianness
    globalNum*: int
    fields*: seq[FieldDef]
    devFields*: seq[DevFieldDef]
    size*: int               ## bytes per data message, header included
    timestampField*: int     ## index into fields (253 or timestamp_16), or -1

  TokenKind* = enum tokHeader, tokDefinition, tokData, tokChecksum

  Token* = object
    offset*, len*: int       ## byte range in the file
    case kind*: TokenKind
    of tokHeader:
      header*: FileHeader
    of tokDefinition, tokData:
      defn*: int                 ## index into Tokenizer.defs
      timestamp*: Option[int64]  ## (data) current FIT time after this message
      compressed*: bool          ## (data) compressed timestamp header
    of tokChecksum:
      checksum*: uint16

  Phase = enum phHeader, phRecords, phDone

  Tokenizer* = object
    data*: seq[byte]
    defs*: seq[Definition]      ## every definition seen, in order
    warnings*: seq[Warning]
    ts16: HashSet[(int, int)]   ## (message number, field number) of timestamp_16
    phase: Phase
    pos, dataEnd, fileEnd: int
    active: array[16, int]      ## local type -> index into defs, or -1
    timestamp: Option[int64]

proc initTokenizer*(data: sink seq[byte],
                    ts16: HashSet[(int, int)]): Tokenizer =
  ## `ts16` is `timestamp16Fields(profile)` (or empty if not needed).
  result = Tokenizer(data: data, ts16: ts16, phase: phHeader)
  for i in 0 ..< 16: result.active[i] = -1

proc fail(offset: int, msg: string) {.noreturn, raises: [FitError].} =
  raiseFit(offset, msg)

func bytes*(t: Tokenizer, tok: Token): seq[byte] =
  ## Copy of the bytes covered by `tok`.
  t.data[tok.offset ..< tok.offset + tok.len]

const fitTag = [byte('.'), byte('F'), byte('I'), byte('T')]

func hasFitTag(t: Tokenizer, pos: int): bool =
  pos + 12 <= t.data.len and t.data.toOpenArray(pos + 8, pos + 11) == fitTag

proc readFileHeader(t: var Tokenizer): Token {.raises: [FitError].} =
  let start = t.pos
  var h: FileHeader
  try:
    h = readHeader(t.data.toOpenArray(start, t.data.high))
  except FitError as e:
    fail(start, e.msg)
  if h.size < 12:
    fail(start, "header size too small (" & $h.size & ")")
  let fileEnd = start + h.size + h.dataSize + 2
  if h.dataSize > 0 and fileEnd <= t.data.len:
    t.dataEnd = fileEnd - 2
    t.fileEnd = fileEnd
  else:
    if t.data.len - start < h.size + 2:
      fail(start, "file too short for header and checksum")
    t.dataEnd = t.data.len - 2
    t.fileEnd = t.data.len
    t.warnings.add wkDataSizeIgnored, start, "header data size ignored; reading to end of file"
  for w in problems(h, t.data.toOpenArray(start, t.fileEnd - 1)):
    t.warnings.add w.kind, start, w.msg
  t.pos = start + h.size
  t.phase = phRecords
  for i in 0 ..< 16: t.active[i] = -1  # definitions do not carry over
  Token(kind: tokHeader, offset: start, len: h.size, header: h)

proc readChecksum(t: var Tokenizer): Token =
  let pos = t.pos
  let c = uint16(getUint(t.data, pos, 2))
  t.pos = pos + 2
  let remaining = t.data.len - t.pos
  if remaining == 0:
    t.phase = phDone
  elif remaining >= 12 and t.hasFitTag(t.pos):
    t.phase = phHeader  # chained file
  else:
    t.warnings.add wkTrailingBytes, t.pos, $remaining & " trailing bytes ignored"
    t.phase = phDone
  Token(kind: tokChecksum, offset: pos, len: 2, checksum: c)

proc readDefinition(t: var Tokenizer): Token {.raises: [FitError].} =
  let pos = t.pos
  let h0 = t.data[pos]
  let hasDev = (h0 and 0x20) != 0
  if pos + 6 > t.dataEnd: fail(pos, "truncated definition")
  let endian = if (t.data[pos + 2] and 1) == 1: bigEndian else: littleEndian
  let globalNum = int(getUint(t.data, pos + 3, 2, endian))
  let n = int(t.data[pos + 5])
  var p = pos + 6 + 3 * n  # start of dev field count, or end if none
  if p > t.dataEnd: fail(pos, "truncated definition")
  var m = 0
  if hasDev:
    if p + 1 > t.dataEnd: fail(pos, "truncated definition")
    m = int(t.data[p])
    inc p
  if p + 3 * m > t.dataEnd: fail(pos, "truncated definition")
  var d = Definition(local: int(h0 and 0x0f), endian: endian,
                     globalNum: globalNum, timestampField: -1)
  var offset = 1  # the header byte
  for i in 0 ..< n:
    let q = pos + 6 + 3 * i
    let number = int(t.data[q])
    let size = int(t.data[q + 1])
    let base = baseTypeOf(t.data[q + 2])
    if base.isNone:
      t.warnings.add wkUnknownBaseType, q, "unknown base type " & $t.data[q + 2] & " for field " & $number
    if d.timestampField < 0 and
        (number == timestampFieldNo or (globalNum, number) in t.ts16):
      d.timestampField = i
    d.fields.add FieldDef(number: number, size: size, base: base, offset: offset)
    offset += size
  for j in 0 ..< m:
    let q = p + 3 * j
    let size = int(t.data[q + 1])
    d.devFields.add DevFieldDef(number: int(t.data[q]), size: size,
                                devIndex: int(t.data[q + 2]), offset: offset)
    offset += size
  d.size = offset
  t.defs.add d
  t.active[d.local] = t.defs.high
  Token(kind: tokDefinition, offset: pos, len: p + 3 * m - pos,
        defn: t.defs.high)

proc updateTimestamp(t: var Tokenizer, idx, pos: int) =
  ## Update the current time from the timestamp field of data message `idx`
  ## starting at `pos`.
  let tf = t.defs[idx].timestampField
  if tf < 0: return
  let f = t.defs[idx].fields[tf]
  let endian = t.defs[idx].endian
  let at = pos + f.offset
  if f.number == timestampFieldNo:
    if f.size != 4:
      t.warnings.add wkTimestampSize, at, "timestamp field has size " & $f.size
      return
    t.timestamp = some(int64(getUint(t.data, at, 4, endian)))
  else:
    if f.size != 2:
      t.warnings.add wkTimestamp16Size, at, "timestamp_16 field has size " & $f.size
      return
    if t.timestamp.isNone:
      t.warnings.add wkTimestamp16NoBase, at, "timestamp_16 with no preceding timestamp"
      return
    let t16 = uint16(getUint(t.data, at, 2, endian))
    let r = expandTimestamp16(t16, t.timestamp.get)
    if r.backwards: t.warnings.add wkTimestamp16Backwards, at, "timestamp_16 moved back in time"
    t.timestamp = some(r.time)

proc readData(t: var Tokenizer, local: int,
              compressed: bool): Token {.raises: [FitError].} =
  let pos = t.pos
  let idx = t.active[local]
  if idx < 0:
    fail(pos, "no definition for local message type " & $local)
  let size = t.defs[idx].size
  if pos + size > t.dataEnd:
    fail(pos, "truncated data message (" & $(t.dataEnd - pos) & "/" & $size &
         " bytes)")
  if compressed:
    if t.timestamp.isNone:
      fail(pos, "compressed timestamp with no preceding timestamp")
    let ts = t.timestamp.get
    let delta = int64(t.data[pos] and 0x1f)
    let rollover = delta < (ts and 0x1f)
    t.timestamp = some((ts and not 0x1f'i64) + delta + (if rollover: 0x20 else: 0))
  t.updateTimestamp(idx, pos)
  Token(kind: tokData, offset: pos, len: size, defn: idx,
        timestamp: t.timestamp, compressed: compressed)

proc readRecord(t: var Tokenizer): Token {.raises: [FitError].} =
  let h0 = t.data[t.pos]
  if (h0 and 0x80) != 0:
    result = t.readData(int((h0 shr 5) and 0x03), true)
  elif (h0 and 0x40) != 0:
    result = t.readDefinition()
  else:
    if (h0 and 0x10) != 0: t.warnings.add wkReservedBit, t.pos, "reserved bit set in record header"
    result = t.readData(int(h0 and 0x0f), false)
  t.pos += result.len

proc next*(t: var Tokenizer): Option[Token] {.raises: [FitError].} =
  ## The next token, or none at the end of the data.
  case t.phase
  of phDone: none(Token)
  of phHeader: some(t.readFileHeader())
  of phRecords:
    if t.pos >= t.dataEnd: some(t.readChecksum())
    else: some(t.readRecord())

iterator tokens*(t: var Tokenizer): Token {.raises: [FitError].} =
  while true:
    let tok = t.next()
    if tok.isNone: break
    yield tok.get
