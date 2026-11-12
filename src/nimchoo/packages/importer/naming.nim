## Naming the activities: each that has no name yet (null) gets its start place and its name from the places near its
## route (see names/activity.nim), kept on the activity as text.  Done at the end of `nch import`, so the names are
## decided in the run that imports; the first time (or after a migration) it names every activity.  If the names are
## needed and cannot be had it is a DownloadError: the activities named so far keep their names, the rest stay null.  With `--offline`
## the activities whose places are not in the cache are left null too, and counted (`left`), without an error.

import std/strformat
import ../db/statement
import ../db/store
import ../../core/errors
import ../names/activity
import ../names/countries
import ../names/lookup
import ../util/profiling/profiling
import ./[route, track]

{.push raises: [].}

type
  GpsErrors* = object
    where*: string ## the file of the activity (else "activity N")
    searches*: int
      ## how many searches for a place were not made, the positions being too far apart

  Named* = object
    total*: int ## activities that had no name
    named*: int ## ... of which now have one
    startOnly*: int ## ... and only a start place
    nothing*: int ## ... and nothing to say
    left*: int
      ## ... and left without a name because `--offline` and the places round them are not in the cache (null: the next run
      ## that may use the network names them)
    gpsErrors*: seq[GpsErrors]
      ## activities with stretches left out of the search for a place along the route (bad GPS fixes)

func gpsErrorCount*(n: Named): int =
  ## The searches not made, in all.
  for e in n.gpsErrors:
    result += e.searches

func leftText*(n: Named): string =
  ## What to say about activities left unnamed because of `--offline`: empty if there are none.
  if n.left > 0:
    fmt"{n.left} left unnamed (--offline)"
  else:
    ""

proc pending*(st: Store): seq[int64] {.raises: [StoreError].} =
  ## The activities not named yet, in the order they began.
  st.db.query(int64, "select id from activity where name is null order by start_t, id")

proc ensureActivityNames*(
    st: Store,
    names: Names,
    progress: proc(done, total: int) {.closure, raises: [].} = nil,
): Named {.raises: [StoreError, DownloadError].} =
  ## Name the activities that have no name yet (the place they started); `progress` is told how far it has got.
  let todo = pending(st)
  result.total = todo.len
  # the route of an activity is read as the stored geometry (one blob), not as a row for each position; an activity with no
  # route (no segment had two points) is read from its positions
  let routeOf =
    prepareStmt(st.db, "select AsBinary(geom) from route where activity_id = ?")
  for k, id in todo:
    var parts: seq[Part]
    timed "naming: read the route":
      routeOf.bindInt(1, id)
      if routeOf.nextRow():
        parts = routeParts(routeOf.blobAt(0))
      routeOf.rewind()
    if parts.len == 0:
      var lons, lats: seq[float]
      for c in readPositions(st.db, ActivityId(id)):
        lons.add c.lon
        lats.add c.lat
      parts.add (lons, lats)
    var got: ActivityNames
    try:
      got = nameActivity(names, parts)
    except OfflineError:
      inc result.left
      if progress != nil:
        progress(k + 1, todo.len)
      continue
    if got.gpsErrors > 0:
      let where = st.db.scalar(
        string,
        """select ifnull((select path from seen_file where file_id = a.file_id limit 1),
                              'activity ' || a.id) from activity a where a.id = :id""",
        id = id,
      )
      result.gpsErrors.add GpsErrors(where: where, searches: got.gpsErrors)
    timed "naming: write the name":
      st.db.execute(
        "update activity set start_place = :startPlace, name = :name where id = :id",
        startPlace = got.start,
        name = got.name,
        id = id,
      )
    if got.name.len > 0:
      inc result.named
    elif got.start.len > 0:
      inc result.startOnly
    else:
      inc result.nothing
    if progress != nil:
      progress(k + 1, todo.len)
