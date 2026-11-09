## The access rules (core/access.nim) put to work: SQLite's authorizer is asked about every table a statement
## touches while the statement is prepared.  The statement helpers (`statement.nim`) say which package the
## statement was written in, by the file it is written in (worked out when the program is compiled, so it costs
## nothing when it runs); here it is kept for the length of the `prepare` and the authorizer reads it.
##
## The one piece of mutable state this needs is a thread variable for the caller: the authorizer gets nothing but
## the connection's pointer from SQLite, and the statement helpers get nothing but the connection.  It is set
## around a `prepare` and cleared after, so it never outlives one call.

import std/[os, options]
import db_connector/db_sqlite
from db_connector/sqlite3 import set_authorizer, SQLITE_OK, SQLITE_READ, SQLITE_INSERT
import ../../core/access

{.push raises: [].}

const
  sqliteDeny = 1'i32
  sqliteOk = 0'i32
  # (the codes of sqlite3.h, for the ones that make or change a table)
  actCreateIndex = 1'i32
  actCreateTable = 2'i32
  actCreateTrigger = 7'i32
  actDelete = 9'i32
  actDropIndex = 10'i32
  actDropTable = 11'i32
  actDropTrigger = 16'i32
  actUpdate = 23'i32
  actAlterTable = 26'i32
  actCreateVtable = 29'i32
  actDropVtable = 30'i32

var
  caller {.threadvar.}: string
    ## the package whose statement is being prepared; "": not checked
  denial {.threadvar.}: string ## why the authorizer refused the last one
  written {.threadvar.}: seq[string]
    ## the tables the statement being prepared writes directly

proc packageOfFile*(file: string): string {.compileTime.} =
  ## The package a source file belongs to: its name is the name of the nearest directory above the file that has
  ## a `package.nim` (PACKAGES.md); "" for a file outside the packages (`core`, the tests).
  var dir = file.parentDir
  while dir.len > 1:
    if fileExists(dir / "package.nim"):
      return dir.lastPathPart
    dir = dir.parentDir

proc authorize(
    user: pointer, action: int32, arg1, arg2, database, trigger: cstring
): int32 {.cdecl, raises: [].} =
  let rules {.cursor.} = cast[Access](user)
  if caller.len == 0 or not trigger.isNil:
    # (what a trigger does is the database's own business)
    return sqliteOk
  if not database.isNil and $database == "temp":
    return sqliteOk
  var table: cstring
  var what: Action
  case action
  of SQLITE_READ:
    table = arg1
    what = acRead
  of SQLITE_INSERT, actUpdate, actDelete:
    table = arg1
    what = acWrite
    if not table.isNil:
      written.add $table
  of actCreateTable, actDropTable, actCreateVtable, actDropVtable:
    table = arg1
    what = acDefine
  of actAlterTable, actCreateIndex, actDropIndex:
    table = arg2
    what = acDefine
  of actCreateTrigger, actDropTrigger:
    # (a trigger belongs to the package that made it and may be on any table that package may read)
    table = arg2
    what = acRead
  else:
    return sqliteOk
  if table.isNil:
    return sqliteOk
  let why = rules.refusal(caller, what, $table, written)
  if why.isNone:
    return sqliteOk
  case rules.mode
  of amOff:
    sqliteOk
  of amEnforce:
    denial = why.get
    sqliteDeny

proc installAccess*(db: DbConn, rules: Access) {.raises: [].} =
  ## Have SQLite ask `rules` about every statement of this connection.  The connection's owner keeps `rules`
  ## alive for as long as the connection is open.
  if rules != nil and rules.mode != amOff:
    discard set_authorizer(db, authorize, cast[pointer](rules))

proc enter*(package: string) {.raises: [].} =
  ## A statement of `package` is about to be prepared.
  caller = package
  denial = ""
  written.setLen 0

proc leave*(): string {.raises: [].} =
  ## The statement is prepared; why the authorizer refused it, "" if it did not.
  caller = ""
  denial
