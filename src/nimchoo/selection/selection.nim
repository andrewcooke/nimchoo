## What is selected, as a short key: for naming files made from the selection (see
## cache.nim), so that what a file or URL shows is pinned to one selection.
##
## The key is a hash of the *content* of the selected activities (the SHA-256 of
## each one's file, and its session), not of database ids: the same activities
## give the same key in any database, and a changed selection gives a new one.

import std/[algorithm, sets, strutils]
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
  for e in entries.sorted:
    text.add e & "\n"
  sha256Hex(text)[0 ..< keyLength]

proc selectedIds*(st: Store): seq[int64] {.raises: [StoreError].} =
  ## The ids of the current selection of the store's user, in order.
  guard:
    for row in st.db.fastRows(
      sql"select activity_id from selection where user_id = ? order by 1", st.userId
    ):
      try:
        result.add parseBiggestInt(row[0])
      except ValueError:
        raiseStore("a bad activity id")

proc maxActivityId*(st: Store): int64 {.raises: [StoreError].} =
  ## The highest activity id there is (0 if there are none): the largest an address can name.
  guard:
    try:
      result =
        parseBiggestInt(st.db.getValue(sql"select coalesce(max(id), 0) from activity"))
    except ValueError:
      raiseStore("a bad activity id")

proc ownedIds*(st: Store, ids: seq[int64]): seq[int64] {.raises: [StoreError].} =
  ## Of `ids` (in order), those that are activities of the store's user: an address may name any number, and only the
  ## user's own activities are ever drawn.
  var mine = initHashSet[int64]()
  guard:
    for row in st.db.fastRows(
      sql"""select a.id from activity a join file f on f.id = a.file_id
        where f.user_id = ?""",
      st.userId,
    ):
      try:
        mine.incl parseBiggestInt(row[0])
      except ValueError:
        raiseStore("a bad activity id")
  for id in ids:
    if id in mine:
      result.add id

const checkLength* = 6

proc contentKey*(st: Store, ids: seq[int64]): string {.raises: [StoreError].} =
  ## The key of the *content* of the activities `ids`: of their files and sessions (the same kind of key as the
  ## selection key).
  var entries: seq[string]
  guard:
    for id in ids:
      for row in st.db.fastRows(
        sql"""select f.sha256, a.session from activity a join file f on f.id = a.file_id
          where a.id = ?""",
        id,
      ):
        entries.add row[0] & ":" & row[1]
  keyOf(entries)

proc checkOf*(st: Store, ids: seq[int64]): string {.raises: [StoreError].} =
  ## A short check of the content of the activities `ids` (the first 6 hex digits of `contentKey`).  An address carries
  ## it with its list of activities, so that after the database has been rebuilt (and the ids mean other activities) or
  ## activities deleted, the address is refused and not wrong.  (It checks the address; it is not the key of a cached
  ## file's inputs: that is the whole of `contentKey` and more, see `cache.inputsKey`.)
  contentKey(st, ids)[0 ..< checkLength]
