## Message decoding: turns data tokens into records of named, scaled values.
##
## Values stay numeric (an enum value is its integer, tagged with its profile
## type name; use `valueName` to get the profile name).  Bad (invalid) fields
## are left out of the record.  Composite fields are expanded into their
## components, dynamic fields are resolved to the matching subfield, and
## accumulated fields are tracked across messages.  Developer fields are
## registered from `field_description` records as they are decoded, so
## records must be decoded in file order (use `Reader`).
##
## Nothing here raises for odd data; diagnostics go to `warnings`.

import std/[options, tables]
import ./binary
import ./lookup
import ./profile
import ./tokens

const
  fieldDescriptionNum* = 206  ## global message number of field_description

type
  ValueKind* = enum vkInt, vkFloat, vkString

  FieldValue* = object
    name*: string       ## "" if the field is not in the profile
    number*: int        ## field number (components: the target's; -1 if none)
    units*: string
    typeName*: string   ## profile type (mapping, date_time, bool...) or base type
    dev*: bool          ## developer field
    bits*: int          ## width in bits of the source it was decoded from
    case kind*: ValueKind
    of vkInt: ints*: seq[int64]
    of vkFloat: floats*: seq[float]
    of vkString: strings*: seq[string]

  Record* = object
    name*: string       ## "" if the message is not in the profile
    number*: int        ## global message number
    local*: int         ## local message type
    defn*: int          ## index into Tokenizer.defs
    timestamp*: Option[int64]  ## FIT seconds
    fields*: seq[FieldValue]

  TypeInfo = tuple[kind: TypeKind, base: BaseType]

  Slot = object
    def: FieldDef
    field: Option[Field]

  DefPlan = object
    ready: bool
    msg: Message          ## empty if the message is unknown
    slots: seq[Slot]

  DevField = object
    name, units: string
    base: BaseType
    scale, offset: float

  Decoder* = object
    warnings*: seq[Warning]
    types: Table[string, TypeInfo]
    plans: seq[DefPlan]                   ## indexed like Tokenizer.defs
    accum: Table[(int, string), uint64]   ## (message number, field name) -> total
    devFields: Table[(int, int), DevField]

  Reader* = object
    tokenizer*: Tokenizer
    decoder*: Decoder
    started: bool

  # per-record context
  RecCtx = object
    msgNum: int
    offset: int                  ## file offset of the data message
    ts: Option[int64]
    refs: Table[string, int64]   ## first value of fields decoded so far, by name

  # set by an enclosing component
  Override = object
    scale, offset: Option[float]
    acc: int                     ## accumulator width in bits (0 = none)
    bits: int                    ## width of the outermost component (0 = none)
    depth: int

  Spec = object
    name, units, typeName: string
    number: int
    kind: TypeKind
    base: BaseType
    scale, offset: float
    acc: int
    bits: int
    check, dev: bool

type
  EventKind* = enum evDefinition, evRecord

  DefField* = tuple[name: string, count: int]  ## name "" if unknown

  Event* = object
    ## A definition or a decoded data message, in file order.
    offset*: int
    case kind*: EventKind
    of evDefinition:
      local*: int
      message*: string    ## "" if unknown
      number*: int        ## global message number
      fields*: seq[DefField]
    of evRecord:
      record*: Record

const maxDepth = 8

proc initDecoder*(p: Profile): Decoder =
  for name, t in p.types:
    result.types[name] = (t.kind, t.base)

proc warn(d: var Decoder, offset: int, msg: string) =
  d.warnings.add (offset, msg)

