## Functions of our own in SQL, registered in every connection (store.nim does it on opening).  All are deterministic, so
## SQLite may use them in an index or evaluate them once, and each gives null for a null argument.
##
## * `fold(text)` is `foldText` (fold.nim): lower case without accents.
## * The grid of cells (geo/cells.nim), so that SQL and Nim cannot compute a cell differently: `cell(lon, lat)`, null for a
##   position that is not on the Earth; `cell_coarse(cell, bits)`, the cell `2^bits` finer ones across that holds it (0 to
##   16); `cell_lon(cell, bits)` and `cell_lat(cell, bits)`, the middle of a cell of that level in degrees; and
##   `cell_dx(cell, bits, radius_m)` and `cell_dy(cell, bits, radius_m)`, how many cells of the level to step east-west and
##   north-south to cover that many metres (`reach`); and `cell_shift(cell, dx, dy)`, the cell that many steps east and north
##   (null if that is off the grid), so that SQL does not need to know how a cell is made of its two numbers.  A level outside 0 to 16, or a negative radius, is an error of the
##   statement, not a null.

import std/options
import db_connector/db_sqlite
import db_connector/sqlite3 as lowlevel
import ../../core/errors
import ../geo/cells
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

template anyNull(args: PValueArg, n: int): bool =
  var found = false
  for i in 0 ..< n:
    if value_type(args[i]) == SQLITE_NULL:
      found = true
  found

proc sayError(ctx: Pcontext, message: string) =
  result_error(ctx, message.cstring, int32(message.len))

proc asCell(args: PValueArg, i: int): Cell =
  Cell(value_int64(args[i]))

proc levelArg(ctx: Pcontext, args: PValueArg, i: int, bits: var int): bool =
  ## The level argument, or an error of the statement (false).
  let v = value_int64(args[i])
  if v < 0 or v > maxBits:
    sayError(ctx, "the level of a cell is 0 to " & $maxBits)
    return false
  bits = int(v)
  true

proc cellFunction(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.} =
  if anyNull(args, 2):
    result_null(ctx)
    return
  let c = cellOf(value_double(args[0]), value_double(args[1]))
  if c.isSome:
    result_int64(ctx, int64(c.get))
  else:
    result_null(ctx)

proc cellCoarseFunction(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.} =
  if anyNull(args, 2):
    result_null(ctx)
    return
  var bits = 0
  if levelArg(ctx, args, 1, bits):
    result_int64(ctx, int64(coarsen(asCell(args, 0), bits)))

proc cellLonFunction(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.} =
  if anyNull(args, 2):
    result_null(ctx)
    return
  var bits = 0
  if levelArg(ctx, args, 1, bits):
    result_double(ctx, centre(asCell(args, 0), bits).lon)

proc cellLatFunction(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.} =
  if anyNull(args, 2):
    result_null(ctx)
    return
  var bits = 0
  if levelArg(ctx, args, 1, bits):
    result_double(ctx, centre(asCell(args, 0), bits).lat)

proc reachOf(ctx: Pcontext, args: PValueArg, east: bool) =
  if anyNull(args, 3):
    result_null(ctx)
    return
  var bits = 0
  if not levelArg(ctx, args, 1, bits):
    return
  let radius = value_double(args[2])
  if not (radius >= 0.0):
    sayError(ctx, "a radius is not negative")
    return
  let steps = reach(asCell(args, 0), bits, radius)
  result_int64(ctx, int64(if east: steps.dx else: steps.dy))

proc cellShiftFunction(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.} =
  if anyNull(args, 3):
    result_null(ctx)
    return
  let c = shifted(asCell(args, 0), int(value_int64(args[1])), int(value_int64(args[2])))
  if c.isSome:
    result_int64(ctx, int64(c.get))
  else:
    result_null(ctx)

proc cellDxFunction(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.} =
  reachOf(ctx, args, true)

proc cellDyFunction(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.} =
  reachOf(ctx, args, false)

proc registerFunctions*(db: DbConn) {.raises: [StoreError].} =
  ## Make our functions known to the connection.
  type Fn = proc(ctx: Pcontext, n: int32, args: PValueArg) {.cdecl.}
  for (name, arity, fn) in [
    ("fold", 1'i32, Fn(foldFunction)),
    ("cell", 2'i32, Fn(cellFunction)),
    ("cell_coarse", 2'i32, Fn(cellCoarseFunction)),
    ("cell_lon", 2'i32, Fn(cellLonFunction)),
    ("cell_lat", 2'i32, Fn(cellLatFunction)),
    ("cell_shift", 3'i32, Fn(cellShiftFunction)),
    ("cell_dx", 3'i32, Fn(cellDxFunction)),
    ("cell_dy", 3'i32, Fn(cellDyFunction)),
  ]:
    if create_function(
      db, name.cstring, arity, SQLITE_UTF8 or SQLITE_DETERMINISTIC, nil, fn, nil, nil
    ) != SQLITE_OK:
      raiseStore("cannot register the SQL function " & name)
