## An activity's track as the database holds it: its positions (the arrays of `track`, importer/series.nim), in the
## stretches of riding they belong to (the `segment` table; see stretch.nim).  Whoever analyses a ride's positions as a
## line (climbs, efforts) reads them here, and so cannot join the two sides of a break: a stretch is a line whose time
## is continuous, and the pieces are not.  (The type has no flat view of all the positions on purpose; whoever needs
## them all, for a place or a window of time, uses `readPositions`.)

import ../db/statement
import ../db/store
import ../../core/errors
import ../fit/time
import ../../core/ids
import ./[coord, series]

{.push raises: [].}

type Track* = seq[seq[Coord]]
  ## One list of positions, in time order, for each stretch of the activity that has any; the
  ## stretches are in time order too.

const
  headSql* = "select t0, n from track where activity_id = :activityId"
  arraysSql* = "select t, lon, lat, alt from track where activity_id = ?"
  segmentsSql* =
    "select start_t, end_t from segment where activity_id = :activityId order by n"

proc readPositions*(db: DbConn, id: ActivityId): seq[Coord] {.raises: [StoreError].} =
  ## All the positions of an activity, in time order (none if it has none).
  let head = db.query(tuple[t0, n: int64], headSql, activityId = id)
  if head.len == 0:
    return
  let arrays = prepareStmt(db, arraysSql)
  arrays.bindInt(1, id)
  if not arrays.nextRow():
    return
  decodePositions(
    Positions(
      t0: UnixTime(head[0].t0),
      count: int(head[0].n),
      t: arrays.blobAt(0),
      lon: arrays.blobAt(1),
      lat: arrays.blobAt(2),
      alt: arrays.blobAt(3),
    )
  )

proc readTrack*(db: DbConn, id: ActivityId): Track {.raises: [StoreError].} =
  ## The positions of an activity, by stretch.
  let all = readPositions(db, id)
  var at = 0 # the positions are in time order, the stretches too
  for g in db.query(tuple[startT, endT: int64], segmentsSql, activityId = id):
    while at < all.len and int64(all[at].t) < g.startT:
      inc at
    var piece: seq[Coord]
    while at < all.len and int64(all[at].t) <= g.endT:
      piece.add all[at]
      inc at
    if piece.len > 0:
      result.add piece
