## Prepared statements that can be run many times (the importer inserts
## thousands of coordinates).  A thin typed layer over SQLite's C interface,
## because `db_sqlite`'s prepared statements are single-use.  Errors become
## `StoreError`.

import std/options
import db_connector/db_sqlite
from db_connector/sqlite3 import PStmt, prepare_v2, bind_int64, bind_double,
    bind_null, bind_text, bind_blob, SQLITE_TRANSIENT, step, reset, clear_bindings,
    finalize, errmsg, last_insert_rowid, exec, free, SQLITE_OK, SQLITE_DONE
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
  if s.raw != nil: discard finalize(s.raw)

proc fail(db: DbConn, what: string) {.noreturn, raises: [StoreError].} =
  raiseStore(what & ": " & $errmsg(db))

proc prepareStmt*(db: DbConn, sql: string): Stmt {.raises: [StoreError].} =
  ## Compile one statement; `?` marks the values to bind (numbered from 1).
  var raw: PStmt
  if prepare_v2(db, cstring(sql), cint(sql.len), raw, nil) != SQLITE_OK:
    fail(db, "cannot prepare '" & sql & "'")
  Stmt(raw: raw, db: db)

proc bindInt*(s: Stmt, i: int, v: int64) {.raises: [StoreError].} =
  if bind_int64(s.raw, int32(i), v) != SQLITE_OK: fail(s.db, "cannot bind")

proc bindInt*(s: Stmt, i: int, v: AnyId) {.raises: [StoreError].} =
  s.bindInt(i, int64(v))

proc bindReal*(s: Stmt, i: int, v: float) {.raises: [StoreError].} =
  if bind_double(s.raw, int32(i), v) != SQLITE_OK: fail(s.db, "cannot bind")

proc bindText*(s: Stmt, i: int, v: string) {.raises: [StoreError].} =
  if bind_text(s.raw, int32(i), cstring(v), int32(v.len),
               SQLITE_TRANSIENT) != SQLITE_OK:
    fail(s.db, "cannot bind")

proc bindBlob*(s: Stmt, i: int, v: string) {.raises: [StoreError].} =
  ## Bytes (the contents of a string, which may hold any byte) as a BLOB.
  if bind_blob(s.raw, int32(i), cstring(v), int32(v.len), SQLITE_TRANSIENT) != SQLITE_OK:
    fail(s.db, "cannot bind")

proc bindNull*(s: Stmt, i: int) {.raises: [StoreError].} =
  if bind_null(s.raw, int32(i)) != SQLITE_OK: fail(s.db, "cannot bind")

proc bindInt*(s: Stmt, i: int, v: Option[int]) {.raises: [StoreError].} =
  ## A number, or NULL if there is none.
  if v.isSome: s.bindInt(i, int64(v.get)) else: s.bindNull(i)

proc bindReal*(s: Stmt, i: int, v: Option[float]) {.raises: [StoreError].} =
  if v.isSome: s.bindReal(i, v.get) else: s.bindNull(i)

proc bindOptText*(s: Stmt, i: int, v: string) {.raises: [StoreError].} =
  ## Text, or NULL if it is empty.
  if v.len > 0: s.bindText(i, v) else: s.bindNull(i)

proc run*(s: Stmt) {.raises: [StoreError].} =
  ## Run the statement (an insert, update or delete) with the values bound so
  ## far, then get it ready for the next set.
  let rc = step(s.raw)
  let bad = rc != SQLITE_DONE
  let message = if bad: $errmsg(s.db) else: ""
  discard reset(s.raw)
  discard clear_bindings(s.raw)
  if bad: raiseStore(message)

proc lastInsertId*(db: DbConn): int64 {.raises: [].} =
  ## The id of the row most recently inserted on this connection.
  last_insert_rowid(db)

proc execScript*(db: DbConn, script: string) {.raises: [StoreError].} =
  ## Run a script of several statements.  (If one fails the ones before it
  ## have been done: run it inside a transaction.)
  var err: cstring
  if exec(db, cstring(script), nil, nil, err) != SQLITE_OK:
    let message = if err.isNil: $errmsg(db) else: $err
    if not err.isNil: free(err)
    raiseStore(message)
