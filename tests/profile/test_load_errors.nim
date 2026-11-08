## Bad profile spreadsheets give a ProfileError that says where.

import std/[strutils, tables, unittest]
import nimchoo/profile/load
import ../support/xlsxbuilder

const
  typesHeader = @["Type Name", "Base Type", "Value Name", "Value", "Comment"]
  messagesHeader = @[
    "Message Name", "Field Def #", "Field Name", "Field Type", "Array", "Components",
    "Scale", "Offset", "Units", "Bits", "Accumulate", "Ref Field Name",
    "Ref Field Value",
  ]

func types(extra: seq[seq[string]] = @[]): seq[seq[string]] =
  @[
    typesHeader,
    @["mesg_num", "enum", "", "", ""],
    @["", "", "file_id", "0", ""],
    @["", "", "record", "20", ""],
    @["sport", "enum", "", "", ""],
    @["", "", "running", "1", ""],
    @["", "", "cycling", "2", ""],
  ] & extra

func field(
    num, name, typ: string,
    scale = "",
    offset = "",
    accumulate = "",
    components = "",
    bits = "",
): seq[string] =
  @["", num, name, typ, "", components, scale, offset, "", bits, accumulate, "", ""]

func record(fields: seq[seq[string]]): seq[seq[string]] =
  @[messagesHeader, @["record", "", "", "", "", "", "", "", "", "", "", "", ""]] & fields

proc load(typeRows, messageRows: seq[seq[string]]): Profile =
  loadProfileFromBytes(xlsxFile(@[("Types", typeRows), ("Messages", messageRows)]))

proc expectError(
    typeRows, messageRows: seq[seq[string]], sheet: string, row: int, text: string
) =
  try:
    discard load(typeRows, messageRows)
    check false # a ProfileError was expected
  except ProfileError as e:
    check e.sheet == sheet
    check e.row == row
    check text in e.msg

suite "profile errors":
  test "a good minimal profile loads":
    let p = load(types(), record(@[field("3", "heart_rate", "uint8", scale = "2")]))
    check p.messages["record"].fields["heart_rate"].scale == 2

  test "bad scale, offset, number, accumulate: sheet and row are reported":
    # the message header is row 1, "record" row 2, the field row 3
    expectError(
      types(),
      record(@[field("3", "hr", "uint8", scale = "abc")]),
      "Messages",
      3,
      "bad scale abc",
    )
    expectError(
      types(),
      record(@[field("3", "hr", "uint8", offset = "1x")]),
      "Messages",
      3,
      "bad offset 1x",
    )
    expectError(
      types(), record(@[field("x", "hr", "uint8")]), "Messages", 3, "bad field number x"
    )
    expectError(
      types(),
      record(@[field("3", "hr", "uint8", accumulate = "y")]),
      "Messages",
      3,
      "bad accumulate y",
    )

  test "nan and infinity are not numbers":
    expectError(
      types(),
      record(@[field("3", "hr", "uint8", scale = "nan")]),
      "Messages",
      3,
      "bad scale nan",
    )
    expectError(
      types(),
      record(@[field("3", "hr", "uint8", scale = "inf")]),
      "Messages",
      3,
      "bad scale inf",
    )

  test "a scale of 0 is refused: every value would be divided by it":
    expectError(
      types(), record(@[field("3", "hr", "uint8", scale = "0")]), "Messages", 3, "bad scale 0"
    )
    expectError(
      types(),
      record(@[field("2", "alt", "uint16", components = "a", bits = "8", scale = "0")]),
      "Messages",
      3,
      "bad component scale 0",
    )
    expectError(
      types(),
      record(@[field("2", "alt", "uint16", components = "a,b", bits = "8,8", scale = "5,0")]),
      "Messages",
      3,
      "bad component scale 0",
    )

  test "a name or number defined twice is refused, not overwritten":
    expectError(
      types(@[@["sport", "enum", "", "", ""]]), record(@[]), "Types", 8, "type sport is defined twice"
    )
    expectError(
      types(@[@["", "", "running", "7", ""]]),
      record(@[]),
      "Types",
      8,
      "sport has the value name running twice",
    )
    expectError(
      types(),
      record(@[field("3", "hr", "uint8"), field("4", "hr", "uint8")]),
      "Messages",
      4,
      "record has the field hr twice",
    )
    expectError(
      types(),
      record(@[field("3", "hr", "uint8"), field("3", "cad", "uint8")]),
      "Messages",
      4,
      "record has the field number 3 twice",
    )
    let twice = @[
      messagesHeader,
      @["record", "", "", "", "", "", "", "", "", "", "", "", ""],
      @["record", "", "", "", "", "", "", "", "", "", "", "", ""],
    ]
    expectError(types(), twice, "Messages", 3, "message record is defined twice")

  test "bad mapping value in the Types sheet":
    expectError(
      types(@[@["", "", "walking", "1x", ""]]), record(@[]), "Types", 8, "bad value 1x"
    )

  test "unknown base type and unknown field type":
    expectError(
      types(@[@["colour", "float7", "", "", ""]]),
      record(@[]),
      "Types",
      8,
      "unknown base type float7",
    )
    expectError(
      types(),
      record(@[field("3", "hr", "nonesuch")]),
      "Messages",
      3,
      "unknown type nonesuch",
    )

  test "bad components":
    expectError(
      types(),
      record(@[field("2", "alt", "uint16", components = "a", bits = "zz")]),
      "Messages",
      3,
      "bad component bits zz",
    )
    expectError(
      types(),
      record(@[field("2", "alt", "uint16", components = "a", bits = "0")]),
      "Messages",
      3,
      "component bits out of range",
    )
    expectError(
      types(),
      record(@[field("2", "alt", "uint16", components = "a", bits = "65")]),
      "Messages",
      3,
      "component bits out of range",
    )

  test "bad dynamic reference":
    # field 5 "sport" followed by a subfield row referring to a missing value
    let sub =
      @["", "", "swim", "uint8", "", "", "", "", "", "", "", "sport", "swimming"]
    expectError(
      types(),
      record(@[field("5", "sport", "sport"), field("6", "cycles", "uint8"), sub]),
      "Messages",
      5,
      "no value swimming in sport",
    )

  test "missing mesg_num, message not in mesg_num":
    expectError(@[typesHeader], record(@[]), "", 0, "no mesg_num type")
    expectError(
      types(),
      @[messagesHeader, @["nonesuch", "", "", "", "", "", "", "", "", "", "", "", ""]],
      "Messages",
      2,
      "not in mesg_num",
    )

  test "not an integer: huge or non-finite floats":
    expect ValueError:
      discard parseNum("1e999")
    expect ValueError:
      discard parseNum("nan")
    check parseNum("1.0") == 1
    check parseNum("0x10") == 16
