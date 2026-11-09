## Functions of our own in SQL, registered in every connection (store.nim does it on opening).  `fold(text)` is
## `foldText` (fold.nim): lower case without accents, null for null.  It is deterministic, so SQLite may use it in an
## index or evaluate it once.

import db_connector/db_sqlite
import db_connector/sqlite3 as lowlevel
import ../../core/errors
import ../text/fold/fold

{.push raises: [].}

proc foldFunction(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.} =
  if value_type(args[0]) == SQLITE_NULL:
    result_null(ctx)
    return
  let folded = foldText($value_text(args[0]))
  result_text(
    ctx, folded.cstring, int32(folded.len), cast[Result_func](SQLITE_TRANSIENT)
  )

proc registerFunctions*(db: DbConn) {.raises: [StoreError].} =
  ## Make `fold()` known to the connection.
  if create_function(
    db, "fold", 1, SQLITE_UTF8 or SQLITE_DETERMINISTIC, nil, foldFunction, nil, nil
  ) != SQLITE_OK:
    raiseStore("cannot register the SQL function fold")
