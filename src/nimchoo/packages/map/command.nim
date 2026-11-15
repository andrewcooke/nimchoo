## `nch map`: the routes of the selected activities, and the climbs they went up, on a map.  A GeoJSON file in the cache
## directory holds them (every feature says what it is, in `kind`, and nothing about how it looks), and a page, drawn by
## Leaflet in the browser, decides the look.
##
## A map is a live view: it shows the selection as it is when the map is made, and is made again for every request.  The files
## are named by the command and the layers (`map-routes-climbs.geojson`); a bookmark of the page keeps the layers, not the data.
##
## This module is newer than `importer`, `selection` and `climbs`: it reads their tables and uses their libraries.

import std/[math, options, os, strutils, tables]
import ../cache/cache
import ../util/atomic/atomic
import ../../core/globals
import ../climbs/attempts
import ../climbs/match
import ../climbs/report
import ../climbs/work
import ../db/statement
import ../db/store
import ../../core/errors
import ../importer/track
import ../fit/time
import ../geo/cells
import ../../core/ids
import ../selection/selection
import ../ui/live
import ../util/args/[args, usage]
import ../web/launch
import ../web/pages
import ../web/webopts
import ./[lines, page, params]
import ../user/session

{.push raises: [].}

const commandName* = "map" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch map`, described (for tab completion).
  mapSpec().docs

const
  synopsis =
    "usage: nch [--db PATH] [--user NAME] map [--layers LIST] [--file | [--no-open] [--port N] [--new-token]]"
  intro =
    """Show the selected activities (see `nch activities --select`) on a map: by default their routes and the climbs they
went up, drawn over them; --layers chooses what is drawn, and `heat` shows how often each place was visited, in cells
(about 100 m, coarser as you zoom out).  It serves a page that draws them on localhost and opens it in a browser (Ctrl-C
stops it); with --file it makes a GeoJSON file in the cache directory instead and prints its path.  Several rides over the
same roads show as a glow; a click on a route says which activity it is, a click on a climb says what it is, a click on a
cell says how often it was visited.  The climbs not yet worked out (an import does that) are worked out first."""
  notes =
    """The map is made again each time the page is loaded, from the selection as it is then: a bookmark of the address keeps
which layers are drawn, not which activities."""

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" & prose(notes, width) & "\n\n" &
    optionLines(mapSpec().docs, width).join("\n") & "\n"

const
  toleranceM = 5.0 ## routes are simplified so that they stray at most this far
  metresPerDegree = 111320.0

proc routesOf(st: Store, ids: seq[int64]): seq[Route] {.raises: [StoreError].} =
  ## The routes of the activities, oldest first.
  if ids.len == 0:
    return
  for r in st.db.query(
    tuple[
      id: ActivityId,
      startT: int64,
      sport: string,
      distanceM: Option[float],
      geometry: string,
    ],
    "select a.id, a.start_t, coalesce(a.sport, ''), a.distance_m, " &
      "AsGeoJSON(SimplifyPreserveTopology(r.geom, :tolerance), 5) " &
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

const heatLevels* = [0, 3, 6]
  ## the levels of cells the heat is given at, finest first: cells of about 100 m, 870 m and 7 km (the page shows the one that
  ## suits its zoom)

proc heatOf(st: Store, ids: seq[int64]): seq[HeatCell] {.raises: [StoreError].} =
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

proc climbsOf(st: Store, ids: seq[int64]): seq[Climb] {.raises: [StoreError].} =
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

proc gatesOf(st: Store, ids: seq[int64]): seq[GateLine] {.raises: [StoreError].} =
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
        "climb " & $id & " has a route that cannot be read (damaged data): " &
          "run `nch climbs --all --delete -f` and ask for the climbs again"
      )
    let g = gateLines(route.get)
    if g.isSome:
      let name = names.getOrDefault(id, "unnamed")
      result.add GateLine(climbId: id, name: name, start: true, ends: g.get.start)
      result.add GateLine(climbId: id, name: name, start: false, ends: g.get.finish)

proc effortsOf(st: Store, ids: seq[int64]): seq[EffortLine] {.raises: [StoreError].} =
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

type Prepared = object
  status: int ## 0 if the files are there; else the exit status (already reported)
  geojson, page: string ## paths (page: only if asked for)

proc stemOf(layers: set[Layer]): string =
  ## What the files are named: the command and the layers, in the order of the layers (`map-routes-climbs`).
  "map-" & layersText(layers).replace(',', '-')

proc routeCount(st: Store, ids: seq[int64]): int {.raises: [StoreError].} =
  ## How many of the activities have a route.
  st.db.scalar(
    int,
    "select count(*) from route where activity_id in (select value from json_each(:ids))",
    ids = jsonList(ids),
  )

proc prepare(g: Globals, p: Params, dir: string, withPage: bool): Prepared =
  ## Make the GeoJSON file of the selection as it is now (and, if asked, the page), whatever was there.  Reports problems.
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return Prepared(status: failure("nch map", e.msg))
  try:
    let ids = selectedIds(st)
    if ids.len == 0:
      return Prepared(
        status:
          failure("nch map", "the selection is empty (see `nch activities --select`)")
      )
    if routeCount(st, ids) == 0:
      return Prepared(
        status: failure(
          "nch map",
          "none of the " & $ids.len &
            " activities has a route (no positions in the files)",
        )
      )
    # the climbs are worked out first if they are not (for the layers that have them)
    if p.layers * {lyClimbs, lyGates, lyEfforts} != {}:
      let worked = ensureClimbs(st)
      if worked.activities > 0:
        stderr.say "worked out the climbs of " & $worked.activities & " activities: " &
          $worked.sectors & " new climbs\n"
    let routes =
      if lyRoutes in p.layers:
        routesOf(st, ids)
      else:
        @[]
    if lyRoutes in p.layers and routes.len < ids.len:
      stderr.say "note: " & $(ids.len - routes.len) & " of the " & $ids.len &
        " activities have no route (no positions in the files)\n"
    let heat =
      if lyHeat in p.layers:
        heatOf(st, ids)
      else:
        @[]
    if lyHeat in p.layers and lyRoutes notin p.layers and heat.len == 0:
      return Prepared(
        status: failure(
          "nch map",
          "none of the " & $ids.len &
            " activities has been through a cell (no positions in the files)",
        )
      )
    let climbs =
      if lyClimbs in p.layers:
        climbsOf(st, ids)
      else:
        @[]
    let gates =
      if lyGates in p.layers:
        gatesOf(st, ids)
      else:
        @[]
    let efforts =
      if lyEfforts in p.layers:
        effortsOf(st, ids)
      else:
        @[]
    let stem = stemOf(p.layers)
    let path = cacheFile(dir, stem, "geojson").get
    writeAtomic(path, featureCollection(routes, climbs, heat, efforts, gates))
    result = Prepared(geojson: path)
    if withPage:
      let pagePath = cacheFile(dir, stem, "html").get
      let html = pageHtml(extractFilename(path), "Map")
      if html.isNone:
        return Prepared(status: failure("nch map", "cannot make a page for " & path))
      writeAtomic(pagePath, html.get)
      result.page = pagePath
  except StoreError as e:
    result = Prepared(status: failure("nch map", e.msg))
  except IOError, OSError:
    result = Prepared(
      status:
        failure("nch map", "cannot write to " & dir & ": " & getCurrentExceptionMsg())
    )
  except TemplateError as e:
    result = Prepared(
      status: failure(
        "nch map",
        "cannot make the page: " & e.msg &
          " (the template is system/templates/map.html and the libraries are system/libraries.txt, " &
          "in the cache directory; delete one to have the built-in one again)",
      )
    )

proc checkSelection(g: Globals): int =
  ## Before serving: the selection is not empty (the page makes its files itself, whenever it is asked for).
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure("nch map", e.msg)
  try:
    if selectedIds(st).len == 0:
      return
        failure("nch map", "the selection is empty (see `nch activities --select`)")
    exitOk
  except StoreError as e:
    failure("nch map", e.msg)
  finally:
    st.close()

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch map ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch map", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  let dir = cacheDir()
  if dir.isNone:
    return failure("nch map", "no place for the cache: set NCH_CACHE or HOME")
  try:
    makeCacheDirs(dir.get)
  except IOError, OSError:
    return
      failure("nch map", "cannot make " & dir.get & ": " & getCurrentExceptionMsg())
  case p.web.kind
  of wkServe:
    let checked = checkSelection(g)
    if checked != exitOk:
      return checked
    # the address keeps the look (the layers); the data are those of the selection when the page is asked for
    return serveWeb(
      g,
      commandName,
      WebOptions(port: p.web.port, noOpen: p.web.noOpen, newToken: p.web.newToken),
      dir.get,
      "layers=" & layersText(p.layers),
    )
  of wkWorker:
    let made = prepare(g, p, userDir(dir.get), true)
    if made.status != 0:
      return made.status
    stdout.say made.page & "\n" & made.geojson & "\n"
  of wkFile:
    let made = prepare(g, p, userDir(dir.get), false)
    if made.status != 0:
      return made.status
    stdout.say made.geojson & "\n"
  exitOk
