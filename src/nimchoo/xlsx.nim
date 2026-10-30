## A minimal xlsx reader: just enough to read the cell values of worksheets as
## strings, from bytes in memory.  An xlsx file is a zip of XML files; we read
## the zip directory ourselves (zippy only opens zips from a path) and inflate
## entries with zippy.
##
## Cell values are returned as the text in the file: numbers are not
## converted, shared strings are resolved, formulas are not evaluated.

import std/[parsexml, streams, strutils, tables]
import zippy
import ./errors
import ./lookup
import ./fit/bytes
export errors

{.push raises: [].}

type
  Row* = Table[int, string]  ## sparse row: 0-based column -> value

  ZipEntry = object
    compression, compressedSize, size, offset: int

  Workbook* = object
    data: string
    entries: Table[string, ZipEntry]
    sheets: Table[string, string]   ## sheet name -> path of its xml in the zip
    shared: seq[string]             ## shared strings

# --- zip

func le(s: string, o, size: int): int {.raises: [XlsxError].} =
  ## The `size` bytes at `o` as a little-endian integer.
  if not s.toOpenArrayByte(0, s.high).canRead(o, size):
    raiseXlsx("truncated zip file")
  int(getUint(s.toOpenArrayByte(0, s.high), o, size))

func u16(s: string, o: int): int {.raises: [XlsxError].} = le(s, o, 2)

func u32(s: string, o: int): int {.raises: [XlsxError].} = le(s, o, 4)

func zipEntries(z: string): Table[string, ZipEntry] {.raises: [XlsxError].} =
  ## The central directory of a zip file.
  var eocd = -1
  var i = z.len - 22
  while i >= 0 and i >= z.len - 22 - 65535:
    if z[i] == 'P' and z[i + 1] == 'K' and z[i + 2] == '\5' and z[i + 3] == '\6':
      eocd = i
      break
    dec i
  if eocd < 0: raiseXlsx("not a zip file")
  var p = u32(z, eocd + 16)
  for _ in 0 ..< u16(z, eocd + 10):
    if u32(z, p) != 0x02014b50:
      raiseXlsx("bad zip central directory")
    let nameLen = u16(z, p + 28)
    if p + 46 + nameLen > z.len:
      raiseXlsx("truncated zip file")
    result[z[p + 46 ..< p + 46 + nameLen]] = ZipEntry(
      compression: u16(z, p + 10), compressedSize: u32(z, p + 20),
      size: u32(z, p + 24),
      offset: u32(z, p + 42))
    p += 46 + nameLen + u16(z, p + 30) + u16(z, p + 32)

const maxEntrySize = 256 * 1024 * 1024  ## larger declared sizes are refused

func extract(z: string, e: ZipEntry): string {.raises: [XlsxError].} =
  let p = e.offset
  if e.size > maxEntrySize: raiseXlsx("zip entry too large")
  if u32(z, p) != 0x04034b50:
    raiseXlsx("bad zip local header")
  let start = p + 30 + u16(z, p + 26) + u16(z, p + 28)
  if start + e.compressedSize > z.len:
    raiseXlsx("truncated zip file")
  let raw = z[start ..< start + e.compressedSize]
  case e.compression
  of 0:
    if raw.len != e.size: raiseXlsx("zip entry has the wrong size")
    raw
  of 8:
    let data =
      try: uncompress(raw, dfDeflate)
      except ZippyError as ex:
        raiseXlsx("cannot inflate: " & ex.msg)
    if data.len != e.size: raiseXlsx("zip entry has the wrong size")
    data
  else:
    raiseXlsx("unsupported zip compression " & $e.compression)

proc file(wb: Workbook, path: string): string {.raises: [XlsxError].} =
  if path notin wb.entries:
    raiseXlsx("no " & path & " in the xlsx file")
  extract(wb.data, wb.entries.must(path))

# --- xml

