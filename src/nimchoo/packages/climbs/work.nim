## Bringing the climbs up to date: for every activity not yet looked at, in the order of their start
## times (all users together, so that the catalogue does not depend on whose rides came first), find
## the climbs in it and match it against the sectors, and match any new sector against the earlier
## rides.  Done when a command wants the climbs (as `ff` does for impulses), and kept.
##
## For an activity:
##   1. the sectors near its route: its passes over them are efforts (this needs only positions and
##      times, so a ride with no altitude gets efforts on known climbs);
##   2. its climbs (from the altitude): one that is not a stored sector again becomes a sector;
##   3. a new sector is matched against the ride it came from and every earlier ride near it.
## A ride is read as its stretches of riding (importer/track.nim) and everything above is done in each
## stretch, never across a break: a pause the device made by itself is inside a stretch, and a stop by
## hand or a jump (a car, a train) is between two, so an effort or a climb cannot include road the rider
## did not ride.
##
## Each activity is one transaction, and is then recorded in `climbs_done` (also when nothing was
## found), with the version of the method.  If the method changes the version does, and
## `clearClimbs` (`nch climbs --all --delete`) starts again.

import std/[math, options, tables]
import ../db/statement
import ../db/store
import ../../core/errors
import ../../core/ids
import ../importer/extract
import ../importer/track
import ../util/lookup/lookup
import ../util/profiling/profiling
import ./[detect, match, ordinal, overlap, profile]

{.push raises: [].}

const
  algorithmVersion* = 4
    ## 4: a ride is read as its stretches of riding (importer/stretch.nim), and a climb or an effort never crosses a break.  3: the profile every 5 m and not smoothed.  2: a climb that is a repeat of a stored one but earned the ride no effort on it is a sector of its own
  margin = 0.001 ## degrees (about 100 m) added to a box that is looked for
  ridePointLimit = 3_000_000 ## about 70 MB

type
  Worked* = object
    activities*, sectors*, efforts*: int

  Box = tuple[lon0, lat0, lon1, lat1: float]

  Sectors = Table[int64, Path] ## the routes of the sectors read so far, by id

  Rides = object
    ## The rides read recently (the same rides are wanted again for each new sector near them),
    ## kept while they hold fewer than `ridePointLimit` points in all.
    paths: Table[int64, seq[Path]]
      ## a path for each stretch of the ride that has two positions
    points: int

func boxOf(p: Path): Box =
  result = (Inf, Inf, -Inf, -Inf)
  for i in 0 ..< p.len:
    result.lon0 = min(result.lon0, p.lon[i])
    result.lat0 = min(result.lat0, p.lat[i])
    result.lon1 = max(result.lon1, p.lon[i])
    result.lat1 = max(result.lat1, p.lat[i])

func wider(b: Box): Box =
  ## The box a little wider, for the spatial indexes to be asked with.
  (b.lon0 - margin, b.lat0 - margin, b.lon1 + margin, b.lat1 + margin)

func ridePaths(track: Track): seq[Path] =
  ## The positions and times of each stretch of a ride as a path (a stretch of fewer than two
  ## positions holds no line, so none is made).
  for coords in track:
    if coords.len < 2:
      continue
    var p: Path
    for c in coords:
      p.lon.add c.lon
      p.lat.add c.lat
      p.t.add float(int64(c.t))
    result.add p

func pointCount(ride: seq[Path]): int =
  for p in ride:
    result += p.len

func boxOf(ride: seq[Path]): Box =
  result = (Inf, Inf, -Inf, -Inf)
  for p in ride:
    let b = boxOf(p)
    result.lon0 = min(result.lon0, b.lon0)
    result.lat0 = min(result.lat0, b.lat0)
    result.lon1 = max(result.lon1, b.lon1)
    result.lat1 = max(result.lat1, b.lat1)

func overRide(sector: Path, ride: seq[Path]): seq[Effort] =
  ## The passes of a ride over a sector: those of each stretch (a pass lies within one).
  for p in ride:
    result.add overPaths(sector, p)

