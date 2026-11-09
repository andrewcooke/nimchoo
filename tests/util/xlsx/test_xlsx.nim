import std/[strutils, tables, unittest]
import nimchoo/packages/util/xlsx/xlsx
import ../../support/xlsxbuilder

const profile = "../choochoo/data/sdk/Profile.xlsx"

proc readWorkbook(path: string): Workbook =
  openWorkbook(readFile(path))

suite "xlsx files":
  test "Types sheet: known value":
    let rows = readWorkbook(profile).rows("Types")
    check rows[0].cell(0) == "Type Name"
    var found = false
    for r in rows:
      if r.cell(2) == "farmers_walk":
        check r.cell(3) == "1"
        found = true
    check found

  test "absent cells are empty strings":
    let rows = readWorkbook(profile).rows("Types")
    check rows[1].cell(99) == ""

  test "from memory and from a file give the same rows":
    let wb = openWorkbook(readFile(profile))
    check wb.rows("Messages") == readWorkbook(profile).rows("Messages")

# --- small hand-made xlsx files (stored, not deflated, zips)

const
  sheetBody = """<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1"><v>42</v></c></row>
<row r="3"><c r="B3" t="s"><v>1</v></c><c r="D3" t="inlineStr"><is><t>inline</t></is></c><c r="AA3" t="s"><v>2</v></c></row>"""
  shared =
    """<si><t>plain</t></si><si><r><t>rich </t></r><r><t>text</t></r></si><si><t>a &amp; b &#65;</t></si>"""

func workbook(prefix, bom: string): string =
  ## An xlsx with one sheet "One", elements optionally with a namespace prefix.
  let p = prefix
  storedZip(
    @[
      (
        "xl/workbook.xml",
        bom & "<" & p & "workbook xmlns:r=\"r\"><" & p & "sheets><" & p &
          "sheet name=\"One\" sheetId=\"1\" r:id=\"rId1\"/></" & p & "sheets></" & p &
          "workbook>",
      ),
      (
        "xl/_rels/workbook.xml.rels",
        "<Relationships><Relationship Id=\"rId1\" " &
          "Type=\"worksheet\" Target=\"worksheets/s1.xml\"/></Relationships>",
      ),
      (
        "xl/sharedStrings.xml",
        bom & "<" & p & "sst>" &
          shared.replace("<", "<" & p).replace("<" & p & "/", "</" & p) & "</" & p &
          "sst>",
      ),
      (
        "xl/worksheets/s1.xml",
        bom & "<" & p & "worksheet><" & p & "sheetData>" &
          sheetBody.replace("<", "<" & p).replace("<" & p & "/", "</" & p) & "</" & p &
          "sheetData></" & p & "worksheet>",
      ),
    ]
  )

proc check1(wb: Workbook) =
  let rows = wb.rows("One")
  check rows.len == 3
  check rows[0] == {0: "plain", 2: "42"}.toTable
  check rows[1].len == 0
  check rows[2] == {1: "rich text", 3: "inline", 26: "a & b A"}.toTable

suite "xlsx reader":
  test "shared strings (rich text, entities), numbers, inline strings":
    check1 openWorkbook(workbook("", ""))

  test "namespace prefixes and a byte order mark":
    check1 openWorkbook(workbook("x:", "\xEF\xBB\xBF"))

  test "not an xlsx file":
    expect XlsxError:
      discard openWorkbook("this is not a zip file at all")
    expect XlsxError:
      discard openWorkbook("")
    expect XlsxError:
      discard openWorkbook(storedZip(@[("a.txt", "hello")]))

  test "no such sheet":
    let wb = openWorkbook(workbook("", ""))
    expect XlsxError:
      discard wb.rows("Two")

  test "truncated file":
    let z = workbook("", "")
    expect XlsxError:
      discard openWorkbook(z[0 ..< z.len div 2])

proc sheetError(xml: string): string =
  ## The message of the XlsxError for a workbook with this sheet xml.
  try:
    discard openWorkbook(xlsxWithSheetXml(xml)).rows("One")
  except XlsxError as e:
    return e.msg
  "no error"

func cell(r: string): string =
  "<worksheet><sheetData><row r=\"1\"><c r=\"" & r &
    "\"><v>1</v></c></row></sheetData></worksheet>"

suite "xlsx reader: bad input":
  test "malformed xml is an error that names the file":
    let msg = sheetError("<worksheet><![CDATA[ never closed")
    check "s1.xml" in msg
    check msg != "no error"
    check sheetError(
      "<worksheet><sheetData><row r=\"1\"><c r=A1><v>1</v></c>" &
        "</row></sheetData></worksheet>"
    ) != "no error"

  test "malformed workbook xml":
    let z = storedZip(
      @[
        ("xl/workbook.xml", "<workbook><![CDATA[ never closed"),
        ("xl/_rels/workbook.xml.rels", "<Relationships/>"),
      ]
    )
    expect XlsxError:
      discard openWorkbook(z)

  test "cell references are bounded as in Excel":
    check "out of range" in sheetError(cell("A99999999999"))
    check "out of range" in sheetError(cell("XFE1")) # column 16385
    check "out of range" in sheetError(cell("A1048577")) # row 1048577
    check "bad cell reference" in sheetError(cell("12"))
    check "bad cell reference" in sheetError(cell("a1"))
    check sheetError(cell("XFD1")) == "no error" # the last column

  test "a shared string index that does not exist":
    check "bad shared string" in
      sheetError(
        "<worksheet><sheetData><row r=\"1\"><c r=\"A1\" t=\"s\"><v>7</v></c>" &
          "</row></sheetData></worksheet>"
      )

  test "a zip entry whose size is not as declared":
    var z = xlsxWithSheetXml(cell("A1"))
    let central = z.find("PK\1\2")
    check central > 0
    z[central + 24 ..< central + 28] = le32(999) # the first entry's size
    expect XlsxError:
      discard openWorkbook(z)
