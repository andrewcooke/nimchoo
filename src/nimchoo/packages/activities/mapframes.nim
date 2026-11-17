## The frames of the activities on a map (`map/frames`): the routes of the selected activities, and how often each place was
## visited (the heat).  Each is a GeoJSON file made from the data as they are, for the activities of the user's selection; the
## style of each (a template the user can edit) is shipped here, next to the frame.

import std/[options, sequtils, strformat]
import ../../core/[errors, extension, ids]
import ../bundle/unpack
import ../db/statement
import ../fit/time
import ../geo/cells
import ../map/[frames, geojson]
import ../selection/selection
import ./mapfeatures
import ../user/session

{.push raises: [].}

const
  toleranceM = 5.0
    ## routes are simplified (Douglas-Peucker: `Simplify`, not `SimplifyPreserveTopology`, which is 12 times slower and a line does not need) so that they stray at most this far
  metresPerDegree = 111320.0
  heatLevels* = [0, 3, 6]
    ## the levels of cells the heat is given at, finest first: cells of about 100 m, 870 m and 7 km (the page shows the one that
    ## suits its zoom)

proc routesOf(st: Session, ids: seq[int64]): seq[Route] {.raises: [StoreError].} =
  ## The routes of the activities, oldest first.
  for r in st.db.query(
    tuple[
      id: ActivityId,
      startT: int64,
      sport: string,
      distanceM: Option[float],
      geometry: string,
    ],
    "select a.id, a.start_t, coalesce(a.sport, ''), a.distance_m, " &
      "AsGeoJSON(Simplify(r.geom, :tolerance), 5) " &
      "from activity a join route r on r.activity_id = a.id " &
      "where a.id in (select value from json_each(:ids)) order by a.start_t, a.id",
    tolerance = toleranceM / metresPerDegree,
    ids = jsonList(ids),
  ):
    result.add Route(
      id: r.id,
      startT: UnixTime(r.startT),
      sport: r.sport,
      distanceM: r.distanceM,
      geometry: r.geometry,
    )

proc heatOf(st: Session, ids: seq[int64]): seq[HeatCell] {.raises: [StoreError].} =
  ## How often the activities visited each cell, at each level of `heatLevels`.
  for bits in heatLevels:
    for r in st.db.query(
      tuple[cell: int64, visits, rides: int],
      """select cell_coarse(cell, :bits), count(*), count(distinct activity_id) from route_cell
          where activity_id in (select value from json_each(:ids)) group by 1 order by 1""",
      bits = bits,
      ids = jsonList(ids),
    ):
      result.add HeatCell(
        cell: Cell(r.cell), bits: bits, visits: r.visits, rides: r.rides
      )

proc makeRoutes(st: Session): FrameData {.raises: [StoreError].} =
  let ids = selectedIds(st)
  let routes = routesOf(st, ids)
  let n = ids.len
  if routes.len == 0:
    result.notes.add fmt"none of the {n} activities has a route (no positions in the files)"
  elif routes.len < n:
    let missing = n - routes.len
    let verb = if missing == 1: "has" else: "have"
    result.notes.add fmt"{missing} of the {n} selected activities {verb} no route (no positions in the files)"
  result.geojson = featureCollection(routes.mapIt(routeFeature(it)))

proc makeHeat(st: Session): FrameData {.raises: [StoreError].} =
  let ids = selectedIds(st)
  let heat = heatOf(st, ids)
  if heat.len == 0:
    result.notes.add fmt"none of the {ids.len} activities has been through a cell (no positions in the files)"
  result.geojson = featureCollection(heat.mapIt(heatFeature(it)))

const
  routesStyle = Bundle(
    name: "templates/activities-map-routes.json", data: staticRead("map-routes.json")
  )
  heatStyle = Bundle(
    name: "templates/activities-map-heat.json", data: staticRead("map-heat.json")
  )
  routesScript = Bundle(
    name: "templates/activities-map-routes.js", data: staticRead("map-routes.js")
  )
  heatScript =
    Bundle(name: "templates/activities-map-heat.js", data: staticRead("map-heat.js"))

proc contributions*(): seq[Contribution] =
  ## The frames of the activities, offered to the map.
  @[
    contribute(
      mapFramePoint,
      MapFrame(
        subject: "activities",
        name: "routes",
        summary:
          "the route of each activity (several over the same road show as a glow)",
        shown: true,
        readsSelection: true,
        tables: @["activity", "route", "selection"],
        make: makeRoutes,
        style: routesStyle,
        styleKeys: @["color", "weight", "opacity", "spread_m"],
        script: some(routesScript),
      ),
    ),
    contribute(
      mapFramePoint,
      MapFrame(
        subject: "activities",
        name: "heat",
        summary:
          "how often each place was visited, in cells of about 100 m, coarser when zoomed out",
        shown: false,
        readsSelection: true,
        tables: @["route_cell", "selection"],
        make: makeHeat,
        style: heatStyle,
        styleKeys: @["low", "high", "opacity_low", "opacity_high", "levels"],
        script: some(heatScript),
      ),
    ),
  ]
