## What a database holds, table by table (`nch db`): the tables of the packages, each with its owner, how many
## rows, how much of the file it takes (with its indexes and its SpatiaLite spatial index) and the tables its foreign
## keys refer to; and, in sum, the tables of SQLite and SpatiaLite and the record of the fragments.  A table that is
## neither (left from an older program, say) is listed with no owner.
##
## It reads every table, which no package may (the access model, `core/access.nim`), so it is read on a connection of
## its own, made read-only: it is about the database file, as the rest of `nch db` is.

import std/[algorithm, options, sequtils, strutils, tables]
import db_connector/db_sqlite
import ../../core/errors
import ./statement

{.push raises: [].}

type
  TableHolding* = object ## a table of a package, or one no package owns
    name*: string
    owner*: Option[string] ## none: no package owns it
    rows*: int64
    bytes*: int64 ## with its indexes and its spatial index
    refersTo*: seq[string] ## the tables its foreign keys refer to, by name

  Holding* = object
    tables*: seq[TableHolding] ## by name
    others*: int ## the tables of SQLite and SpatiaLite and the record of the fragments
    othersBytes*: int64

const
  systemNames = [
    "fragment", "spatial_ref_sys", "spatial_ref_sys_aux", "spatialite_history",
    "sql_statements_log", "data_licenses", "ElementaryGeometries", "KNN", "KNN2",
    "SpatialIndex",
  ] ## the record of the fragments (`core/fragment.nim`) and what SpatiaLite makes
  systemPrefixes =
    ["sqlite_", "geometry_columns", "views_geometry_columns", "virts_geometry_columns"]

func isSystem(name: string): bool =
  ## A table of SQLite, of SpatiaLite or the record of the fragments.
  name in systemNames or systemPrefixes.anyIt(name.startsWith(it))

func quoted(name: string): string =
  ## A name of a table as SQL writes one (a name cannot be bound as a value is).
  "\"" & name.replace("\"", "\"\"") & "\""

func spatialBase(name: string, owned: seq[string]): Option[string] =
  ## The table a SpatiaLite spatial index (`idx_<table>_<column>` and its `_node`, `_parent`, `_rowid`) belongs to.
  if not name.startsWith("idx_"):
    return
  var best = ""
  for t in owned:
    if name.startsWith("idx_" & t & "_") and t.len > best.len:
      best = t
  if best.len > 0:
    result = some(best)

proc holding*(
    db: DbConn, ownerOf: proc(table: string): Option[string] {.raises: [].}
): Holding {.raises: [StoreError].} =
  ## What `db` holds; `ownerOf` says which package owns a table (none: no package).
  var names: seq[tuple[name: string, isVirtual: bool]]
  for r in db.query(
    tuple[name, sql: string],
    "select name, coalesce(sql, '') from sqlite_schema where type = 'table' order by name",
  ):
    names.add (r.name, r.sql.startsWith("CREATE VIRTUAL"))
  var bytes: Table[string, int64] # by table, with its indexes
  for r in db.query(
    tuple[name: string, bytes: int64],
    """select coalesce(s.tbl_name, d.name), sum(d.pgsize) from dbstat d
      left join sqlite_schema s on s.name = d.name group by 1""",
  ):
    bytes[r.name] = r.bytes
  var owned: seq[string]
  for n in names:
    if not n.name.isSystem and not n.name.startsWith("idx_") and ownerOf(n.name).isSome:
      owned.add n.name
  var byName: Table[string, TableHolding]
  for n in names:
    let size = bytes.getOrDefault(n.name)
    let base = spatialBase(n.name, owned)
    if base.isSome:
      byName.mgetOrPut(base.get, TableHolding(name: base.get)).bytes += size
    elif n.name.isSystem or n.isVirtual or n.name.startsWith("idx_"):
      inc result.others
      result.othersBytes += size
    else:
      var t = byName.mgetOrPut(n.name, TableHolding(name: n.name))
      t.owner = ownerOf(n.name)
      t.rows = db.scalar(int64, sqlOf("select count(*) from " & quoted(n.name)))
      t.bytes += size
      for fk in db.query(
        tuple[id, seq: int, table: string],
        sqlOf("select id, seq, \"table\" from pragma_foreign_key_list(:t)").with(
          "t", n.name
        ),
      ):
        if fk.table notin t.refersTo:
          t.refersTo.add fk.table
      byName[n.name] = t
  for t in byName.values:
    result.tables.add t
  result.tables.sort(
    proc(a, b: TableHolding): int =
      cmp(a.name, b.name)
  )
