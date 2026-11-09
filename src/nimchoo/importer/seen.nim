## What `nch activities --import` remembers about the paths it has looked at (the table
## `seen_file`): a path whose size and modification time have not changed is
## skipped without reading it.  Rows are collected in a buffer and written in
## batches, so a run over thousands of files makes few transactions.

import std/[options, tables]
import ../db/[statement, store]
import ../errors

{.push raises: [].}

const batchSize* = 200

type
  Seen* = object
    size*, mtime*: int64 ## bytes; Unix seconds
    fileId*: FileId ## the file it was imported as (0 if it failed)
    failure*, message*: string ## the kind (see failure.nim) and text, if it failed

  SeenTable* = Table[string, Seen] ## by path

  SeenBuffer* = object
    rows: seq[tuple[path: string, seen: Seen]]

func matches*(row: Seen, size, mtime: int64): bool =
  ## Whether a file with this size and time is the file the row describes.
  row.size == size and row.mtime == mtime

func failed*(row: Seen): bool =
  ## Whether the file failed when it was seen.
  row.failure.len > 0

proc loadSeen*(s: Store): SeenTable {.raises: [StoreError].} =
  ## Everything known about the paths of the store's user.
  for row in s.db.query(
    tuple[path: string, size, mtime, fileId: int64, failure, message: string],
    """select path, size, mtime, coalesce(file_id, 0),
        coalesce(failure, ''), coalesce(message, '') from seen_file
        where user_id = :userId""",
    userId = s.userId,
  ):
    result[row.path] = Seen(
      size: row.size,
      mtime: row.mtime,
      fileId: FileId(row.fileId),
      failure: row.failure,
      message: row.message,
    )

proc add*(b: var SeenBuffer, path: string, row: Seen) =
  ## Keep a row to be written.
  b.rows.add (path, row)

proc pathOfFile*(s: Store, fileId: FileId): string =
  ## Where the file with this id was imported from, as last recorded (its name
  ## if no path was); "" if unknown.  Never fails: it is only for telling people.
  try:
    let path = s.db.queryOne(
      string,
      "select path from seen_file where user_id = :userId and file_id = :fileId order by path limit 1",
      userId = s.userId,
      fileId = fileId,
    )
    result =
      if path.isSome:
        path.get
      else:
        s.db.queryOne(string, "select name from file where id = :id", id = fileId).get(
          ""
        )
  except StoreError:
    result = ""

func full*(b: SeenBuffer): bool =
  ## Whether it is time to write the rows.
  b.rows.len >= batchSize

proc flush*(s: Store, b: var SeenBuffer) {.raises: [StoreError].} =
  ## Write the buffered rows, as one transaction.  Not to be called inside
  ## another transaction.
  if b.rows.len == 0:
    return
  s.begin()
  var done = false
  let st = prepareStmt(
    s.db,
    "insert or replace into seen_file(user_id, path, " &
      "size, mtime, file_id, failure, message) values (?, ?, ?, ?, ?, ?, ?)",
  )
  try:
    for (path, row) in b.rows:
      st.bindInt(1, s.userId)
      st.bindText(2, path)
      st.bindInt(3, row.size)
      st.bindInt(4, row.mtime)
      if int64(row.fileId) > 0:
        st.bindInt(5, row.fileId)
      else:
        st.bindNull(5)
      st.bindOptText(6, row.failure)
      st.bindOptText(7, row.message)
      st.run()
    s.commit()
    done = true
  finally:
    if not done:
      s.rollback()
  b.rows.setLen(0)
