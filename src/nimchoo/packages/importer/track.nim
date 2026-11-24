## An activity's track as the database holds it: its positions (the arrays of `track`, importer/series.nim), in the
## stretches of riding they belong to (the riding of `activity` cut at its breaks, `ride_break`; see stretch.nim), and
## the breaks themselves, for whoever needs other kinds of them (a plot over time).  Whoever analyses a ride's positions as a
## line (climbs, efforts) reads them here, and so cannot join the two sides of a break: a stretch is a line whose time
## is continuous, and the pieces are not.  (The type has no flat view of all the positions on purpose; whoever needs
## them all, for a place or a window of time, uses `readPositions`.)

import std/[options, strutils]
import ../db/statement
import ../db/store
import ../../core/errors
import ../fit/time
import ../../core/ids
import ./[coord, series, stretch]

{.push raises: [].}

type Track* = seq[seq[Coord]]
  ## One list of positions, in time order, for each stretch of the activity that has any; the
  ## stretches are in time order too.

const
  headSql* = "select start_epoch, n_readings from track where activity_id = :activityId"
  arraysSql* =
    "select offsets_s, lon_semi, lat_semi, alt_fit from track where activity_id = ?"
  ridingSql* =
    "select riding_start_epoch, riding_end_epoch from activity where id = :activityId"
  breaksSql* =
    "select start_epoch, end_epoch, kind from ride_break where activity_id = :activityId order by start_epoch"

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

proc readBreaks*(
    db: DbConn, id: ActivityId
): tuple[riding: Span, breaks: seq[Break]] {.raises: [StoreError].} =
  ## The riding of an activity and its breaks, in time order.  A StoreError for no such activity or a kind not known.
  let riding = db.queryOne(tuple[startT, endT: int64], ridingSql, activityId = id)
  if riding.isNone:
    raiseStore("there is no activity " & $int64(id))
  result.riding =
    Span(startT: UnixTime(riding.get.startT), endT: UnixTime(riding.get.endT))
  for (s, e, kind) in db.query(
    tuple[s, e: int64, kind: string], breaksSql, activityId = id
  ):
    var k: BreakKind
    try:
      k = parseEnum[BreakKind](kind)
    except ValueError:
      raiseStore(
        "a break of activity " & $int64(id) & " is of no known kind: '" & kind & "'"
      )
    result.breaks.add Break(startT: UnixTime(s), endT: UnixTime(e), kind: k)

proc readStretches*(db: DbConn, id: ActivityId): seq[Span] {.raises: [StoreError].} =
  ## The stretches of riding of an activity, in time order (stretch.nim).
  let (riding, breaks) = readBreaks(db, id)
  stretchesOf(riding, breaks)

proc readTrack*(db: DbConn, id: ActivityId): Track {.raises: [StoreError].} =
  ## The positions of an activity, by stretch.
  let all = readPositions(db, id)
  var at = 0 # the positions are in time order, the stretches too
  for g in readStretches(db, id):
    while at < all.len and all[at].t < g.startT:
      inc at
    var piece: seq[Coord]
    while at < all.len and all[at].t <= g.endT:
      piece.add all[at]
      inc at
    if piece.len > 0:
      result.add piece
