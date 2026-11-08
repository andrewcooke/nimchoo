## An activity's track as the database holds it: its positions, in the stretches of riding they
## belong to (the `segment` table; see stretch.nim).  Whoever analyses a ride's positions as a
## line (climbs, efforts) reads them here, and so cannot join the two sides of a break: a stretch
## is a line whose time is continuous, and the pieces are not.  (The type has no flat view of all
## the positions on purpose.)

import std/[options, strutils]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ../fit/time
import ../ids
import ./extract

{.push raises: [].}

type Track* = seq[seq[Coord]]
  ## One list of positions, in time order, for each stretch of the activity that has any; the
  ## stretches are in time order too.

proc readTrack*(db: DbConn, id: ActivityId): Track {.raises: [StoreError].} =
  ## The positions of an activity, by stretch.
  var current = -1 # the stretch the last row belonged to
  guard:
    for r in db.fastRows(
      sql"""select s.n, c.t, c.lon, c.lat, c.alt from segment s
            join coords c on c.activity_id = s.activity_id and c.t between s.start_t and s.end_t
            where s.activity_id = ? order by s.n, c.t""",
      id,
    ):
      try:
        let n = parseInt(r[0])
        if n != current:
          current = n
          result.add @[]
        result[^1].add Coord(
          t: UnixTime(parseBiggestInt(r[1])),
          lon: parseFloat(r[2]),
          lat: parseFloat(r[3]),
          alt:
            if r[4].len > 0:
              some(parseFloat(r[4]))
            else:
              none(float),
        )
      except ValueError:
        raiseStore("a bad coordinate in the database")
