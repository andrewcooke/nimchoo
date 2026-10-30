## Build small xlsx files for tests: stored (not deflated) zips, inline strings.

import std/strutils

func le16*(x: int): string = $char(x and 0xff) & $char((x shr 8) and 0xff)
func le32*(x: int): string = le16(x and 0xffff) & le16((x shr 16) and 0xffff)

func storedZip*(files: seq[(string, string)]): string =
  var body, central = ""
  for (name, data) in files:
    let offset = body.len
    body.add "PK\3\4" & le16(20) & le16(0) & le16(0) & le16(0) & le16(0) &
      le32(0) & le32(data.len) & le32(data.len) & le16(name.len) & le16(0) &
      name & data
    central.add "PK\1\2" & le16(20) & le16(20) & le16(0) & le16(0) & le16(0) &
      le16(0) & le32(0) & le32(data.len) & le32(data.len) & le16(name.len) &
      le16(0) & le16(0) & le16(0) & le16(0) & le32(0) & le32(offset) & name
  body & central & "PK\5\6" & le16(0) & le16(0) & le16(files.len) &
    le16(files.len) & le32(central.len) & le32(body.len) & le16(0)

func columnName(c: int): string =
  var n = c + 1
  while n > 0:
    result = $char(ord('A') + (n - 1) mod 26) & result
    n = (n - 1) div 26

func sheetXml*(rows: seq[seq[string]]): string =
  ## A worksheet whose cells (empty strings are left out) are inline strings.
  result = "<worksheet><sheetData>"
  for r, row in rows:
    result.add "<row r=\"" & $(r + 1) & "\">"
    for c, v in row:
      if v.len > 0:
        result.add "<c r=\"" & columnName(c) & $(r + 1) &
          "\" t=\"inlineStr\"><is><t>" &
          v.replace("&", "&amp;").replace("<", "&lt;") & "</t></is></c>"
    result.add "</row>"
  result.add "</sheetData></worksheet>"

func xlsxFile*(sheets: seq[(string, seq[seq[string]])]): string =
  ## An xlsx file with the given sheets (name, rows of cell text).
  var wb = "<workbook xmlns:r=\"r\"><sheets>"
  var rels = "<Relationships>"
  var files: seq[(string, string)]
  for i, (name, rows) in sheets:
    wb.add "<sheet name=\"" & name & "\" sheetId=\"" & $(i + 1) &
      "\" r:id=\"rId" & $(i + 1) & "\"/>"
    rels.add "<Relationship Id=\"rId" & $(i + 1) & "\" Type=\"worksheet\" " &
      "Target=\"worksheets/s" & $(i + 1) & ".xml\"/>"
    files.add ("xl/worksheets/s" & $(i + 1) & ".xml", sheetXml(rows))
  wb.add "</sheets></workbook>"
  rels.add "</Relationships>"
  storedZip(@[("xl/workbook.xml", wb), ("xl/_rels/workbook.xml.rels", rels)] &
            files)

func xlsxWithSheetXml*(xml: string): string =
  ## An xlsx file whose only sheet, "One", has this (possibly bad) xml.
  storedZip(@[
    ("xl/workbook.xml", "<workbook xmlns:r=\"r\"><sheets><sheet name=\"One\" " &
      "sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"),
    ("xl/_rels/workbook.xml.rels", "<Relationships><Relationship Id=\"rId1\" " &
      "Type=\"worksheet\" Target=\"worksheets/s1.xml\"/></Relationships>"),
    ("xl/worksheets/s1.xml", xml)])
