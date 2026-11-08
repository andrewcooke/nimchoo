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
## Odd data does not raise: it adds to `warnings`.  (A broken internal
## invariant is a bug and an AssertionDefect, see lookup.nim.)

import std/[options, tables]
import ../lookup
import ../profile/model
import ../warnings
import ./basetype
import ./bytes
import ./records
import ./tokens

{.push raises: [].}

const fieldDescriptionNum* = 206 ## global message number of field_description

type
  TypeInfo = tuple[kind: TypeKind, base: BaseType]

  Slot = object
    def: FieldDef
    known: bool ## the profile has a field with this number in this message
    fieldName: string
    kind: FieldKind ## plain, composite or dynamic (plain if not known)
    scale, offset: float
    accumulate: bool
    meta: Meta ## what its values have in common (made once, shared)

  DefPlan = object
    ready: bool
    msgName: string ## "" if the message is unknown
    msgNum: int
    slots: seq[Slot]
    hasDynamic: bool
      ## a field of the definition is dynamic: values refer to other values of the record
    mayDup: bool
      ## two values may have one name (composites, dynamic fields, a repeated field number)

  DevField = object
    name, units: string
    base: BaseType
    scale, offset: float
    meta: Meta

  Decoder* = object
    warnings*: seq[Warning]
    types: Table[string, TypeInfo]
    plans: seq[DefPlan] ## indexed like Tokenizer.defs
    metas: Table[(int, string), Meta]
      ## (message number, field name) -> its shared description
    accum: Table[(int, string), uint64] ## (message number, field name) -> total
    devFields: Table[(int, int), DevField]

  # per-record context
  RecCtx = object
    msgNum: int
    offset: int ## file offset of the data message
    ts: Option[FitTime]
    refs: Table[string, int64]
      ## first value of fields decoded so far, by name (only for dynamic fields)

  # set by an enclosing component
  Override = object
    scale, offset: Option[float]
    acc: int ## accumulator width in bits (0 = none)
    bits: int ## width of the outermost component (0 = none)
    depth: int

  Spec = object
    meta: Meta
    number: int
    kind: TypeKind
    base: BaseType
    scale, offset: float
    acc: int
    bits: int
    check, dev: bool

const maxDepth = 8

proc initDecoder*(p: Profile): Decoder =
  for name, t in p.types:
    result.types[name] = (t.kind, t.base)

func leBytes(v: uint64): array[8, byte] =
  for i in 0 ..< 8:
    result[i] = byte((v shr (8 * i)) and 0xff)

# --- one value

{.push floatChecks: off.}
func scaled(x, scale, offset: float): Option[float] =
  ## `x / scale - offset`, or none if that is not a finite number (with float
  ## checks off here, so that it is the same with them on or off elsewhere).
  let y = x / scale - offset
  if y == y and y - y == 0.0: # not NaN, not infinite
    some(y)
  else:
    none(float)
{.pop.}

