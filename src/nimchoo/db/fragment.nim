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

  VersionProc* = proc(): string {.nimcall, raises: [].}
    ## Which data a seed would put in now (a hash), worked out when the database is opened.

  Fragment* = object
    name*: string ## "module/file", unique
    sql*: string ## DDL only (data is inserted from Nim)
    seed*: SeedProc ## nil if there is no data to put in
    seedVersion*: string ## which data the seed puts in (a hash), part of the checksum
    # data that can be replaced without destroying the database (the places): not part of the checksum
    version*: VersionProc
      ## nil, or which data there is now; the database remembers which it has
    reseed*: SeedProc ## replaces the data when it is not the version the database has
    legacySums*: seq[string]
      ## checksums that earlier versions recorded and that are still accepted ...
    legacyVersion*: string ## ... meaning the data of this version was loaded

proc checksum*(f: Fragment): string =
  ## The SHA-256 of the fragment's SQL (and of the version of the data its seed puts in), in
  ## hex: recorded with the fragment when it is applied, so that a database made from
  ## different SQL or different data is noticed when it is opened.
  sha256Hex(
    if f.seedVersion.len > 0:
      f.sql & "\n-- seed data: " & f.seedVersion
    else:
      f.sql
  )

func withSeed*(f: Fragment, seed: SeedProc, version = ""): Fragment =
  ## The same fragment, with data to put in after its tables are made.  `version` names
  ## the data (a hash is best): if it changes, databases made with the old data are noticed.
  result = f
  result.seed = seed
  result.seedVersion = version

func withReseed*(f: Fragment, version: VersionProc, reseed: SeedProc): Fragment =
  ## The same fragment, whose data can be replaced: `version` says which data there should be (a
  ## hash); when the database has another, `reseed` makes it so, in a transaction, and the
  ## database remembers the new version.  The data are not part of the fragment's checksum.
  result = f
  result.version = version
  result.reseed = reseed

func withLegacy*(f: Fragment, sums: seq[string], version: string): Fragment =
  ## The same fragment, accepting databases whose recorded checksum is one of `sums` (made when the
  ## data were part of it): they are taken to have the data of `version`.
  result = f
  result.legacySums = sums
  result.legacyVersion = version

proc currentVersion*(f: Fragment): string =
  ## Which data the fragment's seed puts in now.
  if f.version.isNil:
    f.seedVersion
  else:
    f.version()

template fragment*(file: static string): Fragment =
  ## The fragment in `<file>` next to the calling source file.
  const dir = instantiationInfo(-1, true).filename.parentDir
  Fragment(name: lastPathPart(dir) & "/" & file, sql: staticRead(dir / file))
