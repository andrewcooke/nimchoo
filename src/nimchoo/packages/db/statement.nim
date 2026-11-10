## Prepared statements that can be run many times (the importer inserts
## thousands of coordinates).  A thin typed layer over SQLite's C interface,
## because `db_sqlite`'s prepared statements are single-use.  Errors become
## `StoreError`.
##
## On top of that, the typed way to use it (`query`, `queryOne`, `scalar`, `execute`): the values are given by name
## (`:id` in the sql, `id = 3` in the call), bound by their Nim type and never put into the text; a `?` in the text is
## an error.  A row is read into a tuple or an object whose field types say what each column must be.  A column of
## another type than the field's, a NULL for a field that is not an `Option`, or a row of another width than the tuple,
## is a `StoreError` that names the column.  (The prepared statements that are run many times, `prepareStmt`, bind by
## position: they are for loops over thousands of rows.)

import std/[macros, options, strformat]
from std/strutils import IdentChars, IdentStartChars
import db_connector/db_sqlite
from db_connector/sqlite3 import
  PStmt, bind_parameter_count, bind_parameter_name, column_count, column_double,
  column_int64, column_name, column_type, SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT,
  SQLITE_NULL, SQLITE_BLOB, prepare_v2, bind_int64, bind_double, bind_null, bind_text,
  bind_blob, SQLITE_TRANSIENT, step, reset, clear_bindings, finalize, errmsg,
  last_insert_rowid, exec, free, SQLITE_OK, SQLITE_DONE, SQLITE_ROW, column_blob,
  column_bytes
import ../../core/errors
import ../../core/ids
import ./[access, sqltext]
export sqltext, access.packageOfFile, db_sqlite.DbConn

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
  raiseStore(fmt"{what}: {errmsg(db)}")

proc openFile*(path: string): DbConn {.raises: [StoreError].} =
  ## A plain connection to a database file: no fragments, no extensions, no user (`openStore` does those).  For
  ## what must work whatever layout the file has.  Close it with `closeQuietly`.
  try:
    db_sqlite.open(path, "", "", "")
  except DbError as e:
    raiseStore(fmt"cannot open {path}: {e.msg}")

proc closeQuietly*(db: DbConn) {.raises: [].} =
  ## Close a connection, ignoring a failure (it is for cleaning up).
  try:
    db_sqlite.close(db)
  except DbError:
    discard

proc prepareStmtAs*(
    db: DbConn, sql: string, package: string
): Stmt {.raises: [StoreError].} =
  ## Compile one statement written in `package` ("": not checked); `?` marks the values to bind (numbered
  ## from 1).  The access rules (`access.nim`) are asked while it is compiled.
  var raw: PStmt
  enter(package)
  let rc = prepare_v2(db, cstring(sql), cint(sql.len), raw, nil)
  let refused = leave()
  if rc != SQLITE_OK:
    if refused.len > 0:
      raiseStore(fmt"{refused}: {sql}")
    fail(db, fmt"cannot prepare '{sql}'")
  Stmt(raw: raw, db: db)

