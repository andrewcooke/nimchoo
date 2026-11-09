## A query that is built from pieces: its text, with `:name` marks where the values go, and the values by name.
## The values are never put into the text (`statement.nim` binds them), and the pieces can be joined in any order
## with `&`: each carries its own values, so nothing can fall out of step as with `?`.  A name may stand more than
## once in the text; it is one value.  (A name with no value, a value no name uses, or one name given twice is a
## `StoreError` when the query is run.)
##
## Short queries with fixed text use `?` and `query(db, T, text, values...)` instead (`statement.nim`).

import std/options
import ../ids

{.push raises: [].}

type
  ArgKind* = enum
    akNull
    akInt
    akReal
    akText

  Arg* = object ## One value to bind, of the type the column has.
    case kind*: ArgKind
    of akNull:
      discard
    of akInt:
      i*: int64
    of akReal:
      r*: float
    of akText:
      s*: string

  Sql* = object
    text*: string
    args*: seq[tuple[name: string, value: Arg]]

func arg*(v: int): Arg =
  Arg(kind: akInt, i: int64(v))

func arg*(v: int64): Arg =
  Arg(kind: akInt, i: v)

func arg*(v: AnyId): Arg =
  Arg(kind: akInt, i: int64(v))

func arg*(v: bool): Arg =
  Arg(kind: akInt, i: int64(ord(v)))

func arg*(v: float): Arg =
  Arg(kind: akReal, r: v)

func arg*(v: string): Arg =
  ## (An empty string is empty text, not NULL: NULL is an absent `Option`.)
  Arg(kind: akText, s: v)

func arg*[T](v: Option[T]): Arg =
  if v.isSome:
    arg(v.get)
  else:
    Arg(kind: akNull)

func `==`*(a, b: Arg): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of akNull:
    true
  of akInt:
    a.i == b.i
  of akReal:
    a.r == b.r
  of akText:
    a.s == b.s

func sqlOf*(text: string): Sql =
  ## A piece of query with no values yet.
  Sql(text: text)

func with*[T](q: Sql, name: string, v: T): Sql =
  ## The query with the value for `:name`.
  result = q
  result.args.add (name, arg(v))

func `&`*(a, b: Sql): Sql =
  result = Sql(text: a.text & b.text, args: a.args)
  result.args.add b.args

func `&`*(a: Sql, b: string): Sql =
  Sql(text: a.text & b, args: a.args)

func `&`*(a: string, b: Sql): Sql =
  Sql(text: a & b.text, args: b.args)

const cornerMarks* = ":west, :south, :east, :north"
  ## the corners of a box as names, for `inBox`; give `west = ..., south = ..., east = ..., north = ...`

func inBox*(idColumn, table, geomColumn, corners: string): string =
  ## "a.id in (select ROWID from SpatialIndex ...)": the rows of `table` whose `geomColumn` box meets the box with
  ## these four corners (west, south, east, north: `cornerMarks`, or four other `:names`).  The one way a spatial index is
  ## asked, so that it is always the index and never a scan (tests/db/test_plans.nim looks).
  idColumn & " in (select ROWID from SpatialIndex where f_table_name = '" & table &
    "' and f_geometry_column = '" & geomColumn & "' and search_frame = BuildMbr(" &
    corners & "))"

func jsonList*(ids: openArray[int64]): string =
  ## The numbers as a JSON array, for a list of any length to be bound as ONE value:
  ## `... in (select value from json_each(?))`.  (The sql text stays the same, whatever the list.)
  result = "["
  for i, id in ids:
    if i > 0:
      result.add ','
    result.add $id
  result.add ']'
