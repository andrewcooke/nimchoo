## A fragment of the database schema: a file of DDL that belongs to a module.
## A module keeps its fragments, DDL files, in its own directory and lists them
## in its `ddl.nim`:
##
##     const fragments* = @[fragment("001-schema.sql"), fragment("002-more.sql")]
##
## `fragment` reads `<file>` next to the file that calls it, when the
## program is compiled, and names the fragment `module/file` after the
## directory.  The database as a whole is made by applying the fragments of all
## modules in order (see store.nim); the list is put together in modules.nim.

import std/os
import ../hashing
import db_connector/db_sqlite
import ../errors

{.push raises: [].}

type
  SeedProc* = proc(db: DbConn) {.nimcall, raises: [StoreError].}
    ## Code that fills the tables of a fragment with data the program carries (the list of
    ## places).  Run once, right after the fragment's SQL and in the same transaction.

  Fragment* = object
    name*: string    ## "module/file", unique
    sql*: string     ## DDL only (data is inserted from Nim)
    seed*: SeedProc  ## nil if there is no data to put in
    seedVersion*: string  ## which data the seed puts in (a hash), part of the checksum

proc checksum*(f: Fragment): string =
  ## The SHA-256 of the fragment's SQL (and of the version of the data its seed puts in), in
  ## hex: recorded with the fragment when it is applied, so that a database made from
  ## different SQL or different data is noticed when it is opened.
  sha256Hex(if f.seedVersion.len > 0: f.sql & "\n-- seed data: " & f.seedVersion else: f.sql)

func withSeed*(f: Fragment, seed: SeedProc, version = ""): Fragment =
  ## The same fragment, with data to put in after its tables are made.  `version` names
  ## the data (a hash is best): if it changes, databases made with the old data are noticed.
  result = f
  result.seed = seed
  result.seedVersion = version

template fragment*(file: static string): Fragment =
  ## The fragment in `<file>` next to the calling source file.
  const dir = instantiationInfo(-1, true).filename.parentDir
  Fragment(name: lastPathPart(dir) & "/" & file,
           sql: staticRead(dir / file))
