## Importing a FIT file into the database: its activities and their
## coordinates, in one transaction.  Importing the same file again (same
## content, same user) does nothing.

import std/[options, sets, strutils, times]
import ../hashing
import db_connector/db_sqlite
import ../db/[channel, multirow, statement, store]
import ../errors
import ../profile/model
import ../profiling
import ../warnings
import ../places/seed
import ./[extract, route]

{.push raises: [].}

type
  ImportOutcome* = enum ioImported, ioDuplicate

  ImportResult* = object
    outcome*: ImportOutcome
    fileId*: int64              ## the `file` row: the new one, or the one it duplicates
    activities*, segments*, coords*: int   ## rows written (0 if already imported)
    extras*: seq[ExtraCount]    ## what the import steps wrote, in the order of the steps

proc insertActivity(st: Stmt, fileId: int64, a: ActivityData) {.raises: [StoreError].} =
  st.bindInt(1, fileId)
  st.bindInt(2, a.session)
  st.bindInt(3, int64(a.startT))
  st.bindInt(4, int64(a.endT))
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
  st.bindInt(3, int64(g.startT))
  st.bindInt(4, int64(g.endT))
  st.run()

proc insertCoords(m: var MultiInsert, activityId: int64, coords: seq[Coord]) {.raises: [StoreError].} =
  ## All the coordinates of an activity, many rows to a statement.
  var i = 0
  while i < coords.len:
    let n = min(rowsPerStatement, coords.len - i)
    let st = m.statement(n)
    for r in 0 ..< n:
      let c = coords[i + r]
      let b = 5 * r
      st.bindInt(b + 1, activityId)
      st.bindInt(b + 2, int64(c.t))
      st.bindReal(b + 3, c.lon)
      st.bindReal(b + 4, c.lat)
      st.bindReal(b + 5, c.alt)
    st.run()
    i += n

type
  ProfileSource* = proc(): Profile {.closure, raises: [].}
    ## Gives the profile; called only when a file has to be decoded.

type
  Decoded* = object
    ## What the contents of a FIT file come to, worked out with no database: the activities, the
    ## route of each as bytes (see route.nim), in the same order.  Everything here is plain data, so
    ## it can be made on any thread and handed to the one that writes the database.
    activities*: seq[ActivityData]
    routes*: seq[Option[string]]

func channelsOf*(steps: seq[ImportStep]): seq[string] =
  ## The record fields the import steps want besides the position (see db/channel.nim), once each.
  for step in steps:
    for ch in step.channels:
      if ch notin result: result.add ch

proc decodeFile*(profile: Profile, data: seq[byte], channels: seq[string],
                 ws: var seq[Warning]): Decoded {.raises: [FitError, ImportError].} =
  ## Decode a FIT file into its activities.  Warnings are added to `ws` (also if it then raises
  ## FitError, the file being unreadable, or ImportError, it having no activity).
  timed "decode":
    result.activities = readActivities(profile, data, ws, channels)
  timed "route: bytes":
    for a in result.activities: result.routes.add routeWkb(a)

proc knownFile*(s: Store, digest: string): Option[int64] {.raises: [StoreError].} =
  ## The `file` row of the user's that has this content (hash), if there is one.
  guard:
    var known = ""
    timed "known?":
      known = s.db.getValue(
        sql"select id from file where user_id = ? and sha256 = ?",
        s.userId, digest)
    if known.len > 0:
      try:
        return some(parseBiggestInt(known))
      except ValueError:
        raiseStore("bad file id " & known)

proc knownDigests*(s: Store): HashSet[string] {.raises: [StoreError].} =
  ## The hashes of the contents of all the user's files: a worker that sees one of them need not
  ## decode the file (the writer still checks, with `knownFile`, when it comes to write).
  guard:
    for r in s.db.fastRows(sql"select sha256 from file where user_id = ?", s.userId):
      result.incl r[0]

