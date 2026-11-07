## Copying the write-ahead log back into the database, on a thread of its own, while a long import
## goes on.  SQLite does this by itself when the log reaches a size, but then the writer waits
## for it: with a big log that is a pause of a third of a second or more, several times in a long
## import.  A second connection can do it with a "passive" checkpoint, which does not stop the
## writer.  (The writer's own checkpointing is switched off meanwhile: see `batch.nim`.)
##
## The thread uses a connection of its own and nothing else is shared with it but a flag.

import std/[atomics, os, typedthreads]
import db_connector/db_sqlite

{.push raises: [].}

const
  logThreshold = 8 * 1024 * 1024 ## bytes of log that are worth copying back
  pollMs = 50

type Checkpointer* = object
  thread: Thread[string]
  running*: bool

var stopRequested: Atomic[bool]

proc loop(path: string) {.thread.} =
  var db: DbConn
  try:
    db = open(path, "", "", "")
  except DbError:
    return # (no checkpoints then: the log just grows until the end)
  var idle = 0
  {.cast(gcsafe).}:
    while not stopRequested.load():
      sleep(pollMs)
      inc idle
      if idle * pollMs < 250:
        continue
      idle = 0
      try:
        if fileExists(path & "-wal") and getFileSize(path & "-wal") > logThreshold:
          db.exec(sql"pragma wal_checkpoint(PASSIVE)")
      except DbError, OSError:
        discard # (try again later)
  try:
    db.close()
  except DbError:
    discard

proc startCheckpointer*(path: string): Checkpointer =
  ## Start watching the database file at `path` (nothing is started for a database not in a file).
  if path.len == 0 or path == ":memory:":
    return
  {.cast(gcsafe).}:
    stopRequested.store(false)
  try:
    createThread(result.thread, loop, path)
    result.running = true
  except ResourceExhaustedError:
    discard

proc stop*(c: var Checkpointer) =
  ## Stop the thread and wait for it (its connection is then closed).
  if not c.running:
    return
  {.cast(gcsafe).}:
    stopRequested.store(true)
  joinThread(c.thread)
  c.running = false
