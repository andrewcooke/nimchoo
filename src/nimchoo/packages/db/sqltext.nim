## A query that is built from pieces: its text, with `:name` marks where the values go, and the values by name.
## The values are never put into the text (`statement.nim` binds them), and the pieces can be joined in any order
## with `&`: each carries its own values, so nothing can fall out of step.  A name may stand more than
## once in the text; it is one value.  (A name with no value, a value no name uses, or one name given twice is a
## `StoreError` when the query is run.)
##
## Each piece also records the package whose file wrote it (`sqlOf`, and `&` with a plain string, take it from the file
## they are written in, worked out when the program is compiled).  The access rules use it: a statement is run by one
## package, but when another package contributed a piece (a criterion that `climbs` offers `activities`) a read of
## that package's tables is allowed too; a write is the runner's alone (`core/access.nim`, `refusal`).
##
## Short queries with fixed text need no `Sql`: `query(db, T, "... where id = :id", id = 3)` takes the same `:names` and the
## values by name (`statement.nim`); a `?` in the text is an error.

import std/options
import ../../core/ids
import ./access

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
    packages*: seq[string]
      ## the packages whose files wrote pieces of the text (none for a file outside the packages)

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

func joined(a, b: seq[string]): seq[string] =
  ## The union of two lists of packages, in order.
  result = a
  for p in b:
    if p notin result:
      result.add p

func sqlFrom*(text, package: string): Sql =
  ## A piece of query written in `package` ("": a file outside the packages).  `sqlOf` is this with the package of the
  ## file it is written in; call this to say the package yourself (a test of the access rules).
  result = Sql(text: text)
  if package.len > 0:
    result.packages.add package

template sqlOf*(text: string): Sql =
  ## A piece of query with no values yet, written in the package of this file.
  sqlFrom(
    text,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

func with*[T](q: Sql, name: string, v: T): Sql =
  ## The query with the value for `:name`.
  result = q
  result.args.add (name, arg(v))

func `&`*(a, b: Sql): Sql =
  ## The pieces joined; the packages of both.
  result =
    Sql(text: a.text & b.text, args: a.args, packages: joined(a.packages, b.packages))
  result.args.add b.args

func appended(a: Sql, b, package: string): Sql =
  result = Sql(text: a.text & b, args: a.args, packages: a.packages)
  if package.len > 0:
    result.packages = joined(a.packages, @[package])

func prepended(a: string, b: Sql, package: string): Sql =
  result = Sql(text: a & b.text, args: b.args, packages: b.packages)
  if package.len > 0:
    result.packages = joined(@[package], b.packages)

template `&`*(a: Sql, b: string): Sql =
  ## The text added to the piece (it is written in this file's package).
  appended(
    a,
    b,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

template `&`*(a: string, b: Sql): Sql =
  prepended(
    a,
    b,
    (
      block:
        const package = packageOfFile(instantiationInfo(-1, true).filename)
        package
    ),
  )

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
