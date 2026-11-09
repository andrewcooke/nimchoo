## FIT profile: the plain-data model of the `Types` and `Messages` sheets of
## Profile.xlsx.  Loading it is in load.nim; decoding behaviour lives elsewhere;
## nothing here refers to binary data.
##
## Objects refer to each other by name (type names, field names) rather than
## by reference, so a Profile is an immutable-in-spirit value with no cycles.

import std/[options, sets, tables]
import ./basetype

{.push raises: [].}

type
  TypeKind* = enum
    tkBase ## a base type used directly (uint16, string, ...)
    tkBool ## uint8 interpreted as a boolean
    tkMapping ## named enumeration from the Types sheet
    tkDateTime ## uint32 seconds since 1989-12-31 UTC
    tkLocalDateTime ## as tkDateTime, but not UTC
    tkTimestamp16 ## low 16 bits of a timestamp (needs context to decode)

  FitType* = object
    name*: string
    base*: BaseType ## underlying binary representation (all kinds)
    case kind*: TypeKind
    of tkMapping:
      toValue*: Table[string, int64] ## profile name -> number
      toName*: Table[int64, string] ## number -> profile name
    else:
      discard

  FieldKind* = enum
    fkPlain
    fkComposite
    fkDynamic

  Component* = object ## One slice of a composite field's bits.
    target*: string ## field (same message) that interprets the slice
    bits*: int
    scale*, offset*: float
    units*: string
    accumulate*: bool

  Choice* = object ## One alternative of a dynamic field.
    refField*: string ## field (same message) whose value selects this
    refValue*: int64 ## value of refField, as a number
    target*: string ## subfield used when it matches

  Field* = object
    name*: string
    number*: Option[int] ## none for subfields
    typeName*: string ## key into Profile.types
    units*: string
    scale*, offset*: float
    accumulate*: bool
    case kind*: FieldKind
    of fkPlain: discard
    of fkComposite:
      components*: seq[Component]
    of fkDynamic:
      refs*: seq[string] ## referenced fields, in first-seen order
      choices*: seq[Choice] ## in sheet order

  Message* = object
    name*: string
    number*: int
    fields*: Table[string, Field] ## all fields, subfields included
    byNumber*: Table[int, string] ## field number -> field name

  Profile* = object
    types*: Table[string, FitType]
    messages*: Table[string, Message]
    byNumber*: Table[int, string] ## message number -> message name

func timestamp16Fields*(p: Profile): HashSet[(int, int)] =
  ## (message number, field number) of every timestamp_16 field.
  for m in p.messages.values:
    for f in m.fields.values:
      if f.number.isSome and f.typeName == "timestamp_16":
        result.incl (m.number, f.number.get)
