## The database: where it lives, opening it (creating it and bringing its
## schema up to date on first use).  Which user's data we work with is not known here: that is the `user`
## package's (`openSession`), which every command that has a user starts with.
##
## The schema is made of fragments (fragment.nim): the database's own, then
## those of the modules, in the order given.  The database remembers which it
## has had in the table `fragment`, so opening applies only the missing ones.
##
## Errors from the database library (`DbError`) are turned into `StoreError`
## here, so nothing above this module sees them.

import std/[options, os, sequtils, strformat, times]
import db_connector/db_sqlite
import db_connector/sqlite3 as lowlevel
import ../../core/errors
import ../../core/ids
export ids
import ../../core/globals
import ../../core/fragment as coreFragment
import ../../core/[access as coreAccess, ownership]
import ./[access, fragment, functions]
import ./statement
export db_sqlite.DbConn, fragment, coreFragment

{.push raises: [].}

const baseFragments* =
  @[fragment("001-schema.sql")] ## the database's own, applied first, always

type
  ConnObj = object
    db: DbConn
    access: Access
      ## kept alive for as long as SQLite may ask it (the authorizer holds a pointer)

  Conn = ref ConnObj
    ## Owns the connection: it is closed when the last `Store` that points here goes, or earlier
    ## by `close`.  (A `Store` may be copied; the copies share one connection.)

proc closeConn(c: Conn) {.raises: [].} =
  if c != nil and c.db != nil:
    try:
      db_sqlite.close(c.db)
    except DbError:
      discard # nothing useful can be done
    c.db = nil

proc `=destroy`(c: ConnObj) {.raises: [].} =
  if c.db != nil:
    try:
      db_sqlite.close(c.db)
    except DbError:
      discard

type Store* = object
  db*: DbConn
  conn: Conn
  path*: string ## the database file (":memory:" for one in memory)

proc resolveDbPath*(option: string): string =
  ## The database file: the `--db` option, else `$NCH_DB`, else
  ## `nch/nch.db` in the user's data directory.
  if option.len > 0:
    return option
  let env = getEnv("NCH_DB")
  if env.len > 0:
    return env
  getDataDir() / "nch" / "nch.db"

proc loadSpatialite(db: DbConn) {.raises: [StoreError].} =
  ## Load the SpatiaLite extension (geometry types and functions).  It is needed
  ## by every connection, because the triggers of its spatial indexes use it.
  ## (trusted_schema: SQLite will not run those triggers otherwise.)
  var err: cstring
  if enable_load_extension(db, 1) != SQLITE_OK:
    raiseStore("this SQLite cannot load extensions, and nch needs SpatiaLite")
  let rc = load_extension(db, "mod_spatialite", nil, addr err)
  discard enable_load_extension(db, 0)
  if rc != SQLITE_OK:
    let why =
      if err.isNil:
        "unknown error"
      else:
        $err
    raiseStore(
      fmt"cannot load SpatiaLite (is the package that provides mod_spatialite installed?): {why}"
    )
  db.execScript("pragma trusted_schema = 1")

const outOfDate = "; it cannot be updated: run `nch db --delete -f` and import again"

proc recorded(db: DbConn): seq[(string, string)] {.raises: [StoreError].} =
  ## The fragments the database says it has had, each with the checksum of its SQL.
  db.query((string, string), "select name, sha256 from fragment order by name")

proc record(db: DbConn, f: Fragment) {.raises: [StoreError].} =
  db.execute(
    "insert into fragment(name, applied_at, sha256) values (:name, :appliedAt, :sha256)",
    name = f.name,
    appliedAt = getTime().toUnix,
    sha256 = f.checksum,
  )

