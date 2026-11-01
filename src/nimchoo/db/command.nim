## `nch destroy`: delete the whole database, or (with --user) one user and
## everything that belongs to them.  Refuses to do anything without --force.
## (Everything belongs to a user through `on delete cascade`, so deleting the
## user row is enough; this module knows no other module's tables.)

import std/os
import db_connector/db_sqlite
import ../cli/common
import ../errors
import ../ui/logfile
import ./store

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] destroy -f

Without --user: delete the database file, and with it the data of every user.
With --user NAME: delete that user and all their data (the default user is
created again, empty, the next time the database is opened).

Nothing is deleted without -f.

  -f, --force   really do it
  -h, --help    show this help
"""

proc sizeOf(path: string): string =
  try: $getFileSize(path) & " bytes"
  except OSError: "unknown size"

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch destroy ARGS`; returns the exit status.
  var force = false
  for a in args:
    if a in ["-h", "--help"]:
      stdout.say usage
      return exitOk
    elif a in ["-f", "--force"]:
      force = true
    else:
      return usageError("nch destroy", usage, "unexpected argument " & a)
  let path = resolveDbPath(g.dbPath)
  if not fileExists(path):
    stdout.say "no database at " & path & ": nothing to destroy\n"
    return exitOk
  if g.user.len == 0:
    if not force:
      return failure("nch destroy", "would delete the database " & path & " (" &
        sizeOf(path) & ", every user); use -f to do it")
    try:
      for suffix in ["", "-journal", "-wal", "-shm"]:
        removeFile path & suffix
    except OSError as e:
      return failure("nch destroy", "cannot delete " & path & ": " & e.msg)
    g.log.log(lvInfo, "destroy", "deleted the database " & path)
    stdout.say "deleted the database " & path & "\n"
    return exitOk
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch destroy", e.msg)
  defer: st.close()
  if not force:
    return failure("nch destroy", "would delete the user '" & g.user &
      "' and all their data from " & path & "; use -f to do it")
  try:
    guard:
      st.db.exec(sql"delete from user where id = ?", st.userId)
      st.db.exec(sql"vacuum")
  except StoreError as e:
    return failure("nch destroy", e.msg)
  g.log.log(lvInfo, "destroy", "deleted the user '" & g.user & "' from " & path)
  stdout.say "deleted the user '" & g.user & "' and all their data\n"
  exitOk
