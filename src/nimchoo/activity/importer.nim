## Importing a FIT file into the database: its activities and their
## coordinates, in one transaction.  Importing the same file again (same
## content, same user) does nothing.

import std/[options, strutils, times]
import checksums/sha2
import db_connector/db_sqlite
import ../db/[statement, store]
import ../errors
import ../profile/model
import ../warnings
import ./extract

{.push raises: [].}

type
  ImportOutcome* = enum ioImported, ioAlreadyImported

  ImportResult* = object
    outcome*: ImportOutcome
    activities*, segments*, coords*: int   ## rows written (0 if already imported)

proc sha256Hex*(data: openArray[byte]): string =
  var text = newString(data.len)
  for i, b in data: text[i] = char(b)
  for c in secureHash(Sha_256, text):
    result.add toLowerAscii(toHex(ord(c), 2))

proc insertActivity(st: Stmt, userId, fileId: int64, a: ActivityData) {.raises: [StoreError].} =
  st.bindInt(1, userId)
  st.bindInt(2, fileId)
  st.bindInt(3, a.session)
  st.bindInt(4, a.startT)
  st.bindInt(5, a.endT)
  st.bindInt(6, a.utcOffsetS)
  st.bindOptText(7, a.sport)
  st.bindOptText(8, a.subSport)
  st.bindReal(9, a.elapsedS)
  st.bindReal(10, a.timerS)
  st.bindReal(11, a.distanceM)
  st.bindInt(12, a.calories)
  st.run()

proc insertSegment(st: Stmt, activityId: int64, n: int, g: Segment)
    {.raises: [StoreError].} =
  st.bindInt(1, activityId)
  st.bindInt(2, int64(n))
  st.bindInt(3, g.startT)
  st.bindInt(4, g.endT)
  st.run()

proc insertCoord(st: Stmt, activityId: int64, c: Coord) {.raises: [StoreError].} =
  st.bindInt(1, activityId)
  st.bindInt(2, c.t)
  st.bindReal(3, c.lon)
  st.bindReal(4, c.lat)
  st.bindReal(5, c.alt)
  st.run()

proc importFile*(s: Store, p: Profile, name: string, data: seq[byte],
                 ws: var seq[Warning]): ImportResult
    {.raises: [FitError, ImportError, StoreError].} =
  ## Import the FIT file `data` (called `name` in the database) for the
  ## store's user.  Warnings are added to `ws`.  Nothing is written unless the
  ## whole file imports.
  let digest = sha256Hex(data)
  guard:
    let known = s.db.getValue(
      sql"select id from file where user_id = ? and sha256 = ?",
      s.userId, digest)
    if known.len > 0:
      return ImportResult(outcome: ioAlreadyImported)
  let found = readActivities(p, data, ws)
  s.begin()
  var committed = false
  var actStmt, segStmt, coordStmt: Option[Stmt]
  try:
    guard:
      s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, ?)",
                s.userId, name, digest, getTime().toUnix)
    let fileId = lastInsertId(s.db)
    actStmt = some(prepareStmt(s.db, "insert into activity(user_id, file_id, session, " &
      "start_t, end_t, utc_offset_s, sport, sub_sport, elapsed_s, timer_s, " &
      "distance_m, calories) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"))
    segStmt = some(prepareStmt(s.db,
      "insert into segment(activity_id, n, start_t, end_t) values (?, ?, ?, ?)"))
    coordStmt = some(prepareStmt(s.db, 
      "insert into coords(activity_id, t, lon, lat, alt) values (?, ?, ?, ?, ?)"))
    result.outcome = ioImported
    for a in found:
      insertActivity(actStmt.get, s.userId, fileId, a)
      let activityId = lastInsertId(s.db)
      for n, g in a.segments: insertSegment(segStmt.get, activityId, n, g)
      for c in a.coords: insertCoord(coordStmt.get, activityId, c)
      inc result.activities
      result.segments += a.segments.len
      result.coords += a.coords.len
    s.commit()
    committed = true
  finally:
    if actStmt.isSome: finalize(actStmt.get)
    if segStmt.isSome: finalize(segStmt.get)
    if coordStmt.isSome: finalize(coordStmt.get)
    if not committed: s.rollback()
