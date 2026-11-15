## What changed in the database, as keys: the identity of the database, and a counter for each table.
##
## A view (`map`, `calendar`) is made from the rows of some tables, and may be kept while they are as they were.  Each table that a
## package owns has a counter in `table_version`, increased by three triggers (after an insert, an update and a delete: one
## per row, which is the only grain SQLite has), so a key made from the counters of the tables a view reads changes when
## any of them is written.  The triggers are made here, for every table in the list of owned tables (`core/ownership`), so
## that a new table has them without anyone writing them; the tables of `db` itself (the counters, the identity) have none.
##
## `database_identity` is a random name made when the database is created (`seedIdentity`), so that no two databases give
## the same key.

import std/[algorithm, sequtils, strformat, tables]
import ../../core/[errors, fragment, ownership]
import ./statement

{.push raises: [].}

const triggerPrefix = "tv_" ## the names of the triggers that keep the counters

proc seedIdentity*(db: DbConn) {.raises: [StoreError].} =
  ## The one row of `database_identity`: 128 random bits, as hex.
  db.execute(
    "insert into database_identity(one, id) values (1, lower(hex(randomblob(16))))"
  )

proc databaseIdentity*(db: DbConn): string {.raises: [StoreError].} =
  ## The name of this database (made when it was created).
  db.scalar(string, "select id from database_identity")

proc countedTables*(
    db: DbConn, fragments: seq[Fragment]
): seq[string] {.raises: [StoreError].} =
  ## The tables that have a counter: every table a package other than `db` makes and the database has (one a later fragment
  ## dropped is not there), sorted.
  let existing = db.query(string, "select name from sqlite_master where type = 'table'")
  var owners: Table[string, string]
  try:
    owners = tableOwners(fragments)
  except PackageError as e:
    raiseStore(e.msg)
  for table, owner in owners:
    if owner != "db" and table in existing:
      result.add table
  result.sort

proc triggerSql(table, event, what: string): string =
  fmt"""create trigger if not exists "{triggerPrefix}{table}_{event}" after {what} on "{table}" begin update table_version set version = version + 1 where name = '{table}'; end;"""

proc ensureCounters*(db: DbConn, fragments: seq[Fragment]) {.raises: [StoreError].} =
  ## Make the counters and their triggers for every table the fragments make, if the database lacks any (so a new table gets
  ## its own the first time the program opens a database that has it).  Costs one query when nothing is missing.
  let tables = countedTables(db, fragments)
  let have = db.scalar(
    int,
    "select count(*) from sqlite_master where type = 'trigger' and name like 'tv\\_%' escape '\\'",
  )
  if have == tables.len * 3:
    return
  db.execScript("begin")
  var done = false
  try:
    for t in tables:
      db.execScript(
        fmt"insert or ignore into table_version(name, version) values ('{t}', 0)"
      )
      # (not checked: `db` makes triggers on every package's tables, which it may not read)
      db.execScriptAs(triggerSql(t, "i", "insert"), "")
      db.execScriptAs(triggerSql(t, "u", "update"), "")
      db.execScriptAs(triggerSql(t, "d", "delete"), "")
    db.execScript("commit")
    done = true
  finally:
    if not done:
      try:
        db.execScript("rollback")
      except StoreError:
        discard # (nothing useful can be done)

proc tableVersions*(
    db: DbConn, tables: seq[string]
): seq[(string, int64)] {.raises: [StoreError].} =
  ## The counters of these tables, sorted by name, each once.  A table with no counter is a bug (a table that is not
  ## owned by a package, or a misspelt name).
  for name in tables.sorted.deduplicate(isSorted = true):
    let rows = db.query(
      int64, "select version from table_version where name = :name", name = name
    )
    doAssert rows.len == 1, "table '" & name & "' has no counter (a table of a package)"
    result.add (name, rows[0])
