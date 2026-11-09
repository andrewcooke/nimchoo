## Loading the FIT profile (model.nim) from the `Types` and `Messages` sheets
## of Profile.xlsx.

import std/[math, options, sequtils, sets, strutils, tables]
import ../core/errors
import ../fit/basetype
import ../packages/util/lookup/lookup
import ../packages/util/xlsx/xlsx
import ./model
export errors, model

{.push raises: [].}

const overrides = ["date_time", "local_date_time", "timestamp_16"]

# --- parsing helpers

proc fail(sheet: string, row: int, msg: string) {.noreturn, raises: [ProfileError].} =
  raiseProfile(sheet & " row " & $(row + 1) & ": " & msg, sheet, row + 1)

proc parseNum*(s: string): int64 {.raises: [ValueError].} =
  ## Integer cell: decimal, 0x hex, or a float spelling of an integer ("1.0").
  let t = s.strip
  if t.startsWith("0x") or t.startsWith("0X"):
    int64(parseHexInt(t))
  elif '.' in t or 'E' in t or 'e' in t:
    let f = parseFloat(t)
    if classify(f) in {fcNan, fcInf, fcNegInf} or abs(f) > 9e18:
      raise newException(ValueError, "not an integer: " & t)
    int64(f)
  else:
    int64(parseInt(t))

proc split(s: string): seq[string] =
  ## Comma-separated cell; "" gives no items.
  if s.len == 0:
    @[]
  else:
    s.split(',').mapIt(it.strip)

proc intCell(
    sheet: string, row: int, what, s: string
): int64 {.raises: [ProfileError].} =
  ## An integer cell (see `parseNum`).  Raises ProfileError, with the sheet and
  ## (0-based) row, if it is not one.
  try:
    parseNum(s)
  except ValueError:
    fail(sheet, row, "bad " & what & " " & s)

proc floatCell(
    sheet: string, row: int, what, s: string, default: float
): float {.raises: [ProfileError].} =
  ## A finite number in a cell, or `default` if the cell is empty.  Raises
  ## ProfileError, with the sheet and (0-based) row, if it is not a number.
  if s.len == 0:
    return default
  try:
    result = parseFloat(s)
  except ValueError:
    fail(sheet, row, "bad " & what & " " & s)
  if classify(result) in {fcNan, fcInf, fcNegInf}:
    fail(sheet, row, "bad " & what & " " & s)

proc isHeading(s: string): bool =
  s.len > 0 and s[0].isUpperAscii

# --- types

proc seedTypes(): Table[string, FitType] =
  for b in BaseType:
    result[$b] = FitType(name: $b, base: b, kind: tkBase)
  result["bool"] = FitType(name: "bool", base: btUint8, kind: tkBool)
  result["date_time"] = FitType(name: "date_time", base: btUint32, kind: tkDateTime)
  result["local_date_time"] =
    FitType(name: "local_date_time", base: btUint32, kind: tkLocalDateTime)
  result["timestamp_16"] =
    FitType(name: "timestamp_16", base: btUint16, kind: tkTimestamp16)

proc loadTypes*(rows: seq[Row]): Table[string, FitType] {.raises: [ProfileError].} =
  ## Columns: 0 type_name, 1 base_type, 2 value_name, 3 value.
  result = seedTypes()
  var fromSheet: HashSet[string]
    # the types the sheet has defined (the program's own are not among them)
  var cur = "" # name of the mapping being filled, or "" if none
  for i, row in rows:
    let name = row.cell(0)
    if name.len > 0:
      cur = ""
      if name.isHeading:
        continue
      if name in result:
        if name in fromSheet:
          fail("Types", i, "type " & name & " is defined twice")
        continue # (one the program has already: bool, date_time ...)
      fromSheet.incl name
      let base = baseTypeFromName(row.cell(1))
      if base.isNone:
        fail("Types", i, "unknown base type " & row.cell(1))
      result[name] = FitType(name: name, base: base.get, kind: tkMapping)
      cur = name
    elif cur.len > 0 and row.cell(2).len > 0 and row.cell(3).len > 0:
      let value = intCell("Types", i, "value", row.cell(3))
      if row.cell(2) in result.must(cur).toValue:
        fail("Types", i, cur & " has the value name " & row.cell(2) & " twice")
      result.mustMut(cur).toValue[row.cell(2)] = value
      result.mustMut(cur).toName[value] = row.cell(2)
    else:
      cur = ""

