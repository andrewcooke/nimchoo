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
## Each activity is one transaction, and is then recorded in `climbs_done` (also when nothing was
## found), with the version of the method.  If the method changes the version does, and
## `clearClimbs` (`nch climbs --all --delete`) starts again.

import std/[math, options, strutils, tables]
import db_connector/db_sqlite
import ../db/[statement, store]
import ../errors
import ../fit/time
import ../ids
import ../importer/extract
import ../lookup
import ../profiling
import ./[detect, match, ordinal, profile]

{.push raises: [].}

const
  algorithmVersion* = 3
    ## 3: the profile every 5 m and not smoothed.  2: a climb that is a repeat of a stored one but earned the ride no effort on it is a sector of its own
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
    paths: Table[int64, Path]
    points: int

func boxOf(p: Path): Box =
  result = (Inf, Inf, -Inf, -Inf)
  for i in 0 ..< p.len:
    result.lon0 = min(result.lon0, p.lon[i])
    result.lat0 = min(result.lat0, p.lat[i])
    result.lon1 = max(result.lon1, p.lon[i])
    result.lat1 = max(result.lat1, p.lat[i])

func degrees(x: float): string =
  formatFloat(x, ffDecimal, 7)

func frame(b: Box): string =
  ## The box, a little wider, as the SpatiaLite function that the spatial indexes are asked with.
  "BuildMbr(" & degrees(b.lon0 - margin) & ", " & degrees(b.lat0 - margin) & ", " &
    degrees(b.lon1 + margin) & ", " & degrees(b.lat1 + margin) & ")"

func parseLineString(text: string): Path =
  ## The positions of "LINESTRING Z(lon lat alt, ...)".
  let a = text.find('(')
  let b = text.rfind(')')
  if a < 0 or b <= a:
    return
  try:
    for part in text[a + 1 ..< b].split(','):
      let f = part.splitWhitespace
      if f.len < 2:
        return Path()
      result.lon.add parseFloat(f[0])
      result.lat.add parseFloat(f[1])
  except ValueError:
    result = Path()

func lineStringText(p: Path): string =
  ## "LINESTRING Z(lon lat alt, ...)" for a route that has altitudes.
  var points: seq[string]
  for i in 0 ..< p.len:
    points.add degrees(p.lon[i]) & " " & degrees(p.lat[i]) & " " &
      formatFloat(p.elev[i], ffDecimal, 1)
  "LINESTRING Z(" & points.join(", ") & ")"

proc readCoords(st: Store, id: ActivityId): seq[Coord] {.raises: [StoreError].} =
  timed "climbs: read coords":
    guard:
      for r in st.db.fastRows(
        sql"select t, lon, lat, alt from coords where activity_id = ? order by t", id
      ):
        try:
          result.add Coord(
            t: UnixTime(parseBiggestInt(r[0])),
            lon: parseFloat(r[1]),
            lat: parseFloat(r[2]),
            alt:
              if r[3].len > 0:
                some(parseFloat(r[3]))
              else:
                none(float),
          )
        except ValueError:
          raiseStore("a bad coordinate in the database")

func ridePath(coords: openArray[Coord]): Path =
  for c in coords:
    result.lon.add c.lon
    result.lat.add c.lat
    result.t.add float(int64(c.t))

proc rideOf(
    st: Store, rides: var Rides, id: ActivityId
): Path {.raises: [StoreError].} =
  ## The positions and times of an activity, read once while it is wanted.
  let key = int64(id)
  if key in rides.paths:
    return rides.paths.getOrDefault(key)
  result = ridePath(st.readCoords(id))
  if rides.points + result.len > ridePointLimit:
    rides.paths.clear()
    rides.points = 0
  rides.paths[key] = result
  rides.points += result.len

func climbPath(p: Profile, c: Climb): Path =
  ## The route of a climb: the samples of the profile from its start to its end.
  for i in c.first .. c.last:
    result.lon.add p.lon[i]
    result.lat.add p.lat[i]
    result.elev.add p.elev[i]

proc sectorsNear(
    st: Store, cache: var Sectors, box: Box
): seq[int64] {.raises: [StoreError].} =
  ## The ids of the sectors whose boxes meet the box; their routes are read into the cache.
  var ids: seq[int64]
  guard:
    for r in st.db.fastRows(
      sql(
        "select id from sector where id in (select ROWID from SpatialIndex " &
          "where f_table_name = 'sector' and f_geometry_column = 'route' and search_frame = " &
          frame(box) & ")"
      )
    ):
      try:
        ids.add parseBiggestInt(r[0])
      except ValueError:
        raiseStore("a bad sector id")
  for id in ids:
    if id notin cache:
      guard:
        cache[id] = parseLineString(
          st.db.getValue(sql"select AsText(route) from sector where id = ?", id)
        )
    result.add id