proc rideOf(
    st: Store, rides: var Rides, id: ActivityId
): seq[Path] {.raises: [StoreError].} =
  ## The stretches of an activity as paths, read once while it is wanted.
  let key = int64(id)
  if key in rides.paths:
    return rides.paths.getOrDefault(key)
  result = ridePaths(readTrack(st.db, id))
  if rides.points + result.pointCount > ridePointLimit:
    rides.paths.clear()
    rides.points = 0
  rides.paths[key] = result
  rides.points += result.pointCount

func climbPath(p: Profile, c: Climb): Path =
  ## The route of a climb: the samples of the profile from its start to its end.
  for i in c.first .. c.last:
    result.lon.add p.lon[i]
    result.lat.add p.lat[i]
    result.elev.add p.elev[i]

const
  sectorsInBoxSql* =
    "select id from sector where " & inBox("id", "sector", "route", cornerMarks)
  ridesInBoxSql* =
    "select activity_id from route where " &
    inBox("activity_id", "route", "geom", cornerMarks) &
    " and activity_id in (select activity_id from climbs_done) order by activity_id"

proc sectorsNear(
    st: Store, cache: var Sectors, box: Box
): seq[int64] {.raises: [StoreError].} =
  ## The ids of the sectors whose boxes meet the box; their routes are read into the cache.
  let w = wider(box)
  let ids = st.db.query(
    int64, sectorsInBoxSql, west = w.lon0, south = w.lat0, east = w.lon1, north = w.lat1
  )
  for id in ids:
    if id notin cache:
      let route = parseLineString(
        st.db.scalar(
          Option[string], "select AsText(route) from sector where id = :id", id = id
        )
      )
      if route.isNone:
        # (not an empty route: the rides would then be stored as having no efforts on it)
        raiseStore(
          "climb " & $id & " has a route that cannot be read (damaged data): " &
            "run `nch climbs --all --delete -f` and ask for the climbs again"
        )
      cache[id] = route.get
    result.add id

proc ridesNear(st: Store, box: Box): seq[ActivityId] {.raises: [StoreError].} =
  ## The activities already looked at whose routes meet the box.
  let w = wider(box)
  st.db.query(
    ActivityId,
    ridesInBoxSql,
    west = w.lon0,
    south = w.lat0,
    east = w.lon1,
    north = w.lat1,
  )

proc addEfforts(
    insert: Stmt, sector: int64, activity: ActivityId, efforts: seq[Effort]
): int {.raises: [StoreError].} =
  for e in efforts:
    insert.bindInt(1, sector)
    insert.bindInt(2, activity)
    insert.bindReal(3, e.startT)
    insert.bindReal(4, e.finishT)
    insert.bindReal(5, e.elapsed)
    insert.bindReal(6, e.startDist)
    insert.run()
    inc result