proc writeDecoded*(s: Store, name, digest: string, d: Decoded,
                   steps: seq[ImportStep]): ImportResult {.raises: [StoreError].} =
  ## Write a decoded file (called `name` in the database, with this content hash) for the
  ## store's user, in one transaction: nothing is written unless all of it is.  The import
  ## steps (heart rate, ...) write their rows for each activity.
  s.begin()
  var committed = false
  var actStmt, segStmt, routeStmt, startStmt: Option[Stmt]
  var coordInsert = initMultiInsert(s.db, "insert into coords(activity_id, t, lon, lat, alt) values ", 5)
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
    routeStmt = some(prepareStmt(s.db,
      "insert into route(activity_id, geom) values (?, GeomFromWKB(?, 4326))"))
    startStmt = some(prepareStmt(s.db,
      "update activity set start = MakePoint(?, ?, 4326), place_id = ? where id = ?"))
    result.outcome = ioImported
    for step in steps:
      result.extras.add ExtraCount(one: step.label, many: step.labels)
    for i, a in d.activities:
      var activityId = 0'i64
      timed "insert activity":
        insertActivity(actStmt.get, fileId, a)
        activityId = lastInsertId(s.db)
      timed "insert segments":
        for n, g in a.segments: insertSegment(segStmt.get, activityId, n, g)
      timed "insert coords":
        insertCoords(coordInsert, activityId, a.coords)
      if a.coords.len > 0:                  # where it started: the first position
        startStmt.get.bindReal(1, a.coords[0].lon)
        startStmt.get.bindReal(2, a.coords[0].lat)
        var near: Option[Nearest]
        timed "nearest place":
          near = nearestPlace(s.db, a.coords[0].lon, a.coords[0].lat)
        timed "update start":
          if near.isSome: startStmt.get.bindInt(3, near.get.id) else: startStmt.get.bindNull(3)
          startStmt.get.bindInt(4, activityId)
          startStmt.get.run()
      timed "route: insert":
        if d.routes[i].isSome:
          routeStmt.get.bindInt(1, activityId)
          routeStmt.get.bindBlob(2, d.routes[i].get)
          routeStmt.get.run()
      for i, step in steps:
        timed "step: " & step.label:
          result.extras[i].n += step.write(s.db, activityId, a.samples)
      inc result.activities
      result.segments += a.segments.len
      result.coords += a.coords.len
    timed "commit":
      s.commit()
    committed = true
  finally:
    if actStmt.isSome: finalize(actStmt.get)
    if segStmt.isSome: finalize(segStmt.get)
    coordInsert.release()
    if routeStmt.isSome: finalize(routeStmt.get)
    if startStmt.isSome: finalize(startStmt.get)
    if not committed: s.rollback()


proc importFileWith*(s: Store, profile: ProfileSource, name: string,
                     data: seq[byte], ws: var seq[Warning],
                     steps: seq[ImportStep] = @[]): ImportResult
    {.raises: [FitError, ImportError, StoreError].} =
  ## Import the FIT file `data` (called `name` in the database) for the
  ## store's user.  Warnings are added to `ws`.  Nothing is written unless the
  ## whole file imports.  A file already imported (same content) is recognised
  ## by its hash before anything is decoded, so `profile` is not called.
  var digest = ""
  timed "hash":
    digest = sha256Hex(data)
  let known = knownFile(s, digest)
  if known.isSome:
    return ImportResult(outcome: ioDuplicate, fileId: known.get)
  let d = decodeFile(profile(), data, channelsOf(steps), ws)
  writeDecoded(s, name, digest, d, steps)

proc importFile*(s: Store, p: Profile, name: string, data: seq[byte],
                 ws: var seq[Warning], steps: seq[ImportStep] = @[]): ImportResult
    {.raises: [FitError, ImportError, StoreError].} =
  ## `importFileWith` for a profile already in hand.
  importFileWith(s, proc(): Profile {.closure, raises: [].} = p, name, data, ws, steps)
