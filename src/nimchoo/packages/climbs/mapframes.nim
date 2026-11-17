## The frames of the climbs on a map (`map/frames`), for the activities: the climbs the selected activities went up, the two gates
## of each (the lines a ride has to cross), and the part of each ride that is an effort on a climb.  `climbs` supports the
## subject here, it does not manage it: the selection is the activities'.  The frames only read: a note says when some activities have
## no climbs worked out (the import and `nch climbs` do that).  The style of each is shipped here, next to the frame.

import std/[math, options, sequtils, strformat, tables]
import ../../core/[errors, extension, ids]
import ../bundle/unpack
import ../db/statement
import ../importer/track
import ../map/[frames, geojson]
import ../selection/selection
import ../user/session
import ./[attempts, mapfeatures, match, report]

{.push raises: [].}

proc climbsOf(st: Session, ids: seq[int64]): seq[Climb] {.raises: [StoreError].} =
  ## The climbs the activities went up, the biggest first.
  let sectors = climbsOfActivities(st, ids)
  if sectors.len == 0:
    return
  let names = shownNames(st)
  for id in sectors:
    for r in st.db.query(
      tuple[lengthM, gainM, gradient: float, category, geometry: string],
      """select length_m, gain_m, gradient, coalesce(category, ''), AsGeoJSON(route, 5)
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

proc gatesOf(st: Session, ids: seq[int64]): seq[GateLine] {.raises: [StoreError].} =
  ## The two gates of each climb the activities went up (the lines `overPaths` counts a pass across).
  let sectors = climbsOfActivities(st, ids)
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
          "run `nch climbs --all --delete -f` and ask for the climbs again"
      )
    let g = gateLines(route.get)
    if g.isSome:
      let name = names.getOrDefault(id, "unnamed")
      result.add GateLine(climbId: id, name: name, start: true, ends: g.get.start)
      result.add GateLine(climbId: id, name: name, start: false, ends: g.get.finish)

proc effortsOf(st: Session, ids: seq[int64]): seq[EffortLine] {.raises: [StoreError].} =
  ## The part of each ride that is a stored effort on a climb: its positions from the start time to the finish time.
  let names = shownNames(st)
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
    let first = int64(floor(e.startT))
    let last = int64(ceil(e.finishT))
    for c in readPositions(st.db, ActivityId(e.activityId)):
      if int64(c.t) >= first and int64(c.t) <= last:
        line.points.add (lon: c.lon, lat: c.lat)
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
    result.add fmt"{n} {noun} no climbs worked out (run `nch climbs` to work them out)"

proc makeClimbs(st: Session): FrameData {.raises: [StoreError].} =
  let ids = selectedIds(st)
  result.notes = unworked(st, ids)
  result.geojson = featureCollection(climbsOf(st, ids).mapIt(climbFeature(it)))

proc makeGates(st: Session): FrameData {.raises: [StoreError].} =
  let ids = selectedIds(st)
  result.notes = unworked(st, ids)
  result.geojson = featureCollection(gatesOf(st, ids).mapIt(gateFeature(it)))

proc makeEfforts(st: Session): FrameData {.raises: [StoreError].} =
  let ids = selectedIds(st)
  result.notes = unworked(st, ids)
  result.geojson = featureCollection(effortsOf(st, ids).mapIt(effortFeature(it)))

const
  climbTables = @["activity", "climbs_done", "effort", "sector", "selection", "track"]
    ## what the three frames read (they work nothing out)
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
        styleKeys: @["color", "weight", "opacity", "gap_px", "lane_px"],
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
  ]
