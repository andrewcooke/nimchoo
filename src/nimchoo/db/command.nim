## `nch db`: the database file.  With no arguments it says where it is and how big; `--delete -f` deletes it, and
## with it the data of every user (the cache, which can be made again, is `nch cache`).  Does nothing without
## -f; on a terminal it then counts down, in red, so there is time to press Ctrl-C.

import std/[os, strutils]
import db_connector/db_sqlite
import ../cli/[args, common]
import ../download/fetch
import ../errors
import ../ui/[live, logfile]
import ../user/wipe
import ./[statement, store]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] db
       nch [--db PATH] db --delete -f

Without options, say where the database is and how big.

  --delete      delete the database file, and with it the users and all their data: files, activities,
                climbs, landmarks, names.  (The cache survives, so nothing is downloaded again.  To delete
                less: `nch activities --all --delete -f` keeps the users, `nch climbs --all --delete -f`
                keeps the activities.)  The next command that needs a database makes a new one.
  -f, --force   really do it: on a terminal there are then 5 seconds in which to press Ctrl-C
  -h, --help    show this help
"""

type DbArgs = object
  delete, force, help: bool

proc size(path: string): int64 =
  ## The database file with its journal files.
  for suffix in ["", "-journal", "-wal", "-shm"]:
    try:
      if fileExists(path & suffix):
        result += getFileSize(path & suffix)
    except OSError:
      discard

proc freeSpace(path: string): string =
  ## ", 12 MB free" when a deleted row's space is waiting to be reused or given back; "" if none or unknown.
  try:
    let db = open(path, "", "", "")
    defer:
      db.close()
    let free =
      db.scalar(int64, "pragma freelist_count") * db.scalar(int64, "pragma page_size")
    if free > 0:
      result = ", " & humanBytes(free) & " free"
  except DbError, StoreError:
    discard

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch db ARGS`; returns the exit status.
  var given = DbArgs()
  let spec = Spec[DbArgs](
    opts: @[
      flag(DbArgs, ["-h", "--help"], help),
      flag(DbArgs, ["-f", "--force"], force),
      flag(DbArgs, ["--delete"], delete),
    ]
  )
  let why = parseOptions(args, spec, given)
  if why.len > 0:
    return usageError("nch db", usage, why)
  if given.help:
    stdout.say usage
    return exitOk
  if given.force and not given.delete:
    return usageError("nch db", usage, "-f goes with --delete")
  let path = resolveDbPath(g.dbPath)
  if not fileExists(path):
    stdout.say "no database at " & path & "\n"
    return exitOk
  if not given.delete:
    stdout.say path & " (" & humanBytes(size(path)) & freeSpace(path) & ")\n"
    return exitOk
  let what =
    "the database " & path & " (" & humanBytes(size(path)) &
    ") with the data of every user"
  if not given.force:
    return failure("nch db", "would delete " & what & "; use -f to confirm")
  if canLive():
    countdown(newTerminalLive(), what, waitSeconds, sleepMs)
  try:
    for suffix in ["", "-journal", "-wal", "-shm"]:
      removeFile path & suffix
  except OSError as e:
    return failure("nch db", "cannot delete " & path & ": " & e.msg)
  g.log.log(lvInfo, cmDb, leDeleted, "deleted " & what)
  sayDeleted("deleted " & what)
  exitOk