func isBadInt(bt: BaseType, v: int64): bool =
  let sz = bt.size
  let mask = if sz >= 8: high(uint64) else: (1'u64 shl (8 * sz)) - 1
  (cast[uint64](v) and mask) == invalid(bt)

func getBits(data: openArray[byte], endian: Endianness,
             start, count: int): uint64 =
  ## `count` (at most 64) bits of the integer that `data` represents, starting
  ## `start` bits up from the least significant end.  Bits beyond the data
  ## are zero.
  for k in 0 ..< count:
    let bit = start + k
    let bi = bit div 8
    if bi >= data.len: break
    let at = if endian == littleEndian: bi else: data.len - 1 - bi
    if ((data[at] shr (bit mod 8)) and 1) != 0:
      result = result or (1'u64 shl k)

func leBytes(v: uint64): array[8, byte] =
  for i in 0 ..< 8: result[i] = byte((v shr (8 * i)) and 0xff)

# --- one value

proc interpret(d: var Decoder, sp: Spec, data: openArray[byte],
               endian: Endianness, ctx: RecCtx): Option[FieldValue] =
  ## Decode `data` as described by `sp`: bad check, accumulation and scaling.
  template mk(k: ValueKind): FieldValue =
    FieldValue(kind: k, name: sp.name, number: sp.number, units: sp.units,
               typeName: sp.typeName, dev: sp.dev, bits: sp.bits)
  if sp.kind == tkBool:
    var fv = mk(vkInt)
    for x in data: fv.ints.add(if x != 0: 1'i64 else: 0'i64)
    return some(fv)
  let raw = binary.decode(sp.base, data, endian, sp.check)
  if raw.isNone: return none(FieldValue)
  let r = raw.get
  let identity = (sp.scale == 1 and sp.offset == 0) or sp.base == btEnum
  case r.kind
  of rkString:
    var fv = mk(vkString)
    fv.strings = r.strings
    some(fv)
  of rkFloat:
    var fv = mk(vkFloat)
    for x in r.floats:
      fv.floats.add(if identity: x else: x / sp.scale - sp.offset)
    some(fv)
  of rkInt:
    var vals = r.ints
    if sp.acc > 0:
      if vals.len == 1:
        let mask = if sp.acc >= 64: high(uint64) else: (1'u64 shl sp.acc) - 1
        let low = cast[uint64](vals[0]) and mask
        let key = (ctx.msgNum, sp.name)
        var total = low
        if key in d.accum:
          let prev = d.accum.must(key)
          total = (prev and not mask) or low
          if low < (prev and mask) and sp.acc < 64: total += mask + 1
        d.accum[key] = total
        vals = @[cast[int64](total)]
      else:
        d.warn(ctx.offset, "cannot accumulate " & $vals.len & " values of " & sp.name)
    if identity:
      var fv = mk(vkInt)
      fv.ints = vals
      some(fv)
    else:
      var fv = mk(vkFloat)
      for v in vals:
        # isolated bad values in arrays stay unscaled (as the SDK CSV does)
        if vals.len > 1 and isBadInt(sp.base, v): fv.floats.add float(v)
        else: fv.floats.add float(v) / sp.scale - sp.offset
      some(fv)

# --- one profile field

proc addMerging(fs: var seq[FieldValue], v: FieldValue) =
  ## Add `v`.  A composite can give several values for one name (eg the eight
  ## event_timestamps of hr.event_timestamp_12): they become one array.
  if v.name.len > 0:
    for f in fs.mitems:
      if f.name == v.name and f.kind == v.kind:
        case v.kind
        of vkInt: f.ints.add v.ints
        of vkFloat: f.floats.add v.floats
        of vkString: f.strings.add v.strings
        return
  fs.add v

proc decodeField(d: var Decoder, msg: Message, f: Field, number: int,
                 defBase: Option[BaseType], data: openArray[byte],
                 endian: Endianness, ctx: RecCtx, ov: Override,
                 fromBits: bool): seq[FieldValue] =
  ## Decode `data` as profile field `f`.  `fromBits` means `data` is the
  ## little-endian image of a component's bits (so only the leading bytes
  ## that fit the field's type are meaningful, and nothing is bad).
  if ov.depth > maxDepth:
    d.warn(ctx.offset, "field nesting too deep at " & f.name)
    return
  let ti = d.types.must(f.typeName)
  let base = if defBase.isSome: defBase.get else: ti.base
  case f.kind
  of fkComposite:
    let n = if fromBits: min(base.size, 8) else: data.len
    if n < 1 or n > data.len:
      d.warn(ctx.offset, "cannot expand composite field " & f.name &
             " of " & $data.len & " bytes")
      return
    if not fromBits and isBad(base, data, endian): return
    var start = 0
    for c in f.components:
      # components that do not fit in the data are ignored (the profile has
      # more of them than a field can hold, eg hr.event_timestamp_12)
      if c.bits > 64 or start + c.bits > 8 * n: break
      if c.target notin msg.fields:
        d.warn(ctx.offset, "composite " & f.name & ": no field " & c.target)
        start += c.bits
        continue
      let v = getBits(data.toOpenArray(0, n - 1), endian, start, c.bits)
      start += c.bits
      let le = leBytes(v)
      # the outermost component's scale and offset win
      let ov2 = Override(
        scale: (if ov.scale.isSome: ov.scale else: some(c.scale)),
        offset: (if ov.offset.isSome: ov.offset else: some(c.offset)),
        acc: (if ov.acc > 0: ov.acc elif c.accumulate: c.bits else: 0),
        bits: (if ov.bits > 0: ov.bits else: c.bits),
        depth: ov.depth + 1)
      let tnum = if msg.fields.must(c.target).number.isSome:
                   msg.fields.must(c.target).number.get else: -1
      for v in d.decodeField(msg, msg.fields.must(c.target), tnum, none(BaseType),
                             le, littleEndian, ctx, ov2, true):
        result.addMerging v
    return
  of fkDynamic:
    var target = ""
    for refName in f.refs:
      if refName in ctx.refs:
        let rv = ctx.refs.must(refName)
        for c in f.choices:
          if c.refField == refName and c.refValue == rv:
            target = c.target
            break
      if target.len > 0: break
    if target.len > 0 and target in msg.fields:
      let ov2 = Override(scale: ov.scale, offset: ov.offset, acc: ov.acc,
                         bits: (if ov.bits > 0: ov.bits else: 8 * data.len),
                         depth: ov.depth + 1)
      if fromBits:
        return d.decodeField(msg, msg.fields.must(target), number, none(BaseType),
                             data, endian, ctx, ov2, true)
      # as choochoo: the element count comes from the definition's base type,
      # the element type from the subfield
      let sbase = d.types.must(msg.fields.must(target).typeName).base
      let count = if defBase.isSome: data.len div defBase.get.size else: 1
      let take = min(data.len, count * sbase.size)
      return d.decodeField(msg, msg.fields.must(target), number, some(sbase),
                           data.toOpenArray(0, take - 1), endian, ctx, ov2,
                           false)
    # no match: the field itself
  of fkPlain: discard
  let sp = Spec(
    name: f.name, units: f.units, typeName: f.typeName, number: number,
    kind: ti.kind, base: base,
    scale: (if ov.scale.isSome: ov.scale.get else: f.scale),
    offset: (if ov.offset.isSome: ov.offset.get else: f.offset),
    acc: (if ov.acc > 0: ov.acc elif f.accumulate: 8 * base.size else: 0),
    bits: (if ov.bits > 0: ov.bits else: 8 * data.len),
    check: not fromBits, dev: false)
  let v =
    if fromBits:
      d.interpret(sp, data.toOpenArray(0, min(base.size, data.len) - 1),
                  littleEndian, ctx)
    else:
      d.interpret(sp, data, endian, ctx)
  if v.isSome: result.add v.get

# --- plans

proc buildPlan(d: var Decoder, p: Profile, def: Definition): DefPlan =
  result.ready = true
  let mname = p.byNumber.getOrDefault(def.globalNum, "")
  if mname.len > 0 and mname in p.messages:
    result.msg = p.messages.must(mname)
  for fd in def.fields:
    var s = Slot(def: fd)
    if fd.number in result.msg.byNumber:
      let fname = result.msg.byNumber.must(fd.number)
      if fname in result.msg.fields:
        s.field = some(result.msg.fields.must(fname))
    result.slots.add s

# --- developer fields

func intOf(r: Record, name: string): Option[int64] =
  for f in r.fields:
    if f.name == name and f.kind == vkInt and f.ints.len > 0:
      return some(f.ints[0])

func strOf(r: Record, name: string): string =
  for f in r.fields:
    if f.name == name and f.kind == vkString and f.strings.len > 0:
      return f.strings[0]

proc registerDev(d: var Decoder, r: Record, offset: int) =
  ## From a field_description record.
  let idx = r.intOf("developer_data_index")
  let num = r.intOf("field_definition_number")
  let bid = r.intOf("fit_base_type_id")
  if idx.isNone or num.isNone or bid.isNone:
    d.warn(offset, "incomplete field_description")
    return
  let base = baseTypeOf(byte(bid.get and 0xff))
  if base.isNone:
    d.warn(offset, "field_description: unknown base type " & $bid.get)
    return
  var scale = 1.0
  let sc = r.intOf("scale")
  if sc.isSome and sc.get > 0: scale = float(sc.get)
  let off = r.intOf("offset")
  d.devFields[(int(idx.get), int(num.get))] = DevField(
    name: r.strOf("field_name"), units: r.strOf("units"), base: base.get,
    scale: scale, offset: (if off.isSome: float(off.get) else: 0.0))

# --- records

proc decode*(d: var Decoder, p: Profile, t: Tokenizer,
             tok: Token): Record {.raises: [].} =
  ## Decode a data token (other tokens give an empty record).  Must be called
  ## in file order.  Odd data adds to `d.warnings`; nothing is raised (a broken
  ## internal invariant is a bug, and an AssertionDefect).
  if tok.kind != tokData: return
  let idx = tok.defn
  if d.plans.len <= idx: d.plans.setLen(idx + 1)
  if not d.plans[idx].ready: d.plans[idx] = d.buildPlan(p, t.defs[idx])
  let globalNum = t.defs[idx].globalNum
  let endian = t.defs[idx].endian
  result = Record(name: d.plans[idx].msg.name, number: globalNum,
                  local: t.defs[idx].local, defn: idx,
                  timestamp: tok.timestamp)
  var ctx = RecCtx(msgNum: globalNum, offset: tok.offset, ts: tok.timestamp)
  let n = d.plans[idx].slots.len
  var groups = newSeq[seq[FieldValue]](n)

  template noteRefs(vs: seq[FieldValue]) =
    for v in vs:
      if v.name.len > 0 and v.kind == vkInt and v.ints.len > 0:
        ctx.refs[v.name] = v.ints[0]

  template slotData(i: int): untyped =
    t.data.toOpenArray(tok.offset + d.plans[idx].slots[i].def.offset,
                       tok.offset + d.plans[idx].slots[i].def.offset +
                       d.plans[idx].slots[i].def.size - 1)

  # pass 1: plain and unknown fields, then composites, then dynamic fields,
  # so that references are available when needed
  for i in 0 ..< n:
    let fd = d.plans[idx].slots[i].def
    if d.plans[idx].slots[i].field.isNone:
      if fd.base.isNone: continue
      let sp = Spec(name: "", typeName: $fd.base.get, number: fd.number,
                    kind: tkBase, base: fd.base.get, scale: 1, offset: 0,
                    bits: 8 * fd.size, check: true)
      let v = d.interpret(sp, slotData(i), endian, ctx)
      if v.isSome: groups[i] = @[v.get]
    elif d.plans[idx].slots[i].field.get.kind == fkPlain:
      groups[i] = d.decodeField(d.plans[idx].msg, d.plans[idx].slots[i].field.get,
                                fd.number, fd.base, slotData(i), endian, ctx,
                                Override(), false)
      noteRefs(groups[i])
  for pass in [fkComposite, fkDynamic]:
    for i in 0 ..< n:
      if d.plans[idx].slots[i].field.isSome and
          d.plans[idx].slots[i].field.get.kind == pass:
        let fd = d.plans[idx].slots[i].def
        groups[i] = d.decodeField(d.plans[idx].msg,
                                  d.plans[idx].slots[i].field.get, fd.number,
                                  fd.base, slotData(i), endian, ctx, Override(),
                                  false)
        noteRefs(groups[i])

  # a compressed timestamp header with no timestamp field in the definition
  if tok.compressed and t.defs[idx].timestampField < 0 and tok.timestamp.isSome:
    result.fields.add FieldValue(kind: vkInt, name: "timestamp",
                                 number: timestampFieldNo, units: "s",
                                 typeName: "date_time", bits: 32,
                                 ints: @[tok.timestamp.get])
  for g in groups: result.fields.add g
  # one entry per name: keep the one decoded from the widest source (the most
  # precise; eg `data` over the narrower `data16`), the first on a tie
  var best: Table[string, int]
  for i, f in result.fields:
    if f.name.len == 0: continue
    if f.name notin best or f.bits > result.fields[best.must(f.name)].bits:
      best[f.name] = i
  var kept: seq[FieldValue]
  for i, f in result.fields:
    if f.name.len == 0 or best.must(f.name) == i: kept.add f
  result.fields = kept

  for dv in t.defs[idx].devFields:
    let key = (dv.devIndex, dv.number)
    let at = tok.offset + dv.offset
    if key notin d.devFields:
      d.warn(at, "no description for developer field " & $dv.number &
             " of developer " & $dv.devIndex)
      continue
    let df = d.devFields.must(key)
    let sp = Spec(name: df.name, units: df.units, typeName: $df.base,
                  number: dv.number, kind: tkBase, base: df.base,
                  scale: df.scale, offset: df.offset, bits: 8 * dv.size,
                  check: true, dev: true)
    let v = d.interpret(sp, t.data.toOpenArray(at, at + dv.size - 1), endian, ctx)
    if v.isSome: result.fields.add v.get

  if globalNum == fieldDescriptionNum:
    d.registerDev(result, tok.offset)

# --- reading whole files

proc initReader*(p: Profile, data: sink seq[byte]): Reader =
  Reader(tokenizer: initTokenizer(data, p.timestamp16Fields),
         decoder: initDecoder(p))

func warnings*(r: Reader): seq[Warning] =
  ## Tokenizer warnings followed by decoder warnings.
  r.tokenizer.warnings & r.decoder.warnings

proc definitionEvent(d: var Decoder, p: Profile, t: Tokenizer,
                     tok: Token): Event {.raises: [].} =
  ## Event for a definition token.  Developer field names are those described
  ## so far, so this must be called in file order.
  let idx = tok.defn
  if d.plans.len <= idx: d.plans.setLen(idx + 1)
  if not d.plans[idx].ready: d.plans[idx] = d.buildPlan(p, t.defs[idx])
  result = Event(kind: evDefinition, offset: tok.offset,
                 local: t.defs[idx].local, number: t.defs[idx].globalNum,
                 message: d.plans[idx].msg.name)
  for s in d.plans[idx].slots:
    let name = if s.field.isSome: s.field.get.name else: ""
    let sz = if s.def.base.isSome: s.def.base.get.size else: 1
    result.fields.add (name, s.def.size div sz)
  for dv in t.defs[idx].devFields:
    let key = (dv.devIndex, dv.number)
    if key in d.devFields:
      let df = d.devFields.must(key)
      result.fields.add (df.name, dv.size div df.base.size)
    else:
      result.fields.add ("", dv.size)

iterator events*(r: var Reader, p: Profile): Event {.raises: [FitError].} =
  ## Every definition and data message in the file, in order.  Raises
  ## FitError as the tokenizer does (events before the error have already been
  ## yielded).
  while true:
    let tok = r.tokenizer.next()
    if tok.isNone: break
    case tok.get.kind
    of tokHeader:
      if r.started:  # chained file: accumulators and developer fields restart
        r.decoder.accum.clear()
        r.decoder.devFields.clear()
      r.started = true
    of tokDefinition:
      yield r.decoder.definitionEvent(p, r.tokenizer, tok.get)
    of tokData:
      yield Event(kind: evRecord, offset: tok.get.offset,
                  record: r.decoder.decode(p, r.tokenizer, tok.get))
    else: discard

iterator records*(r: var Reader, p: Profile): Record {.raises: [FitError].} =
  ## Every data message in the file, in order (see `events`).
  for ev in r.events(p):
    if ev.kind == evRecord: yield ev.record

# --- access

func field*(r: Record, name: string): Option[FieldValue] =
  ## The first field called `name`.
  for f in r.fields:
    if f.name == name: return some(f)

func valueName*(p: Profile, f: FieldValue, i = 0): string {.raises: [].} =
  ## Profile name of an enumerated value, else the value as text.
  case f.kind
  of vkInt:
    if i >= f.ints.len: return ""
    let v = f.ints[i]
    if f.typeName in p.types and p.types.must(f.typeName).kind == tkMapping and
        v in p.types.must(f.typeName).toName:
      return p.types.must(f.typeName).toName.must(v)
    $v
  of vkFloat:
    if i >= f.floats.len: "" else: $f.floats[i]
  of vkString:
    if i >= f.strings.len: "" else: f.strings[i]
