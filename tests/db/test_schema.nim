## Checks of the whole schema that no single table's tests would think of.

import std/[algorithm, os, sequtils, strutils, tables, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/modules


let dir = getTempDir() / "nch-test-schema"

proc leading(db: DbConn, table: string): seq[seq[string]] =
  ## The column lists that `table` can be searched by: each index, and the
  ## primary key (the rowid alias, or the key of a table without rowid).
  for idx in db.getAllRows(sql("pragma index_list(" & table & ")")):
    var cols: seq[(int, string)]
    for c in db.getAllRows(sql("pragma index_info(" & idx[1] & ")")):
      cols.add (parseInt(c[0]), c[2])
    result.add cols.sorted.mapIt(it[1])
  var pk: seq[(int, string)]
  for c in db.getAllRows(sql("pragma table_info(" & table & ")")):
    if c[5] != "0":
      pk.add (parseInt(c[5]), c[1])
  result.add pk.sorted.mapIt(it[1])

suite "schema":
  test "every foreign key is covered by an index (SQLite does not make one)":
    createDir(dir)
    let path = dir / "fk.db"
    removeFile(path)
    let s = openStore(path, allFragments)
    var missing: seq[string]
    for t in s.db.getAllRows(
      sql"select name from sqlite_master where type = 'table' order by name"
    ):
      let table = t[0]
      var keys: Table[string, seq[(int, string)]] # foreign key id -> (seq, child column)
      for fk in s.db.getAllRows(sql("pragma foreign_key_list(" & table & ")")):
        keys.mgetOrPut(fk[0], @[]).add (parseInt(fk[1]), fk[3])
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
