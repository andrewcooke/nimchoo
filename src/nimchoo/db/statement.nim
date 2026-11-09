## Prepared statements that can be run many times (the importer inserts
## thousands of coordinates).  A thin typed layer over SQLite's C interface,
## because `db_sqlite`'s prepared statements are single-use.  Errors become
## `StoreError`.
##
## On top of that, the typed way to use it (`query`, `queryOne`, `scalar`, `execute`): values are bound by their
## Nim type, never put into the text of the sql, and a row is read into a tuple or an object whose field types say
## what each column must be.  A column of another type than the field's, a NULL for a field that is not an
## `Option`, or a row of another width than the tuple, is a `StoreError` that names the column.

import std/[macros, options]
import db_connector/db_sqlite
from db_connector/sqlite3 import
  PStmt, column_count, column_double, column_int64, column_name, column_type,
  SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_NULL, SQLITE_BLOB, prepare_v2,
  bind_int64, bind_double, bind_null, bind_text, bind_blob, SQLITE_TRANSIENT, step,
  reset, clear_bindings, finalize, errmsg, last_insert_rowid, exec, free, SQLITE_OK,
  SQLITE_DONE, SQLITE_ROW, column_blob, column_bytes
import ../errors
import ../ids

{.push raises: [].}

type
  StmtObj = object
    raw: PStmt
    db: DbConn

  Stmt* = ref StmtObj
    ## A prepared statement.  A handle that may be copied freely: the statement is finalized when
    ## the last copy goes (so it must go before the database connection is closed: a statement
    ## made in a procedure does, being gone when the procedure ends).

proc `=destroy`(s: StmtObj) {.raises: [].} =
  if s.raw != nil:
    discard finalize(s.raw)

proc fail(db: DbConn, what: string) {.noreturn, raises: [StoreError].} =
  raiseStore(what & ": " & $errmsg(db))

proc prepareStmt*(db: DbConn, sql: string): Stmt {.raises: [StoreError].} =
  ## Compile one statement; `?` marks the values to bind (numbered from 1).
  var raw: PStmt
  if prepare_v2(db, cstring(sql), cint(sql.len), raw, nil) != SQLITE_OK:
    fail(db, "cannot prepare '" & sql & "'")
  Stmt(raw: raw, db: db)

proc bindInt*(s: Stmt, i: int, v: int64) {.raises: [StoreError].} =
  ## Bind a whole number (or an id) to parameter `i` (counted from 1).
  if bind_int64(s.raw, int32(i), v) != SQLITE_OK:
    fail(s.db, "cannot bind")

proc bindInt*(s: Stmt, i: int, v: AnyId) {.raises: [StoreError].} =
  ## Bind a whole number (or an id) to parameter `i` (counted from 1).
  s.bindInt(i, int64(v))

proc bindReal*(s: Stmt, i: int, v: float) {.raises: [StoreError].} =
  ## Bind a real number to parameter `i`; an absent one binds nothing (the parameter stays null).
  if bind_double(s.raw, int32(i), v) != SQLITE_OK:
    fail(s.db, "cannot bind")

proc bindText*(s: Stmt, i: int, v: string) {.raises: [StoreError].} =
  ## Bind text to parameter `i` (copied).
  if bind_text(s.raw, int32(i), cstring(v), int32(v.len), SQLITE_TRANSIENT) != SQLITE_OK:
    fail(s.db, "cannot bind")

proc bindBlob*(s: Stmt, i: int, v: string) {.raises: [StoreError].} =
  ## Bytes (the contents of a string, which may hold any byte) as a BLOB.
  if bind_blob(s.raw, int32(i), cstring(v), int32(v.len), SQLITE_TRANSIENT) != SQLITE_OK:
    fail(s.db, "cannot bind")

proc bindNull*(s: Stmt, i: int) {.raises: [StoreError].} =
  ## Bind null to parameter `i`.
  if bind_null(s.raw, int32(i)) != SQLITE_OK:
    fail(s.db, "cannot bind")

proc bindInt*(s: Stmt, i: int, v: Option[int]) {.raises: [StoreError].} =
  ## A number, or NULL if there is none.
  if v.isSome:
    s.bindInt(i, int64(v.get))
  else:
    s.bindNull(i)