# --- messages

proc isSubfieldRow(row: Row): bool =
  row.cell(0).len == 0 and row.cell(1).len == 0 and row.cell(2).len > 0

proc scaleCell(i: int, what, s: string): float {.raises: [ProfileError].} =
  ## A scale (1 if the cell is empty): never 0, which every value would be divided by.
  result = floatCell("Messages", i, what, s, 1)
  if result == 0:
    fail("Messages", i, "bad " & what & " " & s & " (values are divided by it)")

proc component(
    i: int, target, bits, units, scale, offset, accum: string
): Component {.raises: [ProfileError].} =
  let n = intCell("Messages", i, "component bits", bits)
  if n < 1 or n > 64:
    fail("Messages", i, "component bits out of range: " & bits)
  Component(
    target: target,
    bits: int(n),
    units: units,
    scale: scaleCell(i, "component scale", scale),
    offset: floatCell("Messages", i, "component offset", offset, 0),
    accumulate:
      accum.len > 0 and intCell("Messages", i, "component accumulate", accum) != 0,
  )

proc composite(row: Row, i: int, f: Field): Field {.raises: [ProfileError].} =
  ## `f` is a plain field; add the components from the row.
  let
    names = split(row.cell(5))
    bits = split(row.cell(9))
    units = split(row.cell(8))
    scale = split(row.cell(6))
    offset = split(row.cell(7))
    accum = split(row.cell(10))
  proc at(xs: seq[string], k: int): string =
    if k < xs.len:
      xs[k]
    else:
      ""

  result = Field(
    name: f.name,
    number: f.number,
    typeName: f.typeName,
    scale: 1,
    offset: 0,
    kind: fkComposite,
  )
  for k, name in names:
    if bits.at(k).len == 0:
      fail("Messages", i, "component without bits")
    result.components.add component(
      i, name, bits.at(k), units.at(k), scale.at(k), offset.at(k), accum.at(k)
    )

proc plainField(row: Row, i: int): Field {.raises: [ProfileError].} =
  let
    name = row.cell(2)
    isComposite = row.cell(5).len > 0 # scale etc are per-component lists
    scale = scaleCell(
      i,
      "scale",
      if isComposite:
        ""
      else:
        row.cell(6),
    )
    offset = floatCell(
      "Messages",
      i,
      "offset",
      if isComposite:
        ""
      else:
        row.cell(7),
      0,
    )
  result = Field(
    name: name,
    number:
      if row.cell(1).len > 0:
        some(int(intCell("Messages", i, "field number", row.cell(1))))
      else:
        none(int),
    typeName:
      if name in overrides:
        name
      else:
        row.cell(3),
    units:
      if isComposite:
        ""
      else:
        row.cell(8),
    scale: scale,
    offset: offset,
    accumulate:
      not isComposite and row.cell(10).len > 0 and
      intCell("Messages", i, "accumulate", row.cell(10)) != 0,
    kind: fkPlain,
  )

proc resolveRef(
    types: Table[string, FitType], msg: Message, refField, value: string, row: int
): int64 {.raises: [ProfileError].} =
  ## Number for `value` of field `refField`, via its mapping if it has one.
  ## `row` (0-based) is the sheet row the reference came from, for errors.
  if refField notin msg.fields:
    fail("Messages", row, msg.name & ": dynamic reference to unknown field " & refField)
  let t = types.must(msg.fields.must(refField).typeName)
  if t.kind == tkMapping:
    if value notin t.toValue:
      fail(
        "Messages",
        row,
        msg.name & "." & refField & ": no value " & value & " in " & t.name,
      )
    t.toValue.must(value)
  else:
    intCell("Messages", row, "reference value", value)