proc ridesNear(st: Store, box: Box): seq[ActivityId] {.raises: [StoreError].} =
  ## The activities already looked at whose routes meet the box.
  guard:
    for r in st.db.fastRows(
      sql(
        "select activity_id from route where activity_id in " &
          "(select ROWID from SpatialIndex where f_table_name = 'route' and f_geometry_column = 'geom' " &
          "and search_frame = " & frame(box) &
          ") and activity_id in (select activity_id from climbs_done) " &
          "order by activity_id"
      )
    ):
      try:
        result.add ActivityId(parseBiggestInt(r[0]))
      except ValueError:
        raiseStore("a bad activity id")

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
  let coords = st.readCoords(id)
  if coords.len >= 2:
    let ride = ridePath(coords)
    let rideBox = boxOf(ride)
    if rides.points + ride.len > ridePointLimit:
      rides.paths.clear()
      rides.points = 0
    rides.paths[int64(id)] = ride
    rides.points += ride.len
    # 1. the sectors that exist
    var matched: seq[int64] # the sectors this ride earned an effort on
    for sector in st.sectorsNear(cache, rideBox):
      timed "climbs: match a ride to a sector":
        let n = insertEffort.addEfforts(sector, id, overPaths(cache.must(sector), ride))
        result.efforts += n
        if n > 0:
          matched.add sector
    # 2. its climbs
    var foundAt = 0'i64
    guard:
      try:
        foundAt = parseBiggestInt(
          st.db.getValue(sql"select start_t from activity where id = ?", id)
        )
      except ValueError:
        raiseStore("a bad start time in the database")
    var prof: Profile
    var climbs: seq[Climb]
    timed "climbs: profile and detect":
      prof = buildProfile(coords)
      climbs = findClimbs(prof)
    for climb in climbs:
      let route = climbPath(prof, climb)
      var again = false
      for sector in st.sectorsNear(cache, boxOf(route)):
        # the same climb again only if the ride went over that sector: a climb that overlaps a stored one but stops
        # short of its finish (or starts after its start) earned no effort on it, and is a climb of its own
        if sector in matched and isRepeat(cache.must(sector), route):
          again = true
          break
      if again:
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
      let own = insertEffort.addEfforts(sector, id, overPaths(route, ride))
      result.efforts += own
      if own > 0:
        matched.add sector
        # (so that a later lap over the same climb is this sector again)
      for other in st.ridesNear(boxOf(route)):
        if other != id:
          let otherRide = st.rideOf(rides, other)
          timed "climbs: match a new sector to an earlier ride":
            result.efforts +=
              insertEffort.addEfforts(sector, other, overPaths(route, otherRide))
  guard:
    st.db.exec(
      sql"insert into climbs_done(activity_id, version) values (?, ?)",
      id,
      algorithmVersion,
    )

proc ensureClimbs*(
    st: Store,
    progress: proc(done, total: int, soFar: Worked) {.closure, raises: [].} = nil,
): Worked {.raises: [StoreError].} =
  ## Look at the activities that have not been looked at, and bring the sectors and efforts up to
  ## date.  An error if some were looked at by another version of the method.
  guard:
    if st.db.getValue(
      sql"select count(*) from climbs_done where version != ?", algorithmVersion
    ) != "0":
      raiseStore(
        "the climbs were worked out by another version of the method: " &
          "run `nch climbs --all --delete -f` and ask for them again"
      )
  var todo: seq[ActivityId]
  guard:
    for r in st.db.fastRows(
      sql"""select a.id from activity a left join climbs_done d on d.activity_id = a.id
                                  where d.activity_id is null order by a.start_t, a.id"""
    ):
      try:
        todo.add ActivityId(parseBiggestInt(r[0]))
      except ValueError:
        raiseStore("a bad activity id")
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
  guard:
    try:
      result.sectors = parseInt(st.db.getValue(sql"select count(*) from sector"))
      result.efforts = parseInt(st.db.getValue(sql"select count(*) from effort"))
      result.manual =
        parseInt(st.db.getValue(sql"select count(*) from sector where manual = 1"))
    except ValueError:
      raiseStore("a bad count")

proc clearClimbs*(st: Store) {.raises: [StoreError].} =
  ## Delete every sector, with the efforts on them (of every user), and the record of what was
  ## looked at: the next `ensureClimbs` starts again.
  st.begin()
  var done = false
  try:
    guard:
      st.db.exec(sql"delete from climbs_done")
      st.db.exec(sql"delete from sector")
    st.commit()
    done = true
  finally:
    if not done:
      st.rollback()
