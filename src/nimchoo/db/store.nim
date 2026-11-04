## The database: where it lives, opening it (creating it and bringing its
## schema up to date on first use), and the user whose data we work with.
## Every command that uses the database starts with `openStore`.
##
## One user is the default (`user.is_default`): the one used when none is asked for.
## A database with no users gets one, called `default`; if the default user has gone
## but others remain, the oldest of them becomes the default.
##
## The schema is made of fragments (fragment.nim): the database's own, then
## those of the modules, in the order given.  The database remembers which it
## has had in the table `fragment`, so opening applies only the missing ones.
##
## Errors from the database library (`DbError`) are turned into `StoreError`
## here, so nothing above this module sees them.

import std/[os, sequtils, strutils, times]
import db_connector/db_sqlite
import db_connector/sqlite3 as lowlevel
import ../errors
import ../ids
export ids
import ./fragment
import ./statement
export db_sqlite.DbConn, fragment

{.push raises: [].}

const
  defaultUser* = "default"   ## the name of the user made in an empty database
  baseFragments = @[fragment("001-schema.sql")]

type
  ConnObj = object
    db: DbConn

  Conn = ref ConnObj
    ## Owns the connection: it is closed when the last `Store` that points here goes, or earlier
    ## by `close`.  (A `Store` may be copied; the copies share one connection.)

proc closeConn(c: Conn) {.raises: [].} =
  if c != nil and c.db != nil:
    try: db_sqlite.close(c.db)
    except DbError: discard    # nothing useful can be done
    c.db = nil

proc `=destroy`(c: ConnObj) {.raises: [].} =
  if c.db != nil:
    try: db_sqlite.close(c.db)
    except DbError: discard

type
  Store* = object
    db*: DbConn
    conn: Conn
    path*: string      ## the database file (":memory:" for one in memory)
    userId*: UserId
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
    raiseStore("cannot load SpatiaLite (is the package that provides " &
               "mod_spatialite installed?): " & (if err.isNil: "unknown error" else: $err))
  guard:
    db.exec(sql"pragma trusted_schema = 1")

const outOfDate = "; it cannot be updated: run `nch empty --all -f` and import again"

proc recorded(db: DbConn): seq[(string, string)] {.raises: [StoreError].} =
  ## The fragments the database says it has had, each with the checksum of its SQL.
  guard:
    for row in db.fastRows(sql"select name, sha256 from fragment order by name"):
      result.add (row[0], row[1])

proc record(db: DbConn, f: Fragment) {.raises: [StoreError].} =
  guard:
    db.exec(sql"insert into fragment(name, applied_at, sha256, seed_version) values (?, ?, ?, ?)",
            f.name, getTime().toUnix, f.checksum, f.currentVersion)