proc apply(db: DbConn, f: Fragment) {.raises: [StoreError].} =
  ## Run a fragment and record it, as one transaction.
  db.execScript("begin")
  var done = false
  try:
    execScriptAs(db, f.sql, f.ownerName)
      # (a fragment may touch only its own package's tables)
    if not f.seed.isNil:
      f.seed(db)
    record(db, f)
    db.execScript("commit")
    done = true
  except StoreError as e:
    raiseStore(fmt"applying {f.name}: {e.msg}")
  finally:
    if not done:
      try:
        db.execScript("rollback")
      except StoreError:
        discard # (nothing useful can be done)

proc missingFragments(
    have: seq[(string, string)], all: seq[Fragment]
): seq[Fragment] {.raises: [StoreError].} =
  ## The fragments the database has not had yet.  Raises `StoreError` if it has had one this version does not have, or
  ## one made from different SQL: it is of another version, and cannot be brought up to date.
  for (name, sum) in have:
    let known = all.filterIt(it.name == name)
    if known.len == 0:
      raiseStore(fmt"the database is from a newer version of nch (it has '{name}')")
    if known[0].checksum != sum:
      raiseStore(
        fmt"the database was made by a different version of nch (its '{name}' is not the one this version has){outOfDate}"
      )
  for f in all:
    if have.allIt(it[0] != f.name):
      result.add f

proc bringUpToDate(db: DbConn, fragments: seq[Fragment]) {.raises: [StoreError].} =
  db.execScript(
    """create table if not exists fragment (
                    name text primary key,
                    applied_at integer not null,
                    sha256 text not null) strict, without rowid"""
  )
  for f in missingFragments(recorded(db), baseFragments & fragments):
    apply(db, f)

proc appliedFragments*(path: string): seq[(string, string)] {.raises: [StoreError].} =
  ## The fragments (name, checksum) the database file at `path` says it has had, read as they are: nothing is applied,
  ## so this is safe to ask of a database of another version.  Raises `StoreError` if there is no such file, or it is
  ## not one of ours.
  if not fileExists(path):
    raiseStore(fmt"there is no database at {path}")
  var db: DbConn
  try:
    db = db_sqlite.open(path, "", "", "")
  except DbError as e:
    raiseStore(e.msg)
  try:
    result = recorded(db)
  finally:
    try:
      db_sqlite.close(db)
    except DbError:
      discard # (nothing useful can be done)

proc close*(s: Store) {.raises: [].} =
  ## Close the database now (it is also closed when the last copy of the store goes, so this is
  ## only needed to let go of the file at a particular moment).  Closing twice is fine.
  closeConn(s.conn)

proc reclaim*(s: Store) {.raises: [StoreError].} =
  ## Give the space of deleted rows back to the file system (the free pages are removed from the end of the file).
  ## Call it after a big delete, outside a transaction.  Does nothing to a file made without incremental vacuum.
  s.db.execScript("pragma incremental_vacuum")

proc openStore*(
    path: string, fragments: seq[Fragment], access: Access = nil
): Store {.raises: [StoreError].} =
  ## Open the database at `path`, creating the file and applying the fragments
  ## it lacks.  `access` says which package may touch which table (nil: nothing is checked).
  ## Raises StoreError if that cannot be done.
  if path != ":memory:":
    try:
      createDir(parentDir(path))
    except OSError, IOError:
      raiseStore(
        fmt"cannot create the directory for {path}: {getCurrentExceptionMsg()}"
      )
  try:
    result.db = open(path, "", "", "")
  except DbError as e:
    raiseStore(e.msg)
  result.conn = Conn(db: result.db, access: access)
  result.path = path
  try:
    loadSpatialite(result.db)
    registerFunctions(result.db)
    installAccess(result.db, access)
    block:
      # a new file: deleted rows give their space back (`reclaim`), instead of the file only ever growing.  This
      # must be said before the first table is made; a file made without it stays as it is.
      if result.db.scalar(int, "pragma page_count") == 0:
        result.db.execScript("pragma auto_vacuum = incremental")
      result.db.execScript("pragma foreign_keys = on")
      # write-ahead log: a commit does not wait for the disk (the log is synced when it is checkpointed),
      # and readers (the web server's workers) do not wait for a writer.  A power cut can lose the last
      # commits, never corrupt the database; a re-import repeats what was lost.
      result.db.execScript("pragma journal_mode = wal")
      result.db.execScript("pragma synchronous = normal")
      # the log is copied back into the database every 20,000 pages (80 MB), not the default 1,000: a
      # big import then spends about half as long on checkpoints (measured), and the log stays small
      result.db.execScript("pragma wal_autocheckpoint = 20000")
    bringUpToDate(result.db, fragments)
  except StoreError:
    close(result)
    raise

