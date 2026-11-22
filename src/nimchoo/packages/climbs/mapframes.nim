## The frames of the climbs on a map (`map/frames`).  For the activities: the climbs the selected activities went up, the two
## gates of each (the lines a ride has to cross), and the part of each ride that is an effort on a climb; `climbs` supports that
## subject, it does not manage it (the selection is the activities'), and a note says when some activities have no climbs worked
## out (the import and `nch climbs` do that).  For the climbs, the subject it manages: the climbs of the climbs selection, their
## gates, and the routes of your rides that went up them (drawn as the activities' routes are).  The frames only read.  The
## style of each is shipped here, next to the frame.

import std/[options, sequtils, strformat, tables]
import ../../core/[errors, extension, ids]
import ../bundle/unpack
import ../db/statement
import ../importer/[coord, track]
import ../map/[frames, geojson]
import ../activities/[mapfeatures as activityFeatures, mapframes as activityFrames]
import ../selection/selection
import ../user/session
import ./[attempts, chosen, mapfeatures, match, report]
import ../ui/units

{.push raises: [].}

proc climbsOf(st: Session, sectors: seq[int64]): seq[Climb] {.raises: [StoreError].} =
  ## The climbs, in the order given.
  if sectors.len == 0:
    return
  let names = shownNames(st)
  for id in sectors:
    for r in st.db.query(
      tuple[lengthM, gainM, gradient: float, category: Option[string], geometry: string],
      """select length_m, gain_m, gradient, category, AsGeoJSON(route, 5)
          from sector where id = :id""",
      id = id,
    ):
      result.add Climb(
        id: id,
        name: names.getOrDefault(id, "unnamed"),
        category: r.category,
        lengthM: r.lengthM,
        gainM: r.gainM,
        gradient: r.gradient,
        geometry: r.geometry,
      )

proc gatesOf(st: Session, sectors: seq[int64]): seq[GateLine] {.raises: [StoreError].} =
  ## The two gates of each of the climbs (the lines `overPaths` counts a pass across).
  if sectors.len == 0:
    return
  let names = shownNames(st)
  for id in sectors:
    let route = parseLineString(
      st.db.scalar(
        Option[string], "select AsText(route) from sector where id = :id", id = id
      )
    )
    if route.isNone:
      raiseStore(
        fmt"climb {id} has a route that cannot be read (damaged data): " &
          "run `nch climbs --all --delete` and ask for the climbs again"
      )
    let g = gateLines(route.get)
    if g.isSome:
      let name = names.getOrDefault(id, "unnamed")
      result.add GateLine(climbId: id, name: name, start: true, ends: g.get.start)
      result.add GateLine(climbId: id, name: name, start: false, ends: g.get.finish)

func effortPath*(
    positions: seq[Coord], startT, finishT: float
): seq[tuple[lon, lat: float]] =
  ## The line of an effort: a point at exactly the start time and one at the finish time (where the gates were crossed),
  ## each between the two positions either side of it, and the positions in between.  A time outside the positions is
  ## taken at the first or last one (never beyond the ride).  Positions are in time order.
  if positions.len == 0:
    return
  func at(t: float): tuple[lon, lat: float] =
    if t <= float(positions[0].t):
      return (positions[0].lon, positions[0].lat)
    for k in 1 .. positions.high:
      let (a, b) = (positions[k - 1], positions[k])
      if t <= float(b.t):
        let f = (t - float(a.t)) / (float(b.t) - float(a.t))
        return (a.lon + (b.lon - a.lon) * f, a.lat + (b.lat - a.lat) * f)
    (positions[^1].lon, positions[^1].lat)

  result.add at(startT)
  for c in positions:
    if float(c.t) > startT and float(c.t) < finishT:
      result.add (c.lon, c.lat)
  result.add at(finishT)

proc effortsOf(st: Session, ids: seq[int64]): seq[EffortLine] {.raises: [StoreError].} =
  ## The part of each ride that is a stored effort on a climb: from where it crossed the start gate to where it crossed the
  ## finish gate (`effortPath`).  The efforts come by activity, so each ride's positions are read once.
  let names = shownNames(st)
  var positions: seq[Coord]
  var readFor = -1'i64
  for e in st.db.query(
    tuple[sectorId, activityId: int64, startT, finishT, elapsedS, startM: float],
    """select sector_id, activity_id, start_t, finish_t, elapsed_s, start_m from effort
        where activity_id in (select value from json_each(:ids)) order by activity_id, start_t, sector_id""",
    ids = jsonList(ids),
  ):
    var line = EffortLine(
      activityId: ActivityId(e.activityId),
      climbId: e.sectorId,
      name: names.getOrDefault(e.sectorId, "unnamed"),
      startT: e.startT,
      finishT: e.finishT,
      elapsedS: e.elapsedS,
      startM: e.startM,
    )
    if e.activityId != readFor:
      positions = readPositions(st.db, ActivityId(e.activityId))
      readFor = e.activityId
    line.points = effortPath(positions, e.startT, e.finishT)
    result.add line

proc unworked(st: Session, ids: seq[int64]): seq[string] {.raises: [StoreError].} =
  ## A note when some of the activities have no climbs worked out: a frame only reads them, the import and `nch climbs` work
  ## them out.
  let n = st.db.scalar(
    int,
    """select count(*) from activity where id in (select value from json_each(:ids))
        and id not in (select activity_id from climbs_done)""",
    ids = jsonList(ids),
  )
  if n > 0:
    let noun = if n == 1: "activity has" else: "activities have"
    result.add fmt"{count(n)} {noun} no climbs worked out (run `nch climbs` to work them out)"

proc makeClimbs(st: Session): FrameData {.raises: [StoreError].} =
  let ids = selectedIds(st)
  result.warnings = unworked(st, ids)
  result.geojson =
    featureCollection(climbsOf(st, climbsOfActivities(st, ids)).mapIt(climbFeature(it)))

