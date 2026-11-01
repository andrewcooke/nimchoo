## The database: where it lives, opening it (creating it and bringing its
## schema up to date on first use), and the user whose data we work with.
## Every command that uses the database starts with `openStore`.
##
## The schema is made of fragments (fragment.nim): the database's own, then
## those of the modules, in the order given.  The database remembers which it
## has had in the table `fragment`, so opening applies only the missing ones.
##
## Errors from the database library (`DbError`) are turned into `StoreError`
## here, so nothing above this module sees them.

import std/[os, sequtils, strutils, times]
import db_connector/db_sqlite
import ../errors
import ./fragment
import ./statement
export db_sqlite.DbConn, fragment

{.push raises: [].}

const
  defaultUser* = "default"
  baseFragments = @[fragment("001-user.sql")]

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

proc recorded(db: DbConn): seq[string] {.raises: [StoreError].} =
  ## The fragments the database says it has had.
  guard:
    for row in db.fastRows(sql"select name from fragment order by name"):
      result.add row[0]

proc record(db: DbConn, name: string) {.raises: [StoreError].} =
  guard:
    db.exec(sql"insert into fragment(name, applied_at) values (?, ?)",
            name, getTime().toUnix)

proc apply(db: DbConn, f: Fragment) {.raises: [StoreError].} =
  ## Run a fragment and record it, as one transaction.
  guard: db.exec(sql"begin")
  var done = false
  try:
    execScript(db, f.sql)
    record(db, f.name)
    guard: db.exec(sql"commit")
    done = true
  except StoreError as e:
    raiseStore("applying " & f.name & ": " & e.msg)
  finally:
    if not done:
      try: discard db.tryExec(sql"rollback")
      except DbError: discard

proc bringUpToDate(db: DbConn, fragments: seq[Fragment])
    {.raises: [StoreError].} =
  let all = baseFragments & fragments
  guard:
    db.exec(sql"""create table if not exists fragment (
                    name text primary key,
                    applied_at integer not null) without rowid""")
  let have = recorded(db)
  for name in have:
    if all.allIt(it.name != name):
      raiseStore("the database is from a newer version of nch (it has '" &
                 name & "')")
  for f in all:
    if f.name notin have: apply(db, f)

proc close*(s: Store) {.raises: [].} =
  try: db_sqlite.close(s.db)
  except DbError: discard  # nothing useful can be done

proc openStore*(path: string, fragments: seq[Fragment],
                user = defaultUser): Store {.raises: [StoreError].} =
  ## Open the database at `path`, creating the file and applying the fragments
  ## it lacks, and find `user` (the default user is created if missing).
  ## Raises StoreError if that cannot be done or the user does not exist.
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
    bringUpToDate(result.db, fragments)
    guard:
      result.db.exec(sql"insert or ignore into user(name) values (?)",
                     defaultUser)
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
