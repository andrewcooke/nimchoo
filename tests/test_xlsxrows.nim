import std/[strutils, tables, unittest]
import nimchoo/xlsxrows
import ./xlsxbuilder

const profile = "../choochoo/data/sdk/Profile.xlsx"

suite "xlsxrows":
  test "Types sheet: known value":
    let rows = sheetRows(profile, "Types")
    check rows[0].cell(0) == "Type Name"
    var found = false
    for r in rows:
      if r.cell(2) == "farmers_walk":
        check r.cell(3) == "1"
        found = true
    check found

  test "absent cells are empty strings":
    let rows = sheetRows(profile, "Types")
    check rows[1].cell(99) == ""

  test "from memory and from a file give the same rows":
    let wb = openWorkbook(readFile(profile))
    check wb.sheetNames.len == 2
    check wb.rows("Messages") == sheetRows(profile, "Messages")

# --- small hand-made xlsx files (stored, not deflated, zips)

const
  sheetBody = """<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1"><v>42</v></c></row>
<row r="3"><c r="B3" t="s"><v>1</v></c><c r="D3" t="inlineStr"><is><t>inline</t></is></c><c r="AA3" t="s"><v>2</v></c></row>"""
  shared = """<si><t>plain</t></si><si><r><t>rich </t></r><r><t>text</t></r></si><si><t>a &amp; b &#65;</t></si>"""

func workbook(prefix, bom: string): string =
  ## An xlsx with one sheet "One", elements optionally with a namespace prefix.
  let p = prefix
  storedZip(@[
    ("xl/workbook.xml", bom & "<" & p & "workbook xmlns:r=\"r\"><" & p &
     "sheets><" & p & "sheet name=\"One\" sheetId=\"1\" r:id=\"rId1\"/></" & p &
     "sheets></" & p & "workbook>"),
    ("xl/_rels/workbook.xml.rels", "<Relationships><Relationship Id=\"rId1\" " &
     "Type=\"worksheet\" Target=\"worksheets/s1.xml\"/></Relationships>"),
    ("xl/sharedStrings.xml", bom & "<" & p & "sst>" &
     shared.replace("<", "<" & p).replace("<" & p & "/", "</" & p) & "</" & p & "sst>"),
    ("xl/worksheets/s1.xml", bom & "<" & p & "worksheet><" & p & "sheetData>" &
     sheetBody.replace("<", "<" & p).replace("<" & p & "/", "</" & p) &
     "</" & p & "sheetData></" & p & "worksheet>")])

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