proc openXml(xml, path: string): XmlParser {.raises: [XlsxError].} =
  ## `path` (the name in the zip) appears in error messages.
  const bom = "\xEF\xBB\xBF"
  let text = if xml.startsWith(bom): xml[bom.len .. ^1] else: xml
  try:
    result.open(newStringStream(text), path, {reportWhitespace})
  except IOError, OSError:
    raiseXlsx(path & ": " & getCurrentExceptionMsg())

proc nextEvent(x: var XmlParser) {.raises: [XlsxError].} =
  ## `x.next()`.  (parsexml can raise ValueError for a bad character reference.)
  try:
    x.next()
  except ValueError, IOError, OSError:
    raiseXlsx("malformed xml: " & getCurrentExceptionMsg())

proc xmlProblem(x: XmlParser): string {.raises: [].} =
  ## The parser's description of what is wrong, with file, line and column.
  try: x.errorMsg
  except ValueError: "malformed xml"

proc closeXml(x: var XmlParser) {.raises: [].} =
  ## Close the parser.  (It reads an in-memory string, so there is nothing
  ## useful to do if closing it were to fail.)
  try: x.close()
  except IOError, OSError: discard

func local(name: string): string =
  ## An element or attribute name without its namespace prefix.
  let i = name.rfind(':')
  if i < 0: name else: name[i + 1 .. ^1]

proc parseSharedStrings(xml, path: string): seq[string] {.raises: [XlsxError].} =
  ## One string per <si>: the text of its <t> elements (rich text runs are
  ## joined; phonetic runs <rPh> are left out).
  var x = openXml(xml, path)
  defer: x.closeXml()
  var inT, inPh = false
  var cur = ""
  while true:
    x.nextEvent()
    case x.kind
    of xmlEof: break
    of xmlError: raiseXlsx(xmlProblem(x))
    of xmlElementStart, xmlElementOpen:
      case local(x.elementName)
      of "si": cur = ""
      of "t": inT = true
      of "rPh": inPh = true
      else: discard
    of xmlElementEnd:
      case local(x.elementName)
      of "si": result.add cur
      of "t": inT = false
      of "rPh": inPh = false
      else: discard
    of xmlCharData, xmlWhitespace, xmlCData:
      if inT and not inPh: cur.add x.charData
    else: discard

proc parseRelationships(xml, path: string): Table[string, string] {.raises: [XlsxError].} =
  ## id -> target
  var x = openXml(xml, path)
  defer: x.closeXml()
  var id, target = ""
  while true:
    x.nextEvent()
    case x.kind
    of xmlEof: break
    of xmlError: raiseXlsx(xmlProblem(x))
    of xmlElementOpen:
      if local(x.elementName) == "Relationship": id = ""; target = ""
    of xmlAttribute:
      case x.attrKey
      of "Id": id = x.attrValue
      of "Target": target = x.attrValue
      else: discard
    of xmlElementClose, xmlElementEnd:
      if id.len > 0 and target.len > 0:
        result[id] = target
        id = ""; target = ""
    else: discard

proc parseSheetNames(xml, path: string): seq[(string, string)] {.raises: [XlsxError].} =
  ## (name, relationship id) of each sheet in workbook.xml
  var x = openXml(xml, path)
  defer: x.closeXml()
  var name, rid = ""
  var inSheet = false
  while true:
    x.nextEvent()
    case x.kind
    of xmlEof: break
    of xmlError: raiseXlsx(xmlProblem(x))
    of xmlElementOpen:
      inSheet = local(x.elementName) == "sheet"
      name = ""; rid = ""
    of xmlAttribute:
      if inSheet:
        case local(x.attrKey)
        of "name": name = x.attrValue
        of "id": rid = x.attrValue  # r:id (sheetId is a different name)
        else: discard
    of xmlElementClose, xmlElementEnd:
      if inSheet and name.len > 0:
        result.add (name, rid)
      inSheet = false
    else: discard

const
  maxRows = 1_048_576  ## as Excel
  maxCols = 16_384