template prepareStmt*(db: DbConn, sql: string): untyped =
  ## Compile one statement; `?` marks the values to bind (numbered from 1).  It is checked as the package
  ## of the file it is written in.
  prepareStmtAs(
    db,
    sql,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

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

proc execScriptAs*(
    db: DbConn, script: string, package: string
) {.raises: [StoreError].} =
  ## Run a script of several statements written in `package`.  (If one fails the ones before it
  ## have been done: run it inside a transaction.)
  var err: cstring
  enter(package)
  let rc = exec(db, cstring(script), nil, nil, err)
  let refused = leave()
  if rc != SQLITE_OK:
    let message =
      if refused.len > 0:
        refused
      elif err.isNil:
        $errmsg(db)
      else:
        $err
    if not err.isNil:
      free(err)
    raiseStore(message)

template execScript*(db: DbConn, script: string) =
  ## Run a script of several statements.  (If one fails the ones before it
  ## have been done: run it inside a transaction.)  It is checked as the package of the file it is written in.
  execScriptAs(
    db,
    script,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

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
    fmt"column {i} ({column_name(s.raw, int32(i))}) is {typeName(column_type(s.raw, int32(i)))}, not {want}"
  )

proc readCol*(s: Stmt, i: int, v: var int64) {.raises: [StoreError].} =
  if column_type(s.raw, int32(i)) != SQLITE_INTEGER:
    wrong(s, i, "an integer")
  v = column_int64(s.raw, int32(i))

proc readCol*(s: Stmt, i: int, v: var int) {.raises: [StoreError].} =
  var w: int64
  s.readCol(i, w)
  v = int(w)

proc readCol*(s: Stmt, i: int, v: var bool) {.raises: [StoreError].} =
  ## (0 or 1: what SQLite makes of a comparison.)
  var w: int64
  s.readCol(i, w)
  if w != 0 and w != 1:
    wrong(s, i, "0 or 1")
  v = w == 1

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
  when (T is tuple or T is object) and T isnot Option:
    var want = 0
    for _ in fields(result):
      inc want
    let have = int(column_count(s.raw))
    if have != want:
      raiseStore(fmt"the query has {have} columns, not {want}")
    var n = 0
    for f in fields(result):
      s.readCol(n, f)
      inc n
  else:
    let have = int(column_count(s.raw))
    if have != 1:
      raiseStore(fmt"the query has {have} columns, not 1")
    s.readCol(0, result)

proc fetchAll*[T](s: Stmt): seq[T] {.raises: [StoreError].} =
  while s.nextRow():
    result.add readRow[T](s)

proc fetchOne*[T](s: Stmt): Option[T] {.raises: [StoreError].} =
  if s.nextRow():
    result = some(readRow[T](s))

proc theRow[T](got: Option[T], sqlText: string): T {.raises: [StoreError].} =
  if got.isNone:
    raiseStore(fmt"the query gave no row: {sqlText}")
  got.get

# --- a query built from pieces (`sql.nim`) ------------------------------------------------------------------

proc bindArg(s: Stmt, i: int, a: Arg) {.raises: [StoreError].} =
  case a.kind
  of akNull:
    s.bindNull(i)
  of akInt:
    s.bindInt(i, a.i)
  of akReal:
    s.bindReal(i, a.r)
  of akText:
    s.bindText(i, a.s)

proc prepareSql*(db: DbConn, q: Sql, package: string): Stmt {.raises: [StoreError].} =
  ## Compile the query and bind its values by name.  A mark with no value, a value no mark uses, and a name given
  ## twice are errors (a mistake in building the query, told before it runs).
  result = prepareStmtAs(db, q.text, package)
  var used = newSeq[bool](q.args.len)
  for i in 1 .. int(bind_parameter_count(result.raw)):
    let mark = bind_parameter_name(result.raw, int32(i))
    if mark.isNil:
      raiseStore(fmt"the query has a ? where only :names are allowed: {q.text}")
    let name = ($mark)[1 ..^ 1]
    var found = -1
    for k, a in q.args:
      if a.name == name:
        if found >= 0:
          raiseStore(fmt"the value :{name} is given twice")
        found = k
    if found < 0:
      raiseStore(fmt"the query has :{name} but no value for it: {q.text}")
    used[found] = true
    result.bindArg(i, q.args[found].value)
  for k, a in q.args:
    if not used[k]:
      raiseStore(fmt"the value :{a.name} is not used by the query: {q.text}")

proc runQuery*(
    db: DbConn, T: typedesc, q: Sql, package: string
): seq[T] {.raises: [StoreError].} =
  fetchAll[T](prepareSql(db, q, package))

proc runQueryOne*(
    db: DbConn, T: typedesc, q: Sql, package: string
): Option[T] {.raises: [StoreError].} =
  fetchOne[T](prepareSql(db, q, package))

proc runScalar*(
    db: DbConn, T: typedesc, q: Sql, package: string
): T {.raises: [StoreError].} =
  theRow(fetchOne[T](prepareSql(db, q, package)), q.text)

proc runExecute*(db: DbConn, q: Sql, package: string) {.raises: [StoreError].} =
  prepareSql(db, q, package).run()

template query*(db: DbConn, T: typedesc, q: Sql): untyped =
  ## All the rows of a query built from pieces, as `T`s.
  runQuery(
    db,
    T,
    q,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

template queryOne*(db: DbConn, T: typedesc, q: Sql): untyped =
  runQueryOne(
    db,
    T,
    q,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

template scalar*(db: DbConn, T: typedesc, q: Sql): untyped =
  runScalar(
    db,
    T,
    q,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

template execute*(db: DbConn, q: Sql): untyped =
  runExecute(
    db,
    q,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

# --- the calls: the sql text with :names, and name = value for each --------------------------------------------

proc literalText(n: NimNode): Option[string] {.compileTime.} =
  ## The text of a string literal, or of literals joined with `&`; none if any part is something else.
  case n.kind
  of nnkStrLit, nnkTripleStrLit, nnkRStrLit:
    some(n.strVal)
  of nnkInfix:
    if n[0].eqIdent("&"):
      let a = literalText(n[1])
      let b = literalText(n[2])
      if a.isSome and b.isSome:
        return some(a.get & b.get)
    none(string)
  of nnkPar:
    if n.len == 1:
      literalText(n[0])
    else:
      none(string)
  else:
    none(string)

proc unquoted(text: string): string {.compileTime.} =
  ## The sql without what is between single quotes (a ? there is text).
  var quoted = false
  for c in text:
    if c == '\'':
      quoted = not quoted
    elif not quoted:
      result.add c

proc marksIn(text: string): seq[string] {.compileTime.} =
  ## The `:names` in sql text (not in a quoted string, and not a `::`).
  var i = 0
  var quoted = false
  while i < text.len:
    let c = text[i]
    if c == '\'':
      quoted = not quoted
    elif not quoted and c == ':' and i + 1 < text.len and text[i + 1] in IdentStartChars and
        (i == 0 or text[i - 1] notin IdentChars + {':'}):
      var k = i + 1
      while k < text.len and text[k] in IdentChars:
        inc k
      let name = text[i + 1 ..< k]
      if name notin result:
        result.add name
      i = k - 1
    inc i

proc nodes(args: NimNode): seq[NimNode] {.compileTime.} =
  for a in args:
    result.add a

proc built(call, text: NimNode, args: seq[NimNode]): NimNode {.compileTime.} =
  ## `sqlOf(text).with("a", x).with("b", y)` from `a = x, b = y`; when the text is a literal, the names in it and the
  ## names given must be the same (a compile error otherwise).
  result = newCall(bindSym"sqlOf", text)
  var given: seq[string]
  for a in args:
    if a.kind != nnkExprEqExpr:
      error("give each value as name = value (the sql has :names)", a)
    let name = $a[0]
    if name in given:
      error(fmt"the value {name} is given twice", a)
    given.add name
    result = newCall(bindSym"with", result, newLit(name), a[1])
  let literal = literalText(text)
  if literal.isSome:
    let wanted = marksIn(literal.get)
    for w in wanted:
      if w notin given:
        error(fmt"the sql has :{w} but no value {w} = ... is given", call)
    for g in given:
      if g notin wanted:
        error(fmt"the value {g} is given but the sql has no :{g}", call)
    if '?' in unquoted(literal.get):
      error("use :names in the sql, not ?", call)

proc packageLit(at: NimNode): NimNode {.compileTime.} =
  ## The package of the file the call is written in, as a literal.
  newLit(packageOfFile(at.lineInfoObj.filename))

macro query*(db: DbConn, T: typedesc, text: string, args: varargs[untyped]): untyped =
  ## All the rows of the query as `T`s (a tuple, an object, or one value for a one-column query).  The values are
  ## given by name, `query(db, Row, "select ... where id = :id", id = 3)`; each `:name` of the sql text needs its
  ## `name = value`, checked when the program is compiled if the text is a literal.
  newCall(bindSym"runQuery", db, T, built(db, text, nodes(args)), packageLit(db))

macro queryOne*(
    db: DbConn, T: typedesc, text: string, args: varargs[untyped]
): untyped =
  ## The first row, or `none` if there is none.
  newCall(bindSym"runQueryOne", db, T, built(db, text, nodes(args)), packageLit(db))

macro scalar*(db: DbConn, T: typedesc, text: string, args: varargs[untyped]): untyped =
  ## The one value a query is sure to give (`select count(*) ...`); no row at all is a `StoreError`.
  newCall(bindSym"runScalar", db, T, built(db, text, nodes(args)), packageLit(db))

macro execute*(db: DbConn, text: string, args: varargs[untyped]): untyped =
  ## Run an insert, update or delete.
  newCall(bindSym"runExecute", db, built(db, text, nodes(args)), packageLit(db))