proc interpret(
    d: var Decoder,
    sp: Spec,
    data: openArray[byte],
    endian: Endianness,
    ctx: RecCtx,
    into: var seq[FieldValue],
) =
  ## Decode `data` as described by `sp`: bad check, accumulation and scaling.  The value, if
  ## there is one, is added to `into`.  (The numbers are read straight into the value: this runs
  ## for every field of every message, millions of times in a library.)
  template mk(k: ValueKind): FieldValue =
    FieldValue(kind: k, meta: sp.meta, number: sp.number, dev: sp.dev, bits: sp.bits)

  if sp.base == btString:
    var fv = mk(vkString)
    fv.strings = decodeString(data)
    into.add move(fv)
    return
  if sp.check and isBad(sp.base, data, endian):
    return
  let n = data.len div sp.base.size
  if sp.kind == tkBool:
    # true for any value that is not 0, except the marker, which (as for numbers, in an array) stays as it is
    var fv = mk(vkInt)
    fv.ints = newSeq[int64](n)
    for i in 0 ..< n:
      let v = readInt(sp.base, data, i, endian)
      fv.ints[i] =
        if elementKind(sp.base, data, i, endian) == ekBad:
          v
        elif v != 0:
          1'i64
        else:
          0'i64
    into.add move(fv)
    return
  let identity = (sp.scale == 1 and sp.offset == 0) or sp.base == btEnum
  if sp.base in {btFloat32, btFloat64}:
    # a float that is not finite is not a measurement: the field is left out
    # (the marker silently, any other NaN or infinity with a warning)
    var fv = mk(vkFloat)
    fv.floats = newSeq[float](n)
    var left, odd = false
    for i in 0 ..< n:
      case elementKind(sp.base, data, i, endian)
      of ekValue:
        let x = readFloat(sp.base, data, i, endian)
        let y = if identity: some(x) else: scaled(x, sp.scale, sp.offset)
        if y.isSome:
          fv.floats[i] = y.get
        else:
          left = true
          odd = true
      of ekBad:
        left = true
      of ekNonFinite:
        left = true
        odd = true
    if odd:
      d.warnings.add wkNonFiniteFloat,
        ctx.offset, "a NaN or infinite value in " & sp.meta.name & " (field left out)"
    if not left:
      into.add move(fv)
    return
  if sp.acc > 0:
    # an accumulated field: its running total is kept (rare)
    var vals = newSeq[int64](n)
    for i in 0 ..< n:
      vals[i] = readInt(sp.base, data, i, endian)
    if vals.len == 1:
      let mask =
        if sp.acc >= 64:
          high(uint64)
        else:
          (1'u64 shl sp.acc) - 1
      let low = cast[uint64](vals[0]) and mask
      let key = (ctx.msgNum, sp.meta.name)
      var total = low
      if key in d.accum:
        let prev = d.accum.must(key)
        total = (prev and not mask) or low
        if low < (prev and mask) and sp.acc < 64:
          total += mask + 1
      d.accum[key] = total
      vals = @[cast[int64](total)]
    else:
      d.warnings.add wkCannotAccumulate,
        ctx.offset, "cannot accumulate " & $vals.len & " values of " & sp.meta.name
    if identity:
      var fv = mk(vkInt)
      fv.ints = move(vals)
      into.add move(fv)
    else:
      var fv = mk(vkFloat)
      for i, v in vals:
        if vals.len > 1 and elementKind(sp.base, data, i, endian) == ekBad:
          fv.floats.add float(v)
        else:
          fv.floats.add float(v) / sp.scale - sp.offset
      into.add move(fv)
    return
  if identity:
    var fv = mk(vkInt)
    fv.ints = newSeq[int64](n)
    for i in 0 ..< n:
      fv.ints[i] = readInt(sp.base, data, i, endian)
    into.add move(fv)
  else:
    var fv = mk(vkFloat)
    fv.floats = newSeq[float](n)
    for i in 0 ..< n:
      let v = readInt(sp.base, data, i, endian)
      # isolated bad values in arrays stay unscaled (as the SDK CSV does)
      fv.floats[i] =
        if n > 1 and elementKind(sp.base, data, i, endian) == ekBad:
          float(v)
        else:
          float(v) / sp.scale - sp.offset
    into.add move(fv)

# --- one profile field

proc addMerging(fs: var seq[FieldValue], v: FieldValue) =
  ## Add `v`.  A composite can give several values for one name (eg the eight
  ## event_timestamps of hr.event_timestamp_12): they become one array.
  if v.name.len > 0:
    for f in fs.mitems:
      if f.name == v.name and f.kind == v.kind:
        case v.kind
        of vkInt:
          f.ints.add v.ints
        of vkFloat:
          f.floats.add v.floats
        of vkString:
          f.strings.add v.strings
        return
  fs.add v

proc metaFor(d: var Decoder, msgNum: int, f: Field): Meta =
  ## The shared description of a profile field (made the first time it is asked for).
  let key = (msgNum, f.name)
  if key notin d.metas:
    let ti = d.types.getOrDefault(f.typeName, (tkBase, btByte))
      # (a type the profile lacks is a bug, found when used)
    d.metas[key] = newMeta(f.name, f.units, f.typeName, ti.kind, ti.base)
  d.metas.must(key)

proc emitPlain(
    d: var Decoder,
    meta: Meta,
    scale, offset: float,
    accumulate: bool,
    number: int,
    defBase: Option[BaseType],
    data: openArray[byte],
    endian: Endianness,
    ctx: RecCtx,
    ov: Override,
    fromBits: bool,
    into: var seq[FieldValue],
) =
  ## Decode `data` as a plain field with the given scale and offset (an enclosing component's
  ## win), adding the value to `into`.
  let base = if defBase.isSome: defBase.get else: meta.base
  let sp = Spec(
    meta: meta,
    number: number,
    kind: meta.kind,
    base: base,
    scale: (if ov.scale.isSome: ov.scale.get else: scale),
    offset: (if ov.offset.isSome: ov.offset.get else: offset),
    acc: (if ov.acc > 0: ov.acc elif accumulate: 8 * base.size else: 0),
    bits: (if ov.bits > 0: ov.bits else: 8 * data.len),
    check: not fromBits,
    dev: false,
  )
  if fromBits:
    d.interpret(
      sp, data.toOpenArray(0, min(base.size, data.len) - 1), littleEndian, ctx, into
    )
  else:
    d.interpret(sp, data, endian, ctx, into)

proc decodeField(
    d: var Decoder,
    p: Profile,
    plan: DefPlan,
    f: Field,
    meta: Meta,
    number: int,
    defBase: Option[BaseType],
    data: openArray[byte],
    endian: Endianness,
    ctx: RecCtx,
    ov: Override,
    fromBits: bool,
    into: var seq[FieldValue],
) =
  ## Decode `data` as profile field `f` (`meta` is its shared description), adding the values
  ## to `into`.  `fromBits` means `data` is the little-endian image of a component's bits (so
  ## only the leading bytes that fit the field's type are meaningful, and nothing is bad).
  ## (Composite and dynamic fields look up their targets in the profile's message, here.)
  if ov.depth > maxDepth:
    d.warnings.add wkNestingTooDeep, ctx.offset, "field nesting too deep at " & f.name
    return
  let base = if defBase.isSome: defBase.get else: meta.base
  case f.kind
  of fkComposite:
    let n =
      if fromBits:
        min(base.size, 8)
      else:
        data.len
    if n < 1 or n > data.len:
      d.warnings.add wkCompositeSize,
        ctx.offset,
        "cannot expand composite field " & f.name & " of " & $data.len & " bytes"
      return
    if not fromBits and isBad(base, data, endian):
      return
    var start = 0
    var group: seq[FieldValue]
      # the values of this field only: those of one name are merged
    for c in f.components:
      # components that do not fit in the data are ignored (the profile has
      # more of them than a field can hold, eg hr.event_timestamp_12)
      if c.bits > 64 or start + c.bits > 8 * n:
        break
      if c.target notin p.messages.must(plan.msgName).fields:
        d.warnings.add wkCompositeTarget,
          ctx.offset, "composite " & f.name & ": no field " & c.target
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
        depth: ov.depth + 1,
      )
      let target {.cursor.} = p.messages.must(plan.msgName).fields.must(c.target)
        # (looked at, not copied)
      let tnum = if target.number.isSome: target.number.get else: -1
      var made: seq[FieldValue]
      d.decodeField(
        p,
        plan,
        target,
        d.metaFor(plan.msgNum, target),
        tnum,
        none(BaseType),
        le,
        littleEndian,
        ctx,
        ov2,
        true,
        made,
      )
      for v in made:
        group.addMerging v
    for v in group.mitems:
      into.add move(v)
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
      if target.len > 0:
        break
    if target.len > 0 and target in p.messages.must(plan.msgName).fields:
      let tf {.cursor.} = p.messages.must(plan.msgName).fields.must(target)
      let tmeta = d.metaFor(plan.msgNum, tf)
      let ov2 = Override(
        scale: ov.scale,
        offset: ov.offset,
        acc: ov.acc,
        bits: (if ov.bits > 0: ov.bits else: 8 * data.len),
        depth: ov.depth + 1,
      )
      if fromBits:
        d.decodeField(
          p, plan, tf, tmeta, number, none(BaseType), data, endian, ctx, ov2, true, into
        )
        return
      # as choochoo: the element count comes from the definition's base type,
      # the element type from the subfield
      let sbase = tmeta.base
      let count =
        if defBase.isSome:
          data.len div defBase.get.size
        else:
          1
      let take = min(data.len, count * sbase.size)
      d.decodeField(
        p,
        plan,
        tf,
        tmeta,
        number,
        some(sbase),
        data.toOpenArray(0, take - 1),
        endian,
        ctx,
        ov2,
        false,
        into,
      )
      return
    # no match: the field itself
  of fkPlain:
    discard
  d.emitPlain(
    meta, f.scale, f.offset, f.accumulate, number, defBase, data, endian, ctx, ov,
    fromBits, into,
  )

