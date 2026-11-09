## An activity's track as the database holds it: its positions, in the stretches of riding they
## belong to (the `segment` table; see stretch.nim).  Whoever analyses a ride's positions as a
## line (climbs, efforts) reads them here, and so cannot join the two sides of a break: a stretch
## is a line whose time is continuous, and the pieces are not.  (The type has no flat view of all
## the positions on purpose.)

import std/options
import ../db/[statement, store]
import ../core/errors
import ../packages/fit/time
import ../core/ids
import ./extract

{.push raises: [].}

type Track* = seq[seq[Coord]]
  ## One list of positions, in time order, for each stretch of the activity that has any; the
  ## stretches are in time order too.

const trackSql* = """select s.n, c.t, c.lon, c.lat, c.alt from segment s
     join coords c on c.activity_id = s.activity_id and c.t between s.start_t and s.end_t
     where s.activity_id = :activityId order by s.n, c.t"""

proc readTrack*(db: DbConn, id: ActivityId): Track {.raises: [StoreError].} =
  ## The positions of an activity, by stretch.
  var current = -1 # the stretch the last row belonged to
  for r in db.query(
    tuple[n: int, t: int64, lon, lat: float, alt: Option[float]],
    trackSql,
    activityId = id,
  ):
    if r.n != current:
      current = r.n
      result.add @[]
    result[^1].add Coord(t: UnixTime(r.t), lon: r.lon, lat: r.lat, alt: r.alt)
