## FIT profile: plain-data model of the `Types` and `Messages` sheets of
## Profile.xlsx, plus a loader.  Decoding behaviour lives elsewhere; nothing
## here refers to binary data.
##
## Objects refer to each other by name (type names, field names) rather than
## by reference, so a Profile is an immutable-in-spirit value with no cycles.

import std/[options, sequtils, strutils, tables]
import ./xlsxrows

type
  ProfileError* = object of CatchableError

  BaseType* = enum
    ## Order follows the FIT base type list used by choochoo.
    btEnum = "enum", btSint8 = "sint8", btUint8 = "uint8",
    btSint16 = "sint16", btUint16 = "uint16",
    btSint32 = "sint32", btUint32 = "uint32",
    btString = "string", btFloat32 = "float32", btFloat64 = "float64",
    btUint8z = "uint8z", btUint16z = "uint16z", btUint32z = "uint32z",
    btByte = "byte", btSint64 = "sint64", btUint64 = "uint64",
    btUint64z = "uint64z"

  TypeKind* = enum
    tkBase,           ## a base type used directly (uint16, string, ...)
    tkBool,           ## uint8 interpreted as a boolean
    tkMapping,        ## named enumeration from the Types sheet
    tkDateTime,       ## uint32 seconds since 1989-12-31 UTC
    tkLocalDateTime,  ## as tkDateTime, but not UTC
    tkTimestamp16     ## low 16 bits of a timestamp (needs context to decode)

  FitType* = object
    name*: string
    base*: BaseType   ## underlying binary representation (all kinds)
    case kind*: TypeKind
    of tkMapping:
      toValue*: Table[string, int64]  ## profile name -> number
      toName*: Table[int64, string]   ## number -> profile name
    else: discard

  FieldKind* = enum fkPlain, fkComposite, fkDynamic

  Component* = object
    ## One slice of a composite field's bits.
    target*: string   ## field (same message) that interprets the slice
    bits*: int
    scale*, offset*: float
    units*: string
    accumulate*: bool

  Choice* = object
    ## One alternative of a dynamic field.
    refField*: string  ## field (same message) whose value selects this
    refValue*: int64   ## value of refField, as a number
    target*: string    ## subfield used when it matches

  Field* = object
    name*: string
    number*: Option[int]  ## none for subfields
    typeName*: string     ## key into Profile.types
    units*: string
    scale*, offset*: float
    accumulate*: bool
    case kind*: FieldKind
    of fkPlain: discard
    of fkComposite:
      components*: seq[Component]
    of fkDynamic:
      refs*: seq[string]     ## referenced fields, in first-seen order
      choices*: seq[Choice]  ## in sheet order

  Message* = object
    name*: string
    number*: int
    fields*: Table[string, Field]  ## all fields, subfields included
    byNumber*: Table[int, string]  ## field number -> field name

  Profile* = object
    types*: Table[string, FitType]
    messages*: Table[string, Message]
    byNumber*: Table[int, string]  ## message number -> message name

const
  overrides = ["date_time", "local_date_time", "timestamp_16"]

# --- parsing helpers

proc fail(sheet: string, row: int, msg: string) {.noreturn.} =
  raise newException(ProfileError, sheet & " row " & $(row + 1) & ": " & msg)

proc parseNum*(s: string): int64 =
  ## Integer cell: decimal, 0x hex, or a float spelling of an integer ("1.0").
  let t = s.strip
  if t.startsWith("0x") or t.startsWith("0X"):
    int64(parseHexInt(t))
  elif '.' in t or 'E' in t or 'e' in t:
    int64(parseFloat(t))
  else:
    int64(parseInt(t))

proc split(s: string): seq[string] =
  ## Comma-separated cell; "" gives no items.
  if s.len == 0: @[] else: s.split(',').mapIt(it.strip)

proc baseTypeOf(name: string): Option[BaseType] =
  for b in BaseType:
    if $b == name: return some(b)

proc isHeading(s: string): bool =
  s.len > 0 and s[0].isUpperAscii

# --- types

proc seedTypes(): Table[string, FitType] =
  for b in BaseType:
    result[$b] = FitType(name: $b, base: b, kind: tkBase)
  result["bool"] = FitType(name: "bool", base: btUint8, kind: tkBool)
  result["date_time"] =
    FitType(name: "date_time", base: btUint32, kind: tkDateTime)
  result["local_date_time"] =
    FitType(name: "local_date_time", base: btUint32, kind: tkLocalDateTime)
  result["timestamp_16"] =
    FitType(name: "timestamp_16", base: btUint16, kind: tkTimestamp16)

proc loadTypes*(rows: seq[Row]): Table[string, FitType] =
  ## Columns: 0 type_name, 1 base_type, 2 value_name, 3 value.
  result = seedTypes()
  var cur = ""   # name of the mapping being filled, or "" if none
  for i, row in rows:
    let name = row.cell(0)
    if name.len > 0:
      cur = ""
      if name.isHeading or name in result: continue
      let base = baseTypeOf(row.cell(1))
      if base.isNone: fail("Types", i, "unknown base type " & row.cell(1))
      result[name] = FitType(name: name, base: base.get, kind: tkMapping)
      cur = name
    elif cur.len > 0 and row.cell(2).len > 0 and row.cell(3).len > 0:
      let value =
        try: parseNum(row.cell(3))
        except ValueError: fail("Types", i, "bad value " & row.cell(3))
      result[cur].toValue[row.cell(2)] = value
      result[cur].toName[value] = row.cell(2)
    else:
      cur = ""

# --- messages

proc optNum(s: string, default: float): float =
  if s.len == 0: default else: parseFloat(s)

proc isSubfieldRow(row: Row): bool =
  row.cell(0).len == 0 and row.cell(1).len == 0 and row.cell(2).len > 0