proc makeGates(st: Session): FrameData {.raises: [StoreError].} =
  let ids = selectedIds(st)
  result.warnings = unworked(st, ids)
  result.geojson =
    featureCollection(gatesOf(st, climbsOfActivities(st, ids)).mapIt(gateFeature(it)))

# --- the climbs subject: the climbs selection

proc makeChosenClimbs(st: Session): FrameData {.raises: [StoreError].} =
  result.geojson =
    featureCollection(climbsOf(st, chosenClimbs(st)).mapIt(climbFeature(it)))

proc makeChosenGates(st: Session): FrameData {.raises: [StoreError].} =
  result.geojson =
    featureCollection(gatesOf(st, chosenClimbs(st)).mapIt(gateFeature(it)))

proc ridesUp*(st: Session, sectors: seq[int64]): seq[int64] {.raises: [StoreError].} =
  ## The user's activities that have an effort on any of the climbs, oldest first.
  st.db.query(
    int64,
    """select a.id from activity a join file f on f.id = a.file_id
        where f.user_id = :userId and exists (select 1 from effort e
          where e.activity_id = a.id and e.sector_id in (select value from json_each(:sectors)))
        order by a.start_t, a.id""",
    userId = st.userId,
    sectors = jsonList(sectors),
  )

proc makeChosenRoutes(st: Session): FrameData {.raises: [StoreError].} =
  let rides = ridesUp(st, chosenClimbs(st))
  let routes = routesOf(st, rides)
  if rides.len == 0:
    result.warnings.add "you have ridden none of the selected climbs"
  result.geojson = featureCollection(routes.mapIt(routeFeature(it)))

proc makeEfforts(st: Session): FrameData {.raises: [StoreError].} =
  let ids = selectedIds(st)
  result.warnings = unworked(st, ids)
  result.geojson = featureCollection(effortsOf(st, ids).mapIt(effortFeature(it)))

const
  climbTables = @["activity", "climbs_done", "effort", "sector", "selection", "track"]
    ## what the three frames of the activities read (they work nothing out)
  chosenTables =
    @["climb_selection", "sector"] ## what the climbs subject's climbs and gates read
  climbsStyle = Bundle(
    name: "templates/activities-map-climbs.json", data: staticRead("map-climbs.json")
  )
  gatesStyle = Bundle(
    name: "templates/activities-map-gates.json", data: staticRead("map-gates.json")
  )
  effortsStyle = Bundle(
    name: "templates/activities-map-efforts.json", data: staticRead("map-efforts.json")
  )
  climbsScript = Bundle(
    name: "templates/activities-map-climbs.js", data: staticRead("map-climbs.js")
  )
  gatesScript =
    Bundle(name: "templates/activities-map-gates.js", data: staticRead("map-gates.js"))
  effortsScript = Bundle(
    name: "templates/activities-map-efforts.js", data: staticRead("map-efforts.js")
  )

proc contributions*(): seq[Contribution] =
  ## The frames of the climbs, offered to the map for the activities.
  @[
    contribute(
      mapFramePoint,
      MapFrame(
        subject: "activities",
        name: "climbs",
        summary: "the climbs the activities went up",
        shown: true,
        readsSelection: true,
        tables: climbTables,
        make: makeClimbs,
        style: climbsStyle,
        styleKeys: @["color", "opacity", "width_m", "gap_m", "lane_m"],
        script: some(climbsScript),
      ),
    ),
    contribute(
      mapFramePoint,
      MapFrame(
        subject: "activities",
        name: "gates",
        summary:
          "the start and finish line of each of those climbs (for looking at how climbs are matched)",
        shown: false,
        readsSelection: true,
        tables: climbTables,
        make: makeGates,
        style: gatesStyle,
        styleKeys: @["start", "finish", "weight", "opacity"],
        script: some(gatesScript),
      ),
    ),
    contribute(
      mapFramePoint,
      MapFrame(
        subject: "activities",
        name: "efforts",
        summary:
          "the part of each ride between the start and finish times of its efforts on those climbs (for looking at how climbs are matched, with a few activities)",
        shown: false,
        readsSelection: true,
        tables: climbTables,
        make: makeEfforts,
        style: effortsStyle,
        styleKeys: @["color", "weight", "opacity", "start", "finish", "radius"],
        script: some(effortsScript),
      ),
    ),
    # (the routes first: the climbs are drawn beside their threads, from the spread the routes' drawing says)
    contribute(
      mapFramePoint,
      MapFrame(
        subject: "climbs",
        name: "routes",
        summary: "the routes of your rides that went up them",
        shown: false,
        readsSelection: true,
        tables: @["activity", "climb_selection", "effort", "file", "route", "sector"],
        make: makeChosenRoutes,
        style: routesStyle,
        styleKeys: routesStyleKeys,
        script: some(routesScript),
      ),
    ),
    contribute(
      mapFramePoint,
      MapFrame(
        subject: "climbs",
        name: "climbs",
        summary: "the climbs of the selection",
        shown: true,
        readsSelection: true,
        tables: chosenTables,
        make: makeChosenClimbs,
        style: climbsStyle,
        styleKeys: @["color", "opacity", "width_m", "gap_m", "lane_m"],
        script: some(climbsScript),
      ),
    ),
    contribute(
      mapFramePoint,
      MapFrame(
        subject: "climbs",
        name: "gates",
        summary: "the start and finish line of each of them",
        shown: false,
        readsSelection: true,
        tables: chosenTables,
        make: makeChosenGates,
        style: gatesStyle,
        styleKeys: @["start", "finish", "weight", "opacity"],
        script: some(gatesScript),
      ),
    ),
  ]