# --- plans

proc buildPlan(d: var Decoder, p: Profile, def: Definition): DefPlan =
  result.ready = true
  result.msgNum = def.globalNum
  let mname = p.byNumber.getOrDefault(def.globalNum, "")
  var numbers: seq[int]
  p.messages.withValue( # (the message is looked at where it is, not copied)
    mname, msg
  ):
    result.msgName = mname
    for fd in def.fields:
      var s = Slot(def: fd)
      if fd.number in msg.byNumber:
        let fname = msg.byNumber.must(fd.number)
        if fname in msg.fields:
          let f = msg.fields.must(fname)
          s.known = true
          s.fieldName = fname
          s.kind = f.kind
          s.scale = f.scale
          s.offset = f.offset
          s.accumulate = f.accumulate
          s.meta = d.metaFor(def.globalNum, f)
          case f.kind
          of fkDynamic:
            result.hasDynamic = true
            result.mayDup = true
          of fkComposite:
            result.mayDup = true
            for c in f.components: # a component's target can be a dynamic field
              if c.target in msg.fields and msg.fields.must(c.target).kind == fkDynamic:
                result.hasDynamic = true
          of fkPlain:
            discard
      if not s.known and fd.base.isSome:
        s.meta = newMeta("", "", $fd.base.get, tkBase, fd.base.get)
      if fd.number in numbers:
        result.mayDup = true
      numbers.add fd.number
      result.slots.add s
  do:
    for fd in def.fields: # an unknown message: all fields unknown
      var s = Slot(def: fd)
      if fd.base.isSome:
        s.meta = newMeta("", "", $fd.base.get, tkBase, fd.base.get)
      if fd.number in numbers:
        result.mayDup = true
      numbers.add fd.number
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
    d.warnings.add wkFieldDescription, offset, "incomplete field_description"
    return
  let base = baseTypeFromByte(byte(bid.get and 0xff))
  if base.isNone:
    d.warnings.add wkFieldDescription,
      offset, "field_description: unknown base type " & $bid.get
    return
  var scale = 1.0
  let sc = r.intOf("scale")
  if sc.isSome and sc.get > 0:
    scale = float(sc.get)
  let off = r.intOf("offset")
  let name = r.strOf("field_name")
  let units = r.strOf("units")
  d.devFields[(int(idx.get), int(num.get))] = DevField(
    name: name,
    units: units,
    base: base.get,
    scale: scale,
    offset: (if off.isSome: float(off.get) else: 0.0),
    meta: newMeta(name, units, $base.get, tkBase, base.get),
  )

