## Inserting many rows with few statements.  Each call to SQLite has a cost of its own (a step, a
## reset, binds one at a time); an `insert ... values (...), (...), ...` of 128 rows pays it once.  A
## file of thousands of coordinates is thousands of rows, so this is where a big import spends its
## time writing.
##
## The statements are prepared once for each number of rows asked for (the full 128, and whatever is
## left over at the end of an activity) and kept until `release`.

import std/[strutils, tables]
import ../util/lookup/lookup
import db_connector/db_sqlite
import ../../core/errors
import ./statement

{.push raises: [].}

const rowsPerStatement* = 128

type MultiInsert* = object
  db: DbConn
  head: string ## "insert into t(a, b) values "
  group: string ## "(?, ?)": one row
  stmts: Table[int, Stmt] ## by the number of rows

proc initMultiInsert*(db: DbConn, head: string, columns: int): MultiInsert =
  ## For inserts that start with `head` (ending in "values ") of rows of this many columns.
  result.db = db
  result.head = head
  result.group = "(" & repeat("?, ", columns - 1) & "?)"

proc statement*(m: var MultiInsert, rows: int): Stmt {.raises: [StoreError].} =
  ## The statement for exactly `rows` rows: its values are numbered row by row, so column `c`
  ## (from 1) of row `r` (from 0) is parameter `r * columns + c`.
  if rows notin m.stmts:
    var sql = m.head
    for r in 0 ..< rows:
      if r > 0:
        sql.add ", "
      sql.add m.group
    m.stmts[rows] = prepareStmt(m.db, sql)
  m.stmts.must(rows)
