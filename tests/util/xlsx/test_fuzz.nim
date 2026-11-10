## Fuzzing of the xlsx reader (`openWorkbook`, `rows`), which reads Profile.xlsx (a file the user can name with
## `--profile`): a workbook that uses all it understands (shared strings, rich text, inline strings, both ways of naming a
## sheet's file) is damaged, in its zip container and in the xml of each part.  The result must be success or an
## `XlsxError`, never a Defect or a long wait.  Fixed seed; a failing input is saved.
##
## NCH_FUZZ_ROUNDS (default 60) scales the length: 40 files per round.

import std/[monotimes, os, random, strutils, tables, times, unittest]
import nimchoo/core/errors
import nimchoo/packages/util/xlsx/xlsx
import ../../support/[fuzzfiles, xlsxbuilder, xlsxmutate]

const parts = @[
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

proc useXlsx(x: string) {.raises: [XlsxError].} =
  ## Everything the program does with a workbook: open it, read its sheets.
  let wb = openWorkbook(x)
  for sheet in ["One", "Two", "Missing"]:
    try:
      for row in wb.rows(sheet):
        discard row.cell(0)
    except XlsxError:
      discard # (a bad sheet does not stop the others being read)

suite "xlsx fuzzing":
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  test "the workbook that is damaged is good to begin with":
    let wb = openWorkbook(storedZip(parts))
    check wb.rows("One")[0].cell(1) == "alpha"
    check wb.rows("One")[0].cell(27) == "x"
    check wb.rows("One")[2].cell(2) == "hi & bye"
    check wb.rows("Two")[1].cell(0) == "beta"
    check wb.rows("Two")[1].cell(25) == "3.5"

  test "damaged workbooks end in success or an XlsxError, and quickly":
    var r = initRand(20261114)
    var failures: Table[string, string] # what was wrong -> where the input was saved
    var runs, ok = 0
    for round in 0 ..< rounds * 40:
      let x = r.damagedXlsx(parts)
      inc runs
      var what = ""
      let started = getMonoTime()
      try:
        useXlsx(x)
        inc ok
      except XlsxError:
        discard
      except Exception as e: # the point of the test: nothing else may be raised
        what = signatureOf(e)
      if what == "" and (getMonoTime() - started).inMilliseconds > 2000:
        what = "took more than 2 s"
      if what != "" and what notin failures:
        failures[what] = saveFailure("xlsx", "xlsx", round, bytesOf(x), ".xlsx")
    let stats = $runs & " workbooks, " & $ok & " read"
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for what, saved in failures:
      checkpoint what & "  (saved: " & saved & ")"
    check failures.len == 0
    check ok > runs div 10
      # (damage that is always refused would test nothing past the checks)

  test "files that once broke the reader end in success or an XlsxError":
    for path in savedFailures("xlsx", ".xlsx"):
      try:
        useXlsx(readFile(path))
      except XlsxError:
        discard