proc workOn(
    st: Store, id: ActivityId, cache: var Sectors, rides: var Rides, result: var Worked
) {.raises: [StoreError].} =
  ## One activity (inside a transaction made by the caller).
  let insertEffort = prepareStmt(
    st.db,
    "insert or ignore into effort(sector_id, activity_id, start_t, " &
      "finish_t, elapsed_s, start_m) values (?, ?, ?, ?, ?, ?)",
  )
  let insertSector = prepareStmt(
    st.db,
    "insert into sector(length_m, gain_m, gradient, category, " &
      "found_at, route) values (?, ?, ?, ?, ?, GeomFromText(?, 4326))",
  )
  let track = readTrack(st.db, id)
  let ride = ridePaths(track)
  if ride.len > 0:
    let rideBox = boxOf(ride)
    if rides.points + ride.pointCount > ridePointLimit:
      rides.paths.clear()
      rides.points = 0
    rides.paths[int64(id)] = ride
    rides.points += ride.pointCount
    # 1. the sectors that exist
    var matched: seq[int64] # the sectors this ride earned an effort on
    for sector in st.sectorsNear(cache, rideBox):
      timed "climbs: match a ride to a sector":
        let n = insertEffort.addEfforts(sector, id, overRide(cache.must(sector), ride))
        result.efforts += n
        if n > 0:
          matched.add sector
    # 2. its climbs, in each stretch of riding (a climb does not cross a break)
    let foundAt =
      st.db.scalar(int64, "select start_t from activity where id = :id", id = id)
    for coords in track:
      if coords.len < 2:
        continue
      var prof: Profile
      var climbs: seq[Climb]
      timed "climbs: profile and detect":
        prof = buildProfile(coords)
        climbs = findClimbs(prof)
      for climb in climbs:
        let route = climbPath(prof, climb)
        # the same climb again only if the ride went over that sector: a climb that overlaps a stored one but stops
        # short of its finish (or starts after its start) earned no effort on it, and is a climb of its own
        if st.isRepeat(route, matched):
          continue
        insertSector.bindReal(1, climb.length)
        insertSector.bindReal(2, climb.gain)
        insertSector.bindReal(3, climb.gradient)
        insertSector.bindOptText(4, climb.category)
        insertSector.bindInt(5, foundAt)
        insertSector.bindText(6, lineStringText(route))
        insertSector.run()
        let sector = lastInsertId(st.db)
        assignNumber(st, sector)
        cache[sector] = route
        inc result.sectors
        # 3. the new sector against the ride it came from, and the earlier rides near it
        let own = insertEffort.addEfforts(sector, id, overRide(route, ride))
        result.efforts += own
        if own > 0:
          matched.add sector
          # (so that a later lap over the same climb is this sector again)
        for other in st.ridesNear(boxOf(route)):
          if other != id:
            let otherRide = st.rideOf(rides, other)
            timed "climbs: match a new sector to an earlier ride":
              result.efforts +=
                insertEffort.addEfforts(sector, other, overRide(route, otherRide))
  st.db.execute(
    "insert into climbs_done(activity_id, version) values (:activityId, :version)",
    activityId = id,
    version = algorithmVersion,
  )

proc ensureClimbs*(
    st: Store,
    progress: proc(done, total: int, soFar: Worked) {.closure, raises: [].} = nil,
): Worked {.raises: [StoreError].} =
  ## Look at the activities that have not been looked at, and bring the sectors and efforts up to
  ## date.  An error if some were looked at by another version of the method.
  if st.db.scalar(
    int,
    "select count(*) from climbs_done where version != :version",
    version = algorithmVersion,
  ) != 0:
    raiseStore(
      "the climbs were worked out by another version of the method: " &
        "run `nch climbs --all --delete -f` and ask for them again"
    )
  let todo = st.db.query(
    ActivityId,
    "select a.id from activity a left join climbs_done d on d.activity_id = a.id " &
      "where d.activity_id is null order by a.start_t, a.id",
  )
  var cache: Sectors
  var rides: Rides
  for k, id in todo:
    st.begin()
    var done = false
    try:
      workOn(st, id, cache, rides, result)
      st.commit()
      done = true
    finally:
      if not done:
        st.rollback()
    inc result.activities
    if progress != nil:
      progress(k + 1, todo.len, result)

type Counts* = object
  sectors*, efforts*: int
  manual*: int ## of the sectors, those with a name given by hand

func describe*(c: Counts): string =
  ## "43 sectors and 220 efforts (of every user)", and what would be lost that cannot be made again:
  ## "43 sectors and 220 efforts (of every user); 2 names given by hand are lost".
  result =
    $c.sectors & (if c.sectors == 1: " sector" else: " sectors") & " and " & $c.efforts &
    (if c.efforts == 1: " effort" else: " efforts") & " (of every user)"
  if c.manual > 0:
    result.add "; " & $c.manual & (
      if c.manual == 1: " name given by hand is lost"
      else: " names given by hand are lost"
    )

proc countClimbs*(st: Store): Counts {.raises: [StoreError].} =
  ## How many sectors and efforts there are.
  result.sectors = st.db.scalar(int, "select count(*) from sector")
  result.efforts = st.db.scalar(int, "select count(*) from effort")
  result.manual = st.db.scalar(int, "select count(*) from sector where manual = 1")

proc clearClimbs*(st: Store) {.raises: [StoreError].} =
  ## Delete every sector, with the efforts on them (of every user), and the record of what was
  ## looked at: the next `ensureClimbs` starts again.
  st.begin()
  var done = false
  try:
    st.db.execute("delete from climbs_done")
    st.db.execute("delete from sector")
    st.commit()
    done = true
  finally:
    if not done:
      st.rollback()