func cellPosition(r: string): (int, int) {.raises: [XlsxError].} =
  ## (row, col), both 0-based, of a reference like "AB12"
  var col, row = 0
  var letters = 0
  for c in r:
    case c
    of 'A' .. 'Z':
      col = col * 26 + (ord(c) - ord('A') + 1)
      inc letters
    of '0' .. '9':
      row = row * 10 + (ord(c) - ord('0'))
    else:
      raiseXlsx("bad cell reference " & r)
    if col > maxCols or row > maxRows:
      raiseXlsx("cell reference out of range: " & r)
  if letters == 0 or row == 0:
    raiseXlsx("bad cell reference " & r)
  (row - 1, col - 1)

proc parseSheet(xml, path: string, shared: seq[string]): seq[Row] {.raises: [XlsxError].} =
  var x = openXml(xml, path)
  defer: x.closeXml()
  var cellRef, ctype, text = ""
  var inC, inV, inT = false
  while true:
    x.nextEvent()
    case x.kind
    of xmlEof: break
    of xmlError: raiseXlsx(xmlProblem(x))
    of xmlElementOpen, xmlElementStart:
      case local(x.elementName)
      of "c": inC = true; cellRef = ""; ctype = ""; text = ""
      of "v": inV = true
      of "t": inT = inC
      else: discard
    of xmlAttribute:
      if inC and not inV:
        case x.attrKey
        of "r": cellRef = x.attrValue
        of "t": ctype = x.attrValue
        else: discard
    of xmlElementEnd:
      case local(x.elementName)
      of "v": inV = false
      of "t": inT = false
      of "c":
        inC = false
        if text.len > 0:
          if cellRef.len == 0:
            raiseXlsx("cell without a reference")
          let (row, col) = cellPosition(cellRef)
          var value = text
          if ctype == "s":
            let i = try: parseInt(text) except ValueError: -1
            if i < 0 or i >= shared.len:
              raiseXlsx("bad shared string " & text)
            value = shared[i]
          while result.len <= row: result.add Row()
          result[row][col] = value
      else: discard
    of xmlCharData, xmlWhitespace, xmlCData:
      if inC and (inV or inT): text.add x.charData
    else: discard

# --- workbook

proc openWorkbook*(data: string): Workbook {.raises: [XlsxError].} =
  ## Raises XlsxError if `data` is not an xlsx file.
  result.data = data
  result.entries = zipEntries(data)
  const relsPath = "xl/_rels/workbook.xml.rels"
  let rels = parseRelationships(result.file(relsPath), relsPath)
  for (name, rid) in parseSheetNames(result.file("xl/workbook.xml"),
                                     "xl/workbook.xml"):
    if rid in rels:
      let target = rels.must(rid)
      result.sheets[name] =
        if target.startsWith("/"): target[1 .. ^1] else: "xl/" & target
  if "xl/sharedStrings.xml" in result.entries:
    result.shared = parseSharedStrings(result.file("xl/sharedStrings.xml"),
                                       "xl/sharedStrings.xml")

func sheetNames*(wb: Workbook): seq[string] =
  for name in wb.sheets.keys: result.add name

proc rows*(wb: Workbook, sheet: string): seq[Row] {.raises: [XlsxError].} =
  ## All rows of `sheet`, indexed by 0-based row number (empty rows are empty
  ## tables).  Raises XlsxError if there is no such sheet.
  if sheet notin wb.sheets:
    raiseXlsx("no sheet called " & sheet)
  parseSheet(wb.file(wb.sheets.must(sheet)), wb.sheets.must(sheet), wb.shared)

proc readWorkbook*(path: string): Workbook {.raises: [XlsxError, IOError].} =
  ## The xlsx file at `path`.
  openWorkbook(readFile(path))

func cell*(row: Row, col: int): string =
  ## Value in column `col` of a row, or "" if absent.
  row.getOrDefault(col)
