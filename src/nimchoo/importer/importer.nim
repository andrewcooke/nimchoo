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
import ./[extract, route]

{.push raises: [].}

type
  ImportOutcome* = enum ioImported, ioDuplicate

  ImportResult* = object
    outcome*: ImportOutcome
    fileId*: int64              ## the `file` row: the new one, or the one it duplicates
    activities*, segments*, coords*: int   ## rows written (0 if already imported)

proc sha256Hex*(data: openArray[byte]): string =
  var text = newString(data.len)
  for i, b in data: text[i] = char(b)
  for c in secureHash(Sha_256, text):
    result.add toLowerAscii(toHex(ord(c), 2))

proc insertActivity(st: Stmt, fileId: int64, a: ActivityData) {.raises: [StoreError].} =
  st.bindInt(1, fileId)
  st.bindInt(2, a.session)
  st.bindInt(3, a.startT)
  st.bindInt(4, a.endT)
  st.bindInt(5, a.utcOffsetS)
  st.bindOptText(6, a.sport)
  st.bindOptText(7, a.subSport)
  st.bindReal(8, a.elapsedS)
  st.bindReal(9, a.timerS)
  st.bindReal(10, a.distanceM)
  st.bindInt(11, a.calories)
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

type
  ProfileSource* = proc(): Profile {.closure, raises: [].}
    ## Gives the profile; called only when a file has to be decoded.

proc importFileWith*(s: Store, profile: ProfileSource, name: string,
                     data: seq[byte], ws: var seq[Warning]): ImportResult
    {.raises: [FitError, ImportError, StoreError].} =
  ## Import the FIT file `data` (called `name` in the database) for the
  ## store's user.  Warnings are added to `ws`.  Nothing is written unless the
  ## whole file imports.  A file already imported (same content) is recognised
  ## by its hash before anything is decoded, so `profile` is not called.
  let digest = sha256Hex(data)
  guard:
    let known = s.db.getValue(
      sql"select id from file where user_id = ? and sha256 = ?",
      s.userId, digest)
    if known.len > 0:
      try:
        return ImportResult(outcome: ioDuplicate,
                            fileId: parseBiggestInt(known))
      except ValueError:
        raiseStore("bad file id " & known)
  let found = readActivities(profile(), data, ws)
  s.begin()
  var committed = false
  var actStmt, segStmt, coordStmt, routeStmt, startStmt: Option[Stmt]
  try:
    guard:
      s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, ?)",
                s.userId, name, digest, getTime().toUnix)
    let fileId = lastInsertId(s.db)
    result.fileId = fileId
    actStmt = some(prepareStmt(s.db, "insert into activity(file_id, session, " &
      "start_t, end_t, utc_offset_s, sport, sub_sport, elapsed_s, timer_s, " &
      "distance_m, calories) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"))
    segStmt = some(prepareStmt(s.db,
      "insert into segment(activity_id, n, start_t, end_t) values (?, ?, ?, ?)"))
    coordStmt = some(prepareStmt(s.db, 
      "insert into coords(activity_id, t, lon, lat, alt) values (?, ?, ?, ?, ?)"))
    routeStmt = some(prepareStmt(s.db,
      "insert into route(activity_id, geom) values (?, GeomFromText(?, 4326))"))
    startStmt = some(prepareStmt(s.db,
      "update activity set start = MakePoint(?, ?, 4326) where id = ?"))
    result.outcome = ioImported
    for a in found:
      insertActivity(actStmt.get, fileId, a)
      let activityId = lastInsertId(s.db)
      for n, g in a.segments: insertSegment(segStmt.get, activityId, n, g)
      for c in a.coords: insertCoord(coordStmt.get, activityId, c)
      if a.coords.len > 0:                  # where it started: the first position
        startStmt.get.bindReal(1, a.coords[0].lon)
        startStmt.get.bindReal(2, a.coords[0].lat)
        startStmt.get.bindInt(3, activityId)
        startStmt.get.run()
      let wkt = routeWkt(a)
      if wkt.isSome:
        routeStmt.get.bindInt(1, activityId)
        routeStmt.get.bindText(2, wkt.get)
        routeStmt.get.run()
      inc result.activities
      result.segments += a.segments.len
      result.coords += a.coords.len
    s.commit()
    committed = true
  finally:
    if actStmt.isSome: finalize(actStmt.get)
    if segStmt.isSome: finalize(segStmt.get)
    if coordStmt.isSome: finalize(coordStmt.get)
    if routeStmt.isSome: finalize(routeStmt.get)
    if startStmt.isSome: finalize(startStmt.get)
    if not committed: s.rollback()

proc importFile*(s: Store, p: Profile, name: string, data: seq[byte],
                 ws: var seq[Warning]): ImportResult
    {.raises: [FitError, ImportError, StoreError].} =
  ## `importFileWith` for a profile already in hand.
  importFileWith(s, proc(): Profile {.closure, raises: [].} = p, name, data, ws)
