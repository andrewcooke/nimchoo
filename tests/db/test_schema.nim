## Checks of the whole schema that no single table's tests would think of.

import std/[algorithm, options, os, sequtils, strutils, tables, unittest]
import db_connector/db_sqlite
import nimchoo/packages/db/statement
import nimchoo/packages/db/store
from nimchoo/registry import allFragments, allAccess, newAllAccess

let dir = getTempDir() / "nch-test-schema"

proc leading(db: DbConn, table: string): seq[seq[string]] =
  ## The column lists that `table` can be searched by: each index, and the
  ## primary key (the rowid alias, or the key of a table without rowid).
  for idx in db.query(
    tuple[seq: int, name: string, unique: int, origin: string, partial: int],
    "select * from pragma_index_list(:table)",
    table = table,
  ):
    var cols: seq[(int, string)]
    for c in db.query(
      tuple[seqno, cid: int, name: Option[string]],
      "select * from pragma_index_info(:index)",
      index = idx.name,
    ):
      cols.add (c.seqno, c.name.get(""))
    result.add cols.sorted.mapIt(it[1])
  var pk: seq[(int, string)]
  for c in db.query(
    tuple[cid: int, name, ctype: string, notNull: int, default: Option[string], pk: int],
    "select * from pragma_table_info(:table)",
    table = table,
  ):
    if c.pk != 0:
      pk.add (c.pk, c.name)
  result.add pk.sorted.mapIt(it[1])

suite "schema":
  test "every foreign key is covered by an index (SQLite does not make one)":
    createDir(dir)
    let path = dir / "fk.db"
    removeFile(path)
    let s = openStore(path, allFragments, access = allAccess)
    var missing: seq[string]
    for table in s.db.query(
      string, "select name from sqlite_master where type = 'table' order by name"
    ):
      var keys: Table[int, seq[(int, string)]] # foreign key id -> (seq, child column)
      for fk in s.db.query(
        tuple[
          id, seq: int,
          table: string,
          fromColumn: string,
          toColumn: Option[string],
          onUpdate, onDelete, match: string,
        ],
        "select * from pragma_foreign_key_list(:table)",
        table = table,
      ):
        keys.mgetOrPut(fk.id, @[]).add (fk.seq, fk.fromColumn)
      let indexes = leading(s.db, table)
      for id, cols in keys:
        let wanted = cols.sorted.mapIt(it[1])
        # covered when the key's columns are the first columns of some index
        # (in any order: the planner can use them in any order)
        if not indexes.anyIt(
          it.len >= wanted.len and it[0 ..< wanted.len].sorted == wanted.sorted
        ):
          missing.add table & "(" & wanted.join(", ") & ")"
    s.close()
    check missing == newSeq[string]()
