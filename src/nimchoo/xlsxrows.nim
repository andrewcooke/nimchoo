## Rows of cell values for a sheet of an xlsx file (a thin layer over xlsx.nim).

import std/tables
import ./xlsx
export xlsx

proc sheetRows*(path, sheet: string): seq[Row] =
  ## All rows of `sheet` of the xlsx file at `path`, indexed by 0-based row
  ## number.  Empty rows are empty tables.  Cells are strings (numbers are not
  ## converted).
  openWorkbook(readFile(path)).rows(sheet)

func cell*(row: Row, col: int): string =
  ## Value in column `col`, or "" if absent.
  row.getOrDefault(col)
