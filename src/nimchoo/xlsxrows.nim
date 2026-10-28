## Adapter: rows of cell values for a sheet of an xlsx file.
## Hides the xlsx library so it can be replaced (see TODO.md, task 1).

import std/tables
import xl

type
  Row* = Table[int, string]  ## sparse row: 0-based column -> value

proc sheetRows*(path, sheet: string): seq[Row] =
  ## All rows of `sheet`, indexed by 0-based row number.  Empty rows are
  ## empty tables.  Cells are strings (numbers are not converted).
  let wb = load(path)
  for c in wb.cells(sheet):
    let (r, col) = c.rc
    while result.len <= r:
      result.add initTable[int, string]()
    result[r][col] = c.value

proc cell*(row: Row, col: int): string =
  ## Value in column `col`, or "" if absent.
  row.getOrDefault(col)
