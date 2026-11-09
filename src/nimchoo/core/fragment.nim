## A fragment of the database schema: a file of DDL that belongs to a package.  A package keeps its
## fragments, DDL files, in its own directory and lists them in its `package.nim`:
##
##     const package* = Package(fragments: @[fragment("001-schema.sql"), fragment("002-more.sql")])
##
## `fragment` reads `<file>` next to the file that calls it, when the program is compiled, and names the
## fragment `package/file` after the directory.  The database as a whole is made by applying the
## fragments of all packages in dependency order (see packages/db/store.nim).  The checksum of a fragment is in
## packages/db/fragment.nim (it needs `hashing`, which is a package and so may not be imported here).

import std/os
import db_connector/db_sqlite
import ./errors

{.push raises: [].}

type
  SeedProc* = proc(db: DbConn) {.nimcall, raises: [StoreError].}
    ## Code that fills the tables of a fragment with data the program carries (the list of
    ## places).  Run once, right after the fragment's SQL and in the same transaction.

  Fragment* = object
    name*: string ## "package/file", unique
    sql*: string ## DDL only (data is inserted from Nim)
    seed*: SeedProc ## nil if there is no data to put in
    seedVersion*: string ## which data the seed puts in (a hash), part of the checksum

func withSeed*(f: Fragment, seed: SeedProc, version = ""): Fragment =
  ## The same fragment, with data to put in after its tables are made.  `version` names
  ## the data (a hash is best): if it changes, databases made with the old data are noticed.
  result = f
  result.seed = seed
  result.seedVersion = version

template fragment*(file: static string): Fragment =
  ## The fragment in `<file>` next to the calling source file.
  const dir = instantiationInfo(-1, true).filename.parentDir
  Fragment(name: lastPathPart(dir) & "/" & file, sql: staticRead(dir / file))