proc apply(db: DbConn, f: Fragment) {.raises: [StoreError].} =
  ## Run a fragment and record it, as one transaction.
  guard: db.exec(sql"begin")
  var done = false
  try:
    execScript(db, f.sql)
    if not f.seed.isNil: f.seed(db)
    record(db, f)
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
                    applied_at integer not null,
                    sha256 text not null) without rowid""")
    # a database made before checksums were recorded has no such column
    var columns: seq[string]
    for row in db.fastRows(sql"pragma table_info(fragment)"): columns.add row[1]
    if "sha256" notin columns:
      raiseStore("the database was made by an older version of nch" & outOfDate)
    # which data a fragment's seed put in (for the fragments whose data can be replaced)
    if "seed_version" notin columns:
      db.exec(sql"alter table fragment add column seed_version text")
  let have = recorded(db)
  for (name, sum) in have:
    let known = all.filterIt(it.name == name)
    if known.len == 0:
      raiseStore("the database is from a newer version of nch (it has '" & name & "')")
    if known[0].checksum != sum:
      if sum in known[0].legacySums:        # recorded when the data were part of the checksum
        guard:
          db.exec(sql"update fragment set sha256 = ?, seed_version = ? where name = ?",
                  known[0].checksum, known[0].legacyVersion, name)
      else:
        raiseStore("the database was made by a different version of nch (its '" & name &
                   "' is not the one this version has)" & outOfDate)
  for f in all:
    if have.allIt(it[0] != f.name): apply(db, f)
  for f in all:                              # data that can be replaced: is it the version wanted?
    if f.reseed.isNil: continue
    let want = f.currentVersion
    var has = ""
    guard:
      has = db.getValue(sql"select coalesce(seed_version, '') from fragment where name = ?", f.name)
    if has == want: continue
    guard: db.exec(sql"begin")
    var done = false
    try:
      f.reseed(db)
      guard: db.exec(sql"update fragment set seed_version = ? where name = ?", want, f.name)
      guard: db.exec(sql"commit")
      done = true
    except StoreError as e:
      raiseStore("replacing the data of " & f.name & ": " & e.msg)
    finally:
      if not done:
        try: discard db.tryExec(sql"rollback")
        except DbError: discard

proc close*(s: Store) {.raises: [].} =
  ## Close the database now (it is also closed when the last copy of the store goes, so this is
  ## only needed to let go of the file at a particular moment).  Closing twice is fine.
  closeConn(s.conn)

proc openStore*(path: string, fragments: seq[Fragment],
                user = ""): Store {.raises: [StoreError].} =
  ## Open the database at `path`, creating the file and applying the fragments
  ## it lacks, and find `user` ("": the default user, made if there are no users).
  ## Raises StoreError if that cannot be done or the user does not exist.
  if path != ":memory:":
    try:
      createDir(parentDir(path))
    except OSError, IOError:
      raiseStore("cannot create the directory for " & path & ": " &
                 getCurrentExceptionMsg())
  guard:
    result.db = open(path, "", "", "")
    result.conn = Conn(db: result.db)
    result.path = path
  try:
    loadSpatialite(result.db)
    guard:
      result.db.exec(sql"pragma foreign_keys = on")
      # write-ahead log: a commit does not wait for the disk (the log is synced when it is checkpointed),
      # and readers (the web server's workers) do not wait for a writer.  A power cut can lose the last
      # commits, never corrupt the database; a re-import repeats what was lost.
      result.db.exec(sql"pragma journal_mode = wal")
      result.db.exec(sql"pragma synchronous = normal")
      # the log is copied back into the database every 20,000 pages (80 MB), not the default 1,000: a
      # big import then spends about half as long on checkpoints (measured), and the log stays small
      result.db.exec(sql"pragma wal_autocheckpoint = 20000")
    bringUpToDate(result.db, fragments)
    guard:
      if result.db.getValue(sql"select count(*) from user") == "0":
        result.db.exec(sql"insert into user(name, is_default) values (?, 1)", defaultUser)
      elif result.db.getValue(sql"select count(*) from user where is_default = 1") == "0":
        result.db.exec(sql"update user set is_default = 1 where id = (select min(id) from user)")
      let id = if user.len == 0:
                 result.db.getValue(sql"select id from user where is_default = 1")
               else:
                 result.db.getValue(sql"select id from user where name = ?", user)
      if id.len == 0:
        raiseStore("no such user: " & user)
      try:
        result.userId = UserId(parseBiggestInt(id))
      except ValueError:
        raiseStore("bad user id " & id)
      result.userName = result.db.getValue(sql"select name from user where id = ?", id)
  except StoreError:
    close(result)
    raise

proc setAutoCheckpoint*(s: Store, pages: int) {.raises: [StoreError].} =
  ## Copy the log back into the database whenever it holds this many pages (0: never, leaving it to
  ## someone else, see checkpointer.nim; the last connection to close does it anyway).
  guard: s.db.exec(sql("pragma wal_autocheckpoint = " & $pages))

proc begin*(s: Store) {.raises: [StoreError].} =
  guard: s.db.exec(sql"begin")

proc commit*(s: Store) {.raises: [StoreError].} =
  guard: s.db.exec(sql"commit")

proc rollback*(s: Store) {.raises: [].} =
  ## Undo the open transaction; a failure here has nowhere useful to go.
  try: discard s.db.tryExec(sql"rollback")
  except DbError: discard
