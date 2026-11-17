## What is left of the counters of tables (`002-versions.sql`, dropped by `003-drop-versions.sql`): the seeds of the two
## fragments, which a database applies in turn.  Kept until the next squash folds both fragments away.
##
## The counters (a table `table_version`, kept by triggers on every owned table, and a random `database_identity`) were for
## keys of cached frames (dev/display-arch/plan.md, step 4); views are made on every request, nothing is cached, and they
## were dropped (2026-11-16).

import std/strformat
import ../../core/errors
import ./statement

{.push raises: [].}

proc seedIdentity*(db: DbConn) {.raises: [StoreError].} =
  ## The seed of `002-versions.sql` (its version is part of the fragment's checksum, so it stays while the fragment does).
  db.execute(
    "insert into database_identity(one, id) values (1, lower(hex(randomblob(16))))"
  )

proc dropCounters*(db: DbConn) {.raises: [StoreError].} =
  ## The seed of `003-drop-versions.sql`: drop the triggers that kept the counters (`tv_TABLE_i`, `_u`, `_d`), which exist
  ## only in a database opened while they were made.
  let names = db.query(
    string,
    "select name from sqlite_master where type = 'trigger' and name like 'tv\\_%' escape '\\'",
  )
  for name in names:
    # (a name cannot be bound; these come from the database and are quoted)
    db.execScriptAs(fmt"""drop trigger "{name}"""", "")
