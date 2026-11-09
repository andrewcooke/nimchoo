## What a file decodes to: named values (`FieldValue`), `Record`s (one data
## message), and `Event`s (a definition or a record, in file order), with the
## accessors that go with them.

import std/[options, tables]
import ../packages/util/lookup/lookup
import ../profile/model
import ./basetype
import ./time
export time.FitTime

{.push raises: [].}

type
  ValueKind* = enum
    vkInt
    vkFloat
    vkString

  FieldMeta* {.acyclic.} = object
    ## What every value of one profile field has in common.  Made once for each field of a message
    ## and pointed at by its values, not copied into each (a file has hundreds of thousands).
    name*: string ## "" if the field is not in the profile
    units*: string
    typeName*: string ## profile type (mapping, date_time, bool...) or base type
    kind*: TypeKind ## of that type
    base*: BaseType ## its binary form

  Meta* = ref FieldMeta ## shared, and never changed once made

  FieldValue* = object
    meta*: Meta
    number*: int ## field number (components: the target's; -1 if none)
    dev*: bool ## developer field
    bits*: int ## width in bits of the source it was decoded from
    case kind*: ValueKind
    of vkInt: ints*: seq[int64]
    of vkFloat: floats*: seq[float]
    of vkString: strings*: seq[string]

  Record* = object
    name*: string ## "" if the message is not in the profile
    number*: int ## global message number
    local*: int ## local message type
    defn*: int ## index into Tokenizer.defs
    timestamp*: Option[FitTime]
    fields*: seq[FieldValue]

type
  EventKind* = enum
    evDefinition
    evRecord

  DefField* = tuple[name: string, count: int] ## name "" if unknown

  Event* = object ## A definition or a decoded data message, in file order.
    offset*: int
    case kind*: EventKind
    of evDefinition:
      local*: int
      message*: string ## "" if unknown
      number*: int ## global message number
      fields*: seq[DefField]
    of evRecord:
      record*: Record

func newMeta*(name, units, typeName: string, kind: TypeKind, base: BaseType): Meta =
  ## The description of a field (see Meta).
  Meta(name: name, units: units, typeName: typeName, kind: kind, base: base)

func name*(f: FieldValue): lent string =
  ## The field's name.
  f.meta.name
func units*(f: FieldValue): lent string =
  ## The field's units ("" if none).
  f.meta.units
func typeName*(f: FieldValue): lent string =
  ## The name of the field's FIT type.
  f.meta.typeName

func field*(r: Record, name: string): Option[FieldValue] =
  ## The first field called `name`.
  for f in r.fields:
    if f.name == name:
      return some(f)

func valueName*(p: Profile, f: FieldValue, i = 0): string {.raises: [].} =
  ## Profile name of an enumerated value, else the value as text.
  case f.kind
  of vkInt:
    if i >= f.ints.len:
      return ""
    let v = f.ints[i]
    if f.typeName in p.types and p.types.must(f.typeName).kind == tkMapping and
        v in p.types.must(f.typeName).toName:
      return p.types.must(f.typeName).toName.must(v)
    $v
  of vkFloat:
    if i >= f.floats.len:
      ""
    else:
      $f.floats[i]
  of vkString:
    if i >= f.strings.len:
      ""
    else:
      f.strings[i]