proc loadMessages*(
    rows: seq[Row], types: Table[string, FitType]
): (Table[string, Message], Table[int, string]) {.raises: [ProfileError].} =
  ## Columns: 0 msg_name, 1 field_no, 2 field_name, 3 field_type, 5 components,
  ## 6 scale, 7 offset, 8 units, 9 bits, 10 accumulate, 11 ref_name, 12 ref_value.
  var
    messages: Table[string, Message]
    byNumber: Table[int, string]
    cur = ""
    # raw ref values for dynamic fields, parallel to Field.choices
    pending: Table[string, seq[(string, int)]] # (raw value, sheet row)

  proc finish() {.raises: [ProfileError].} =
    if cur.len == 0:
      return
    for fname, raws in pending:
      if messages.must(cur).fields.must(fname).kind != fkDynamic:
        continue
      for k, (raw, row) in raws:
        let c = messages.must(cur).fields.must(fname).choices[k]
        let value = resolveRef(types, messages.must(cur), c.refField, raw, row)
        messages.mustMut(cur).fields.mustMut(fname).choices[k].refValue = value
    pending.clear()
    cur = ""

  if "mesg_num" notin types:
    raiseProfile("no mesg_num type")
  let mesgNum = types.must("mesg_num")

  for i, row in rows:
    if row.cell(0).len > 0:
      finish()
      let name = row.cell(0)
      if name.isHeading:
        continue
      if name notin mesgNum.toValue:
        fail("Messages", i, "message " & name & " not in mesg_num")
      let number = int(mesgNum.toValue.must(name))
      if name in messages:
        fail("Messages", i, "message " & name & " is defined twice")
      if number in byNumber:
        fail(
          "Messages",
          i,
          "messages " & byNumber.must(number) & " and " & name & " have number " &
            $number,
        )
      messages[name] = Message(name: name, number: number)
      byNumber[number] = name
      cur = name
    elif cur.len == 0:
      continue
    elif row.cell(2).len == 0:
      finish() # blank row ends the message
    else:
      var f = plainField(row, i)
      if f.typeName notin types:
        fail("Messages", i, "unknown type " & f.typeName)
      if row.cell(5).len > 0:
        f = composite(row, i, f)
      elif f.number.isSome and i + 1 < rows.len and isSubfieldRow(rows[i + 1]):
        # dynamic: gather the subfield rows that follow
        var d = Field(
          name: f.name,
          number: f.number,
          typeName: f.typeName,
          units: f.units,
          scale: f.scale,
          offset: f.offset,
          accumulate: f.accumulate,
          kind: fkDynamic,
        )
        var raws: seq[(string, int)]
        var j = i + 1
        while j < rows.len and isSubfieldRow(rows[j]):
          let
            names = split(rows[j].cell(11))
            values = split(rows[j].cell(12))
          if names.len != values.len:
            fail("Messages", j, "ref_name / ref_value length mismatch")
          for k, rname in names:
            if rname notin d.refs:
              d.refs.add rname
            d.choices.add Choice(refField: rname, target: rows[j].cell(2))
            raws.add (values[k], j)
          inc j
        pending[f.name] = raws
        f = d
      if f.name in messages.must(cur).fields:
        fail("Messages", i, cur & " has the field " & f.name & " twice")
      messages.mustMut(cur).fields[f.name] = f
      if f.number.isSome:
        if f.number.get in messages.must(cur).byNumber:
          fail("Messages", i, cur & " has the field number " & $f.number.get & " twice")
        messages.mustMut(cur).byNumber[f.number.get] = f.name
  finish()
  (messages, byNumber)

proc loadProfileFromBytes*(
    xlsx: string
): Profile {.raises: [ProfileError, XlsxError].} =
  ## Read the Types and Messages sheets of an xlsx file held in memory.
  let wb = openWorkbook(xlsx)
  let types = loadTypes(wb.rows("Types"))
  let (messages, byNumber) = loadMessages(wb.rows("Messages"), types)
  Profile(types: types, messages: messages, byNumber: byNumber)

proc loadProfile*(
    path: string
): Profile {.raises: [ProfileError, XlsxError, IOError].} =
  ## Read the Types and Messages sheets of the xlsx file at `path`.
  loadProfileFromBytes(readFile(path))
