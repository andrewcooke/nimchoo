## What `nch import` remembers about the paths it has looked at (the table
## `seen_file`): a path whose size and modification time have not changed is
## skipped without reading it.  Rows are collected in a buffer and written in
## batches, so a run over thousands of files makes few transactions.

import std/[strutils, tables]
import db_connector/db_sqlite
import ../db/[statement, store]
import ../errors

{.push raises: [].}

const batchSize* = 200

type
  Seen* = object
    size*, mtime*: int64          ## bytes; Unix seconds
    fileId*: int64                ## the file it was imported as (0 if it failed)
    failure*, message*: string    ## the kind (see failure.nim) and text, if it failed

  SeenTable* = Table[string, Seen]   ## by path

  SeenBuffer* = object
    rows: seq[tuple[path: string, seen: Seen]]

func matches*(row: Seen, size, mtime: int64): bool =
  ## Whether a file with this size and time is the file the row describes.
  row.size == size and row.mtime == mtime

func failed*(row: Seen): bool = row.failure.len > 0

proc loadSeen*(s: Store): SeenTable {.raises: [StoreError].} =
  ## Everything known about the paths of the store's user.
  guard:
    for row in s.db.fastRows(sql"""select path, size, mtime, coalesce(file_id, 0),
        coalesce(failure, ''), coalesce(message, '') from seen_file
        where user_id = ?""", s.userId):
      try:
        result[row[0]] = Seen(size: parseBiggestInt(row[1]),
                              mtime: parseBiggestInt(row[2]),
                              fileId: parseBiggestInt(row[3]),
                              failure: row[4], message: row[5])
      except ValueError:
        raiseStore("a bad row in seen_file for " & row[0])

proc add*(b: var SeenBuffer, path: string, row: Seen) =
  b.rows.add (path, row)

proc pathOfFile*(s: Store, fileId: int64): string =
  ## Where the file with this id was imported from, as last recorded (its name
  ## if no path was); "" if unknown.  Never fails: it is only for telling people.
  try:
    guard:
      result = s.db.getValue(sql"select path from seen_file where user_id = ? and file_id = ? order by path limit 1",
                             s.userId, fileId)
      if result.len == 0:
        result = s.db.getValue(sql"select name from file where id = ?", fileId)
  except StoreError:
    result = ""

func full*(b: SeenBuffer): bool = b.rows.len >= batchSize

proc flush*(s: Store, b: var SeenBuffer) {.raises: [StoreError].} =
  ## Write the buffered rows, as one transaction.  Not to be called inside
  ## another transaction.
  if b.rows.len == 0: return
  s.begin()
  var done = false
  let st = prepareStmt(s.db, "insert or replace into seen_file(user_id, path, " &
    "size, mtime, file_id, failure, message) values (?, ?, ?, ?, ?, ?, ?)")
  try:
    for (path, row) in b.rows:
      st.bindInt(1, s.userId)
      st.bindText(2, path)
      st.bindInt(3, row.size)
      st.bindInt(4, row.mtime)
      if row.fileId > 0: st.bindInt(5, row.fileId) else: st.bindNull(5)
      st.bindOptText(6, row.failure)
      st.bindOptText(7, row.message)
      st.run()
    s.commit()
    done = true
  finally:
    finalize(st)
    if not done: s.rollback()
  b.rows.setLen(0)