proc bindReal*(s: Stmt, i: int, v: Option[float]) {.raises: [StoreError].} =
  ## Bind a real number to parameter `i`; an absent one binds nothing (the parameter stays null).
  if v.isSome:
    s.bindReal(i, v.get)
  else:
    s.bindNull(i)

proc bindOptText*(s: Stmt, i: int, v: string) {.raises: [StoreError].} =
  ## Text, or NULL if it is empty.
  if v.len > 0:
    s.bindText(i, v)
  else:
    s.bindNull(i)

proc run*(s: Stmt) {.raises: [StoreError].} =
  ## Run the statement (an insert, update or delete) with the values bound so
  ## far, then get it ready for the next set.
  let rc = step(s.raw)
  let bad = rc != SQLITE_DONE
  let message =
    if bad:
      $errmsg(s.db)
    else:
      ""
  discard reset(s.raw)
  discard clear_bindings(s.raw)
  if bad:
    raiseStore(message)

proc nextRow*(s: Stmt): bool {.raises: [StoreError].} =
  ## Step to the next row of a query; false when there are no more.  (Call `rewind` before running the query again.)
  let rc = step(s.raw)
  if rc == SQLITE_ROW:
    return true
  if rc != SQLITE_DONE:
    fail(s.db, "cannot read")
  false

proc blobAt*(s: Stmt, i: int): string =
  ## The bytes of column `i` (counted from 0) of the current row, whatever they are (zeros included); "" if it is null.
  let n = int(column_bytes(s.raw, int32(i)))
  if n <= 0:
    return ""
  result = newString(n)
  copyMem(addr result[0], column_blob(s.raw, int32(i)), n)

proc rewind*(s: Stmt) =
  ## Get the statement ready to run again with new values.
  discard reset(s.raw)
  discard clear_bindings(s.raw)

proc lastInsertId*(db: DbConn): int64 {.raises: [].} =
  ## The id of the row most recently inserted on this connection.
  last_insert_rowid(db)

proc execScript*(db: DbConn, script: string) {.raises: [StoreError].} =
  ## Run a script of several statements.  (If one fails the ones before it
  ## have been done: run it inside a transaction.)
  var err: cstring
  if exec(db, cstring(script), nil, nil, err) != SQLITE_OK:
    let message =
      if err.isNil:
        $errmsg(db)
      else:
        $err
    if not err.isNil:
      free(err)
    raiseStore(message)

# --- typed binding -------------------------------------------------------------------------------------------

proc bindValue*(s: Stmt, i: int, v: int) {.raises: [StoreError].} =
  s.bindInt(i, int64(v))

proc bindValue*(s: Stmt, i: int, v: int64) {.raises: [StoreError].} =
  s.bindInt(i, v)

proc bindValue*(s: Stmt, i: int, v: AnyId) {.raises: [StoreError].} =
  s.bindInt(i, int64(v))

proc bindValue*(s: Stmt, i: int, v: float) {.raises: [StoreError].} =
  s.bindReal(i, v)

proc bindValue*(s: Stmt, i: int, v: string) {.raises: [StoreError].} =
  ## (An empty string is empty text, not NULL: NULL is an absent `Option`.)
  s.bindText(i, v)

proc bindValue*[T](s: Stmt, i: int, v: Option[T]) {.raises: [StoreError].} =
  if v.isSome:
    s.bindValue(i, v.get)
  else:
    s.bindNull(i)

macro bindArgs(s: Stmt, args: varargs[untyped]): untyped =
  ## `bindValue` for each argument, numbered from 1.
  result = newStmtList()
  for n, a in args:
    result.add newCall(bindSym"bindValue", s, newLit(n + 1), a)

# --- typed reading -------------------------------------------------------------------------------------------

proc typeName(t: int32): string =
  case t
  of SQLITE_INTEGER: "an integer"
  of SQLITE_FLOAT: "a real number"
  of SQLITE_TEXT: "text"
  of SQLITE_BLOB: "a blob"
  of SQLITE_NULL: "null"
  else: "something unknown"

