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

{.push raises: [].}

type
  Fragment* = object
    name*: string    ## "module/file", unique
    sql*: string     ## DDL only (data is inserted from Nim)

template fragment*(file: static string): Fragment =
  ## The fragment in `<file>` next to the calling source file.
  const dir = instantiationInfo(-1, true).filename.parentDir
  Fragment(name: lastPathPart(dir) & "/" & file,
           sql: staticRead(dir / file))
