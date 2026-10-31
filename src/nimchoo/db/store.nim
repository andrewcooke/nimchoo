## The database: where it lives, opening it (creating it and bringing its
## schema up to date on first use), and the user whose data we work with.
## Every command that uses the database starts with `openStore`.
##
## Errors from the database library (`DbError`) are turned into `StoreError`
## here, so nothing above this module sees them.

import std/[os, strutils]
import db_connector/db_sqlite
import ../errors
import ./migrations
export db_sqlite.DbConn, migrations.defaultUser

{.push raises: [].}

type
  Store* = object
    db*: DbConn
    userId*: int64
    userName*: string

template guard*(body: untyped) =
  ## Run database code, turning a DbError into a StoreError.
  try:
    body
  except DbError as e:
    raiseStore(e.msg)

proc resolveDbPath*(option: string): string =
  ## The database file: the `--db` option, else `$NCH_DB`, else
  ## `nch/nch.db` in the user's data directory.
  if option.len > 0: return option
  let env = getEnv("NCH_DB")
  if env.len > 0: return env
  string(getDataDir()) / "nch" / "nch.db"

proc schemaVersion(db: DbConn): int {.raises: [StoreError].} =
  guard:
    try:
      result = parseInt(db.getValue(sql"pragma user_version"))
    except ValueError:
      raiseStore("cannot read the schema version")

proc migrate(db: DbConn) {.raises: [StoreError].} =
  ## Apply the migrations the database has not had yet, each in a transaction.
  let have = schemaVersion(db)
  if have > allMigrations.len:
    raiseStore("the database is from a newer version of nch (schema " & $have &
               ", this program knows " & $allMigrations.len & ")")
  for i in have ..< allMigrations.len:
    guard:
      db.exec(sql"begin")
      try:
        for statement in allMigrations[i]:
          db.exec(sql(statement))
        db.exec(sql("pragma user_version = " & $(i + 1)))
        db.exec(sql"commit")
      except DbError:
        discard db.tryExec(sql"rollback")
        raise

proc close*(s: Store) {.raises: [].} =
  try: db_sqlite.close(s.db)
  except DbError: discard  # nothing useful can be done

proc openStore*(path: string, user = defaultUser): Store
    {.raises: [StoreError].} =
  ## Open the database at `path`, creating the file and applying migrations as
  ## needed, and find `user`.  Raises StoreError if that cannot be done or the
  ## user does not exist.
  if path != ":memory:":
    try:
      createDir(parentDir(path))
    except OSError, IOError:
      raiseStore("cannot create the directory for " & path & ": " &
                 getCurrentExceptionMsg())
  guard:
    result.db = open(path, "", "", "")
  try:
    guard:
      result.db.exec(sql"pragma foreign_keys = on")
    migrate(result.db)
    guard:
      let id = result.db.getValue(sql"select id from user where name = ?", user)
      if id.len == 0:
        raiseStore("no such user: " & user)
      try:
        result.userId = parseBiggestInt(id)
      except ValueError:
        raiseStore("bad user id " & id)
      result.userName = user
  except StoreError:
    close(result)
    raise

proc begin*(s: Store) {.raises: [StoreError].} =
  guard: s.db.exec(sql"begin")

proc commit*(s: Store) {.raises: [StoreError].} =
  guard: s.db.exec(sql"commit")

proc rollback*(s: Store) {.raises: [].} =
  ## Undo the open transaction; a failure here has nowhere useful to go.
  try: discard s.db.tryExec(sql"rollback")
  except DbError: discard