proc wrong(s: Stmt, i: int, want: string) {.noreturn, raises: [StoreError].} =
  raiseStore(
    "column " & $i & " (" & $column_name(s.raw, int32(i)) & ") is " &
      typeName(column_type(s.raw, int32(i))) & ", not " & want
  )

proc readCol*(s: Stmt, i: int, v: var int64) {.raises: [StoreError].} =
  if column_type(s.raw, int32(i)) != SQLITE_INTEGER:
    wrong(s, i, "an integer")
  v = column_int64(s.raw, int32(i))

proc readCol*(s: Stmt, i: int, v: var int) {.raises: [StoreError].} =
  var w: int64
  s.readCol(i, w)
  v = int(w)

proc readCol*(s: Stmt, i: int, v: var AnyId) {.raises: [StoreError].} =
  var w: int64
  s.readCol(i, w)
  v = typeof(v)(w)

proc readCol*(s: Stmt, i: int, v: var float) {.raises: [StoreError].} =
  ## (A whole number is read as a real number: SQLite gives `0` for `coalesce(x, 0)`.)
  let t = column_type(s.raw, int32(i))
  if t != SQLITE_FLOAT and t != SQLITE_INTEGER:
    wrong(s, i, "a real number")
  v = column_double(s.raw, int32(i))

proc readCol*(s: Stmt, i: int, v: var string) {.raises: [StoreError].} =
  if column_type(s.raw, int32(i)) != SQLITE_TEXT:
    wrong(s, i, "text")
  v = s.blobAt(i)

proc readCol*[T](s: Stmt, i: int, v: var Option[T]) {.raises: [StoreError].} =
  ## NULL is `none`; anything else must be a `T`.
  if column_type(s.raw, int32(i)) == SQLITE_NULL:
    v = none(T)
  else:
    var w: T
    s.readCol(i, w)
    v = some(w)

proc readRow[T](s: Stmt): T {.raises: [StoreError].} =
  ## The current row as a `T`: a tuple or object (one column for each field, in order), or a single value.
  when T is tuple or T is object:
    var want = 0
    for _ in fields(result):
      inc want
    if int(column_count(s.raw)) != want:
      raiseStore("the query has " & $column_count(s.raw) & " columns, not " & $want)
    var n = 0
    for f in fields(result):
      s.readCol(n, f)
      inc n
  else:
    if column_count(s.raw) != 1:
      raiseStore("the query has " & $column_count(s.raw) & " columns, not 1")
    s.readCol(0, result)

proc fetchAll*[T](s: Stmt): seq[T] {.raises: [StoreError].} =
  while s.nextRow():
    result.add readRow[T](s)

proc fetchOne*[T](s: Stmt): Option[T] {.raises: [StoreError].} =
  if s.nextRow():
    result = some(readRow[T](s))

template query*(
    db: DbConn, T: typedesc, sqlText: string, args: varargs[untyped]
): seq[T] =
  ## All the rows of the query as `T`s (a tuple, an object, or one value for a one-column query); the `args` are
  ## bound to the `?`s by their types.
  block:
    let stmt = prepareStmt(db, sqlText)
    bindArgs(stmt, args)
    fetchAll[T](stmt)

template queryOne*(
    db: DbConn, T: typedesc, sqlText: string, args: varargs[untyped]
): Option[T] =
  ## The first row, or `none` if there is none.
  block:
    let stmt = prepareStmt(db, sqlText)
    bindArgs(stmt, args)
    fetchOne[T](stmt)

proc theRow[T](got: Option[T], sqlText: string): T {.raises: [StoreError].} =
  if got.isNone:
    raiseStore("the query gave no row: " & sqlText)
  got.get

template scalar*(
    db: DbConn, T: typedesc, sqlText: string, args: varargs[untyped]
): untyped =
  ## The one value a query is sure to give (`select count(*) ...`); no row at all is a `StoreError`.
  block:
    let stmt = prepareStmt(db, sqlText)
    bindArgs(stmt, args)
    theRow(fetchOne[T](stmt), sqlText)

template execute*(db: DbConn, sqlText: string, args: varargs[untyped]) =
  ## Run an insert, update or delete with the `args` bound.
  block:
    let stmt = prepareStmt(db, sqlText)
    bindArgs(stmt, args)
    stmt.run()
