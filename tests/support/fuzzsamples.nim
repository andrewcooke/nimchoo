## Valid inputs for the fuzzers to damage, and for libFuzzer to start from (tools/fuzz.nim): a zip, an xlsx workbook, a
## small profile, addresses.

import std/[strutils]
import ./[xlsxbuilder, zips]

proc zipBases*(): seq[string] =
  ## Valid zip files to damage: deflated, stored, several entries, an empty one, a long name.
  let text = repeat("the quick brown fox, 12345; ", 200)
  let entries =
    @[("a.txt", "hello"), ("dir/b.csv", text), ("empty", ""), ("c.txt", text[0 .. 99])]
  @[
    makeZip(entries, deflate = true),
    makeZip(entries, deflate = false),
    makeZip(@[(repeat("n", 300), "x")]),
    makeZip(newSeq[(string, string)]()),
    storedZip(entries),
  ]

let xlsxParts* = @[
  (
    "xl/workbook.xml",
    """<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="One" sheetId="1" r:id="rId1"/><sheet name="Two" sheetId="2" r:id="rId2"/></sheets></workbook>""",
  ),
  (
    "xl/_rels/workbook.xml.rels",
    """<Relationships><Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="worksheet" Target="/xl/worksheets/sheet2.xml"/></Relationships>""",
  ),
  (
    "xl/sharedStrings.xml",
    """<sst><si><t>alpha</t></si><si><r><t>be</t></r><r><t>ta</t></r></si><si><t>x</t><rPh><t>y</t></rPh></si></sst>""",
  ),
  (
    "xl/worksheets/sheet1.xml",
    """<worksheet><sheetData><row r="1"><c r="A1"><v>12</v></c><c r="B1" t="s"><v>0</v></c><c r="AB1" t="s"><v>2</v></c></row><row r="3"><c r="C3" t="inlineStr"><is><t>hi &amp; bye</t></is></c></row></sheetData></worksheet>""",
  ),
  (
    "xl/worksheets/sheet2.xml",
    """<worksheet><sheetData><row r="2"><c r="A2" t="s"><v>1</v></c><c r="Z2"><v>3.5</v></c></row></sheetData></worksheet>""",
  ),
]

const
  typesHeader = @["Type Name", "Base Type", "Value Name", "Value", "Comment"]
  messagesHeader = @[
    "Message Name", "Field Def #", "Field Name", "Field Type", "Array", "Components",
    "Scale", "Offset", "Units", "Bits", "Accumulate", "Ref Field Name",
    "Ref Field Value",
  ]

func field*(
    num, name, typ: string,
    scale = "",
    offset = "",
    accumulate = "",
    components = "",
    bits = "",
    refName = "",
    refValue = "",
): seq[string] =
  @[
    "", num, name, typ, "", components, scale, offset, "", bits, accumulate, refName,
    refValue,
  ]

func smallProfile*(): string =
  ## A profile with a little of everything the loader reads: enums, a date type, scales and offsets, accumulated fields,
  ## components, sub-fields (a reference field and its value).
  let types = @[
    typesHeader,
    @["mesg_num", "enum", "", "", ""],
    @["", "", "file_id", "0", ""],
    @["", "", "record", "20", ""],
    @["sport", "enum", "", "", ""],
    @["", "", "running", "1", ""],
    @["", "", "cycling", "2", ""],
    @["date_time", "uint32", "", "", ""],
    @["", "", "min", "268435456", ""],
  ]
  let messages = @[
    messagesHeader,
    @["record", "", "", "", "", "", "", "", "", "", "", "", ""],
    field("253", "timestamp", "date_time"),
    field("3", "heart_rate", "uint8", scale = "2", offset = "10"),
    field("5", "distance", "uint32", scale = "100", accumulate = "1"),
    field(
      "6", "speed", "uint16", scale = "1000", components = "enhanced_speed", bits = "16"
    ),
    field("73", "enhanced_speed", "uint32", scale = "1000"),
    field("7", "sport", "sport", refName = "heart_rate", refValue = "1"),
    @["file_id", "", "", "", "", "", "", "", "", "", "", "", ""],
    field("0", "type", "sport"),
  ]
  xlsxFile(@[("Types", types), ("Messages", messages)])

const requestAddresses* = [
  "/map?selection=AsBO&state=ab12cd&token=T0kEn", "/map?selection=AsBO",
  "/ff?model=default&from=2020-01-02&to=2020-12-31&fitness-scale=1.5&fatigue-scale=2&hourly=1&utc=1",
  "/ff?state=0a1b2c", "/files/map-lusab-babad-fuzoh.geojson",
  "/files/ff--model-default.html", "/", "/map", "/files/a%2Eb", "/x?a=1&b=%20c&d",
]