proc component(target, bits, units, scale, offset, accum: string): Component =
  Component(target: target, bits: int(parseNum(bits)), units: units,
            scale: optNum(scale, 1), offset: optNum(offset, 0),
            accumulate: accum.len > 0 and parseNum(accum) != 0)

proc composite(row: Row, i: int, f: Field): Field =
  ## `f` is a plain field; add the components from the row.
  let
    names = split(row.cell(5))
    bits = split(row.cell(9))
    units = split(row.cell(8))
    scale = split(row.cell(6))
    offset = split(row.cell(7))
    accum = split(row.cell(10))
  proc at(xs: seq[string], k: int): string =
    if k < xs.len: xs[k] else: ""
  result = Field(name: f.name, number: f.number, typeName: f.typeName,
                 scale: 1, offset: 0, kind: fkComposite)
  for k, name in names:
    if bits.at(k).len == 0: fail("Messages", i, "component without bits")
    result.components.add component(name, bits.at(k), units.at(k),
                                    scale.at(k), offset.at(k), accum.at(k))

proc plainField(row: Row, i: int): Field =
  let
    name = row.cell(2)
    isComposite = row.cell(5).len > 0  # scale etc are per-component lists
    scale = try: optNum(if isComposite: "" else: row.cell(6), 1)
            except ValueError: fail("Messages", i, "bad scale " & row.cell(6))
    offset = try: optNum(if isComposite: "" else: row.cell(7), 0)
             except ValueError: fail("Messages", i, "bad offset " & row.cell(7))
  result = Field(
    name: name,
    number: if row.cell(1).len > 0: some(int(parseNum(row.cell(1))))
            else: none(int),
    typeName: if name in overrides: name else: row.cell(3),
    units: if isComposite: "" else: row.cell(8),
    scale: if scale == 0: 1 else: scale,
    offset: offset,
    accumulate: not isComposite and row.cell(10).len > 0 and
                parseNum(row.cell(10)) != 0,
    kind: fkPlain)

proc resolveRef(types: Table[string, FitType], msg: Message,
                refField, value: string): int64 =
  ## Number for `value` of field `refField`, via its mapping if it has one.
  if refField notin msg.fields:
    raise newException(ProfileError,
      msg.name & ": dynamic reference to unknown field " & refField)
  let t = types[msg.fields[refField].typeName]
  if t.kind == tkMapping:
    if value notin t.toValue:
      raise newException(ProfileError,
        msg.name & "." & refField & ": no value " & value & " in " & t.name)
    t.toValue[value]
  else:
    parseNum(value)

proc loadMessages*(rows: seq[Row], types: Table[string, FitType]):
    (Table[string, Message], Table[int, string]) =
  ## Columns: 0 msg_name, 1 field_no, 2 field_name, 3 field_type, 5 components,
  ## 6 scale, 7 offset, 8 units, 9 bits, 10 accumulate, 11 ref_name, 12 ref_value.
  var
    messages: Table[string, Message]
    byNumber: Table[int, string]
    cur = ""
    # raw ref values for dynamic fields, parallel to Field.choices
    pending: Table[string, seq[string]]

  proc finish() =
    if cur.len == 0: return
    for fname, raws in pending:
      if messages[cur].fields[fname].kind != fkDynamic: continue
      for k, raw in raws:
        let c = messages[cur].fields[fname].choices[k]
        messages[cur].fields[fname].choices[k].refValue =
          resolveRef(types, messages[cur], c.refField, raw)
    pending.clear()
    cur = ""

  if "mesg_num" notin types:
    raise newException(ProfileError, "no mesg_num type")
  let mesgNum = types["mesg_num"]

  for i, row in rows:
    if row.cell(0).len > 0:
      finish()
      let name = row.cell(0)
      if name.isHeading: continue
      if name notin mesgNum.toValue:
        fail("Messages", i, "message " & name & " not in mesg_num")
      let number = int(mesgNum.toValue[name])
      messages[name] = Message(name: name, number: number)
      byNumber[number] = name
      cur = name
    elif cur.len == 0:
      continue
    elif row.cell(2).len == 0:
      finish()   # blank row ends the message
    else:
      var f = plainField(row, i)
      if f.typeName notin types:
        fail("Messages", i, "unknown type " & f.typeName)
      if row.cell(5).len > 0:
        f = composite(row, i, f)
      elif f.number.isSome and i + 1 < rows.len and isSubfieldRow(rows[i + 1]):
        # dynamic: gather the subfield rows that follow
        var d = Field(name: f.name, number: f.number, typeName: f.typeName,
                      units: f.units, scale: f.scale, offset: f.offset,
                      accumulate: f.accumulate, kind: fkDynamic)
        var raws: seq[string]
        var j = i + 1
        while j < rows.len and isSubfieldRow(rows[j]):
          let
            names = split(rows[j].cell(11))
            values = split(rows[j].cell(12))
          if names.len != values.len:
            fail("Messages", j, "ref_name / ref_value length mismatch")
          for k, rname in names:
            if rname notin d.refs: d.refs.add rname
            d.choices.add Choice(refField: rname, target: rows[j].cell(2))
            raws.add values[k]
          inc j
        pending[f.name] = raws
        f = d
      messages[cur].fields[f.name] = f
      if f.number.isSome:
        messages[cur].byNumber[f.number.get] = f.name
  finish()
  (messages, byNumber)

proc loadProfile*(path: string): Profile =
  ## Read the Types and Messages sheets of the xlsx file at `path`.
  let types = loadTypes(sheetRows(path, "Types"))
  let (messages, byNumber) = loadMessages(sheetRows(path, "Messages"), types)
  Profile(types: types, messages: messages, byNumber: byNumber)
