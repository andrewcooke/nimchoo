## Importing a FIT file into the database: its activities and their
## coordinates, in one transaction.  Importing the same file again (same
## content, same user) does nothing.

import std/[options, sets, times]
import ../util/hashing/hashing
import ../db/multirow
import ../db/statement
import ../db/store
import ./channel
import ../../core/errors
import ../fit/model
import ../util/profiling/profiling
import ../util/warnings/warnings
import ./[extract, route]

{.push raises: [].}

type
  ImportOutcome* = enum
    ioImported
    ioDuplicate

  ImportResult* = object
    outcome*: ImportOutcome
    fileId*: FileId ## the `file` row: the new one, or the one it duplicates
    activities*, segments*, coords*: int ## rows written (0 if already imported)
    extras*: seq[ExtraCount] ## what the import steps wrote, in the order of the steps

proc insertActivity(
    st: Stmt, fileId: FileId, a: ActivityData
) {.raises: [StoreError].} =
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

proc insertSegment(
    st: Stmt, activityId: ActivityId, n: int, g: Segment
) {.raises: [StoreError].} =
  st.bindInt(1, activityId)
  st.bindInt(2, int64(n))
  st.bindInt(3, int64(g.startT))
  st.bindInt(4, int64(g.endT))
  st.run()

proc insertCoords(
    m: var MultiInsert, activityId: ActivityId, coords: seq[Coord]
) {.raises: [StoreError].} =
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

type ProfileSource* = proc(): Profile {.closure, raises: [].}
  ## Gives the profile; called only when a file has to be decoded.

type Decoded* = object
  ## What the contents of a FIT file come to, worked out with no database: the activities, the
  ## route of each as bytes (see route.nim), in the same order.  Everything here is plain data, so
  ## it can be made on any thread and handed to the one that writes the database.
  activities*: seq[ActivityData]
  routes*: seq[Option[string]]

func channelsOf*(steps: seq[ImportStep]): seq[string] =
  ## The record fields the import steps want besides the position (see db/channel.nim), once each.
  for step in steps:
    for ch in step.channels:
      if ch notin result:
        result.add ch

proc decodeFile*(
    profile: Profile, data: seq[byte], channels: seq[string], ws: var seq[Warning]
): Decoded {.raises: [FitError, ImportError].} =
  ## Decode a FIT file into its activities.  Warnings are added to `ws` (also if it then raises
  ## FitError, the file being unreadable, or ImportError, it having no activity).
  timed "decode":
    result.activities = readActivities(profile, data, ws, channels)
  timed "route: bytes":
    for a in result.activities:
      result.routes.add routeWkb(a)

const knownFileSql* = "select id from file where user_id = :userId and sha256 = :sha256"

proc knownFile*(s: Store, digest: string): Option[FileId] {.raises: [StoreError].} =
  ## The `file` row of the user's that has this content (hash), if there is one.
  timed "known?":
    result = s.db.queryOne(FileId, knownFileSql, userId = s.userId, sha256 = digest)

proc knownDigests*(s: Store): HashSet[string] {.raises: [StoreError].} =
  ## The hashes of the contents of all the user's files: a worker that sees one of them need not
  ## decode the file (the writer still checks, with `knownFile`, when it comes to write).
  for digest in s.db.query(
    string, "select sha256 from file where user_id = :userId", userId = s.userId
  ):
    result.incl digest

proc writeDecoded*(
    s: Store, name, digest: string, d: Decoded, steps: seq[ImportStep]
): ImportResult {.raises: [StoreError].} =
  ## Write a decoded file (called `name` in the database, with this content hash) for the
  ## store's user, in one transaction: nothing is written unless all of it is.  The import
  ## steps (heart rate, ...) write their rows for each activity.
  s.begin()
  var committed = false
  try:
    var coordInsert = initMultiInsert(
      s.db, "insert into coords(activity_id, t, lon, lat, alt) values ", 5
    )
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, :importedAt)",
      userId = s.userId,
      name = name,
      sha256 = digest,
      importedAt = getTime().toUnix,
    )
    let fileId = FileId(lastInsertId(s.db))
    result.fileId = fileId
    let actStmt = prepareStmt(
      s.db,
      "insert into activity(file_id, session, " &
        "start_t, end_t, utc_offset_s, sport, sub_sport, elapsed_s, timer_s, " &
        "distance_m, calories) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    let segStmt = prepareStmt(
      s.db, "insert into segment(activity_id, n, start_t, end_t) values (?, ?, ?, ?)"
    )
    let routeStmt = prepareStmt(
      s.db, "insert into route(activity_id, geom) values (?, GeomFromWKB(?, 4326))"
    )
    let startStmt = prepareStmt(
      s.db, "update activity set start = MakePoint(?, ?, 4326) where id = ?"
    )
    result.outcome = ioImported
    for step in steps:
      result.extras.add ExtraCount(one: step.label, many: step.labels)
    for i, a in d.activities:
      var activityId = ActivityId(0)
      timed "insert activity":
        insertActivity(actStmt, fileId, a)
        activityId = ActivityId(lastInsertId(s.db))
      timed "insert segments":
        for n, g in a.segments:
          insertSegment(segStmt, activityId, n, g)
      timed "insert coords":
        insertCoords(coordInsert, activityId, a.coords)
      if a.coords.len > 0: # where it started: the first position
        startStmt.bindReal(1, a.coords[0].lon)
        startStmt.bindReal(2, a.coords[0].lat)
        timed "update start":
          startStmt.bindInt(3, activityId)
          startStmt.run()
      timed "route: insert":
        if d.routes[i].isSome:
          routeStmt.bindInt(1, activityId)
          routeStmt.bindBlob(2, d.routes[i].get)
          routeStmt.run()
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
    if not committed:
      s.rollback()

proc importFileWith*(
    s: Store,
    profile: ProfileSource,
    name: string,
    data: seq[byte],
    ws: var seq[Warning],
    steps: seq[ImportStep] = @[],
): ImportResult {.raises: [FitError, ImportError, StoreError].} =
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