# --- records

func dropDuplicateNames(fs: var seq[FieldValue]) =
  ## Of values with one name keep the one decoded from the widest source (the most precise; eg
  ## `data` over the narrower `data16`), the first on a tie.  Values with no name are all kept.
  var anyDuplicate = false # (usually none: then nothing is allocated)
  block scan:
    for i in 0 ..< fs.len:
      if fs[i].meta.name.len == 0:
        continue
      for j in i + 1 ..< fs.len:
        if fs[j].meta == fs[i].meta or fs[j].meta.name == fs[i].meta.name:
          anyDuplicate = true
          break scan
  if not anyDuplicate:
    return
  var keep = newSeq[bool](fs.len)
  for i in 0 ..< fs.len:
    keep[i] = true
    if fs[i].meta.name.len == 0:
      continue
    for j in 0 ..< fs.len:
      if j == i or fs[j].meta.name != fs[i].meta.name:
        continue
      if (j < i and fs[j].bits >= fs[i].bits) or (j > i and fs[j].bits > fs[i].bits):
        keep[i] = false
        break
  var kept = newSeqOfCap[FieldValue](fs.len)
  for i in 0 ..< fs.len:
    if keep[i]:
      kept.add move(fs[i])
  fs = kept

let timestampMeta = newMeta("timestamp", "s", "date_time", tkDateTime, btUint32)
  ## the field of a compressed timestamp header that the definition lacks