proc setAutoCheckpoint*(s: Store, pages: int) {.raises: [StoreError].} =
  ## Copy the log back into the database whenever it holds this many pages (0: never, leaving it to
  ## someone else, see checkpointer.nim; the last connection to close does it anyway).
  s.db.execScript(fmt"pragma wal_autocheckpoint = {pages}")

proc begin*(s: Store) {.raises: [StoreError].} =
  ## Start a transaction.
  s.db.execScript("begin")

proc commit*(s: Store) {.raises: [StoreError].} =
  ## End the transaction, keeping its changes.
  s.db.execScript("commit")

proc rollback*(s: Store) {.raises: [].} =
  ## Undo the open transaction; a failure here has nowhere useful to go.
  try:
    s.db.execScript("rollback")
  except StoreError:
    discard

const sqliteOpenReadOnly = 1'i32 ## SQLITE_OPEN_READONLY, of sqlite3.h

when defined(macosx):
  const sqliteLib = "libsqlite3(|.0).dylib"
else:
  const sqliteLib = "libsqlite3.so(|.0)"
  ## the library as `db_connector` loads it (its own name for it is not exported)

proc sqliteOpenV2(
  filename: cstring, ppDb: var PSqlite3, flags: int32, zVfs: cstring
): int32 {.cdecl, dynlib: sqliteLib, importc: "sqlite3_open_v2".}
  ## `db_connector` binds only `sqlite3_open`, which takes no flags: it creates a missing file and always opens for
  ## writing.  This is the call that can open read-only.

proc openReadOnly*(
    path: string, fragments: seq[Fragment], access: Access = nil
): Store {.raises: [StoreError].} =
  ## Open the database at `path` and change nothing, for the reading that must have no effect (tab completion): a missing
  ## file is an error and is not created; no pragma is set; the schema is not brought up to date (a database that lacks
  ## a fragment, or has one of another version, is a `StoreError`, as a read-write open would refuse or change it); and
  ## nothing can be written.  SpatiaLite is not loaded, so what is read must not need it.  SQLite may still make the
  ## `-shm` and `-wal` files beside a database in write-ahead mode (it needs them to read one).
  if path == ":memory:" or not fileExists(path):
    raiseStore(fmt"there is no database at {path}")
  var handle: PSqlite3
  if sqliteOpenV2(path, handle, sqliteOpenReadOnly, nil) != SQLITE_OK:
    let why =
      if handle.isNil:
        "out of memory"
      else:
        $lowlevel.errmsg(handle)
    if not handle.isNil:
      discard lowlevel.close(handle)
    raiseStore(fmt"cannot open {path} for reading: {why}")
  result.db = handle
  result.conn = Conn(db: result.db, access: access)
  result.path = path
  try:
    registerFunctions(result.db)
    installAccess(result.db, access)
    let all = baseFragments & fragments
    let todo = missingFragments(recorded(result.db), all)
    if todo.len > 0:
      raiseStore(
        fmt"the database has not had {todo[0].name} yet (any other nch command brings it up to date)"
      )
  except StoreError:
    close(result)
    raise

proc openStore*(g: Globals): Store {.raises: [StoreError].} =
  ## The database the global options point at (read-only if they say so: `openReadOnly`).
  if g.readOnly:
    openReadOnly(resolveDbPath(g.dbPath), g.fragments, g.access)
  else:
    openStore(resolveDbPath(g.dbPath), g.fragments, g.access)
