## What is selected, as a short key: for naming files made from the selection (see
## cache.nim), so that what a file or URL shows is pinned to one selection.
##
## The key is a hash of the *content* of the selected activities (the SHA-256 of
## each one's file, and its session), not of database ids: the same activities
## give the same key in any database, and a changed selection gives a new one.

import std/algorithm
import ../hashing
import db_connector/db_sqlite
import ../db/store
import ../errors

{.push raises: [].}

const keyLength* = 12

func keyOf*(entries: seq[string]): string =
  ## The key of a selection, from "file-sha256:session" for each activity (in
  ## any order): the first 12 hex digits of the SHA-256 of the sorted entries.
  var text = ""
  for e in entries.sorted: text.add e & "\n"
  sha256Hex(text)[0 ..< keyLength]

proc selectionKey*(st: Store): string {.raises: [StoreError].} =
  ## The key of the current selection of the store's user.
  var entries: seq[string]
  guard:
    for row in st.db.fastRows(sql"""select f.sha256, a.session
        from selection s join activity a on a.id = s.activity_id
        join file f on f.id = a.file_id where s.user_id = ?""", st.userId):
      entries.add row[0] & ":" & row[1]
  keyOf(entries)