proc decode*(
    d: var Decoder, p: Profile, t: Tokenizer, tok: Token
): Record {.raises: [].} =
  ## Decode a data token (other tokens give an empty record).  Must be called
  ## in file order.  Odd data adds to `d.warnings`; nothing is raised (a broken
  ## internal invariant is a bug, and an AssertionDefect).
  if tok.kind != tokData:
    return
  let idx = tok.defn
  if d.plans.len <= idx:
    d.plans.setLen(idx + 1)
  if not d.plans[idx].ready:
    d.plans[idx] = d.buildPlan(p, t.defs[idx])
  let globalNum = t.defs[idx].globalNum
  let endian = t.defs[idx].endian
  result = Record(
    name: d.plans[idx].msgName,
    number: globalNum,
    local: t.defs[idx].local,
    defn: idx,
    timestamp: tok.timestamp,
  )
  var ctx = RecCtx(msgNum: globalNum, offset: tok.offset, ts: tok.timestamp)
  let n = d.plans[idx].slots.len
  result.fields = newSeqOfCap[FieldValue](n + 2)

  template slotData(i: int): untyped =
    t.data.toOpenArray(
      tok.offset + d.plans[idx].slots[i].def.offset,
      tok.offset + d.plans[idx].slots[i].def.offset + d.plans[idx].slots[i].def.size - 1,
    )

  proc unknown(slot: Slot): Spec =
    Spec(
      meta: slot.meta,
      number: slot.def.number,
      kind: tkBase,
      base: slot.def.base.get,
      scale: 1,
      offset: 0,
      bits: 8 * slot.def.size,
      check: true,
    )

  # a compressed timestamp header with no timestamp field in the definition
  if tok.compressed and t.defs[idx].timestampField < 0 and tok.timestamp.isSome:
    result.fields.add FieldValue(
      kind: vkInt,
      meta: timestampMeta,
      number: timestampFieldNo,
      bits: 32,
      ints: @[int64(tok.timestamp.get)],
    )

  if not d.plans[idx].hasDynamic:
    # the usual case: the values come out in the order of the definition
    for i in 0 ..< n:
      let fd = d.plans[idx].slots[i].def
      if not d.plans[idx].slots[i].known:
        if fd.base.isNone:
          continue
        d.interpret(
          unknown(d.plans[idx].slots[i]), slotData(i), endian, ctx, result.fields
        )
      elif d.plans[idx].slots[i].kind == fkPlain:
        d.emitPlain(
          d.plans[idx].slots[i].meta,
          d.plans[idx].slots[i].scale,
          d.plans[idx].slots[i].offset,
          d.plans[idx].slots[i].accumulate,
          fd.number,
          fd.base,
          slotData(i),
          endian,
          ctx,
          Override(),
          false,
          result.fields,
        )
      else:
        d.decodeField(
          p,
          d.plans[idx],
          p.messages.must(d.plans[idx].msgName).fields.must(
            d.plans[idx].slots[i].fieldName
          ),
          d.plans[idx].slots[i].meta,
          fd.number,
          fd.base,
          slotData(i),
          endian,
          ctx,
          Override(),
          false,
          result.fields,
        )
  else:
    # a dynamic field depends on the values of others (which may come after it): the plain and
    # unknown fields first, then composites, then dynamic ones; the values keep the definition's order
    var groups = newSeq[seq[FieldValue]](n)
    template noteRefs(vs: seq[FieldValue]) =
      for v in vs:
        if v.meta.name.len > 0 and v.kind == vkInt and v.ints.len > 0:
          ctx.refs[v.meta.name] = v.ints[0]

    for i in 0 ..< n:
      let fd = d.plans[idx].slots[i].def
      if not d.plans[idx].slots[i].known:
        if fd.base.isNone:
          continue
        d.interpret(unknown(d.plans[idx].slots[i]), slotData(i), endian, ctx, groups[i])
      elif d.plans[idx].slots[i].kind == fkPlain:
        d.emitPlain(
          d.plans[idx].slots[i].meta,
          d.plans[idx].slots[i].scale,
          d.plans[idx].slots[i].offset,
          d.plans[idx].slots[i].accumulate,
          fd.number,
          fd.base,
          slotData(i),
          endian,
          ctx,
          Override(),
          false,
          groups[i],
        )
        noteRefs(groups[i])
    for pass in [fkComposite, fkDynamic]:
      for i in 0 ..< n:
        if d.plans[idx].slots[i].known and d.plans[idx].slots[i].kind == pass:
          let fd = d.plans[idx].slots[i].def
          d.decodeField(
            p,
            d.plans[idx],
            p.messages.must(d.plans[idx].msgName).fields.must(
              d.plans[idx].slots[i].fieldName
            ),
            d.plans[idx].slots[i].meta,
            fd.number,
            fd.base,
            slotData(i),
            endian,
            ctx,
            Override(),
            false,
            groups[i],
          )
          noteRefs(groups[i])
    for g in groups.mitems:
      for v in g.mitems:
        result.fields.add move(v)
  if d.plans[idx].mayDup:
    dropDuplicateNames(result.fields)

  for dv in t.defs[idx].devFields:
    let key = (dv.devIndex, dv.number)
    let at = tok.offset + dv.offset
    if key notin d.devFields:
      d.warnings.add wkUndescribedDevField,
        at,
        "no description for developer field " & $dv.number & " of developer " &
          $dv.devIndex
      continue
    let df = d.devFields.must(key)
    let sp = Spec(
      meta: df.meta,
      number: dv.number,
      kind: tkBase,
      base: df.base,
      scale: df.scale,
      offset: df.offset,
      bits: 8 * dv.size,
      check: true,
      dev: true,
    )
    d.interpret(
      sp, t.data.toOpenArray(at, at + dv.size - 1), endian, ctx, result.fields
    )

  if globalNum == fieldDescriptionNum:
    d.registerDev(result, tok.offset)

proc definitionEvent*(
    d: var Decoder, p: Profile, t: Tokenizer, tok: Token
): Event {.raises: [].} =
  ## Event for a definition token.  Developer field names are those described
  ## so far, so this must be called in file order.
  let idx = tok.defn
  if d.plans.len <= idx:
    d.plans.setLen(idx + 1)
  if not d.plans[idx].ready:
    d.plans[idx] = d.buildPlan(p, t.defs[idx])
  result = Event(
    kind: evDefinition,
    offset: tok.offset,
    local: t.defs[idx].local,
    number: t.defs[idx].globalNum,
    message: d.plans[idx].msgName,
  )
  for s in d.plans[idx].slots:
    let name = if s.known: s.meta.name else: ""
    let sz = if s.def.base.isSome: s.def.base.get.size else: 1
    result.fields.add (name, s.def.size div sz)
  for dv in t.defs[idx].devFields:
    let key = (dv.devIndex, dv.number)
    if key in d.devFields:
      let df = d.devFields.must(key)
      result.fields.add (df.name, dv.size div df.base.size)
    else:
      result.fields.add ("", dv.size)

proc resetFile*(d: var Decoder) {.raises: [].} =
  ## Forget what was learned from the file so far (accumulated totals,
  ## developer fields), for the start of a chained file.
  d.accum.clear()
  d.devFields.clear()
