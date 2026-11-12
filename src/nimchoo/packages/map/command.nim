## `nch map`: the routes of the selected activities, and the climbs they went up, on a map.  A GeoJSON file in the cache
## directory holds them (every feature says what it is, in `kind`, and nothing about how it looks), and a page, drawn by
## Leaflet in the browser (`--web`), decides the look.
##
## Which activities are drawn is carried by the address of the page: `selection=...` is the list of them
## (selection/bits.nim) and `state=...` a hash of everything the map is made from (the content of the activities, their routes
## and the climbs), so that an address made before the database was rebuilt, or before something it shows changed, is refused
## and not wrong.  The files are named by a hash of the whole address, in pronounceable words
## (`map-lusab-babad-fuzoh.geojson`).  An address with a state whose file is there is served as it is; if the file is gone
## it is made again, but only if the state is still the same.  An address without a state is made from the data as they are,
## and the address that names exactly that is what the command reports.
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
import ../importer/[keys, track]
import ../fit/time
import ../geo/cells
import ../../core/ids
import ../selection/bits
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
    "usage: nch [--db PATH] [--user NAME] map [--layers LIST] [--web [--no-open] [--port N] [--new-token]]"
  intro =
    """Show the selected activities (see `nch activities --select`) on a map: by default their routes and the climbs they
went up, drawn over them; --layers chooses what is drawn, and `heat` shows how often each place was visited, in cells
(about 100 m, coarser as you zoom out).  It makes a GeoJSON file in the cache directory and prints its path; with --web it
also serves a page that draws it, and opens it in a browser.  Several rides over the same roads show as a glow; a click on a
route says which activity it is, a click on a climb says what it is, a click on a cell says how often it was visited.  The climbs not yet worked out (an import does that) are
worked out first.  Asking again for the same thing finds the file already there."""
  notes =
    """The address of the page records which activities it shows, so a reload shows the same ones even if the selection
has since changed.  It stops working when the database is rebuilt (the numbers then mean other activities)."""

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
  stem, query: string
    ## the name of the files, and the address that names the map exactly
  geojson, page: string ## paths (page: only if asked for)

type Inputs = object
  state: string ## the key of everything the map is made from
  routes: int ## how many of the activities have a route
  climbs: seq[Climb]
  gates: seq[GateLine]
  efforts: seq[EffortLine]
  worked: Worked ## the climbs that had to be worked out first

proc inputsOf(
    st: Session, ids: seq[int64], layers: set[Layer]
): Inputs {.raises: [StoreError].} =
  ## What the map of the activities is made from, and the state that stands for it: the content of the activities (which the
  ## cells of the heat are a function of) and, for the layers that have them, their routes and the climbs (which are worked
  ## out first if they are not).  A layer that is not drawn is not an input: a change to the climbs does not touch a heat map.
  let routeKey = routesKey(st, ids)
  result.routes = routeKey.count
  var inputs = @[("activities", contentKey(st, ids))]
  if lyRoutes in layers:
    inputs.add ("routes", routeKey.key)
  if layers * {lyClimbs, lyGates, lyEfforts} != {}:
    result.worked = ensureClimbs(st)
  if lyClimbs in layers:
    result.climbs = climbsOf(st, ids)
    inputs.add ("climbs", climbsKey(result.climbs))
  if lyGates in layers:
    result.gates = gatesOf(st, ids)
    inputs.add ("gates", gatesKey(result.gates))
  if lyEfforts in layers:
    result.efforts = effortsOf(st, ids)
    inputs.add ("efforts", effortsKey(result.efforts))
  result.state = stateKey(inputs)

proc stateOf*(
    st: Session, ids: seq[int64], layers: set[Layer] = defaultLayers
): string {.raises: [StoreError].} =
  ## The state of the map of these activities (which must be the user's: `ownedIds`) with these layers, as an address
  ## carries it.
  inputsOf(st, ids, layers).state

proc prepare(g: Globals, p: Params, dir: string, withPage: bool): Prepared =
  ## Make the GeoJSON file (if it is not there) and, if asked, the page.  Reports problems.
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return Prepared(status: failure("nch map", e.msg))
  try:
    # the activities: those of the address, else the selection
    var ids: seq[int64]
    if p.target == tList:
      let d = decodeBits(p.selection, maxActivityId(st))
      if d.problem.len > 0:
        return Prepared(
          status: usageError("nch map", usageText(helpWidth(stderr)), d.problem)
        )
      ids = d.ids
    else:
      ids = selectedIds(st)
    let mine = ownedIds(st, ids)
    if mine.len == 0:
      return Prepared(
        status: failure(
          "nch map",
          if p.target == tSelection:
            "the selection is empty (see `nch activities --select`)"
          else:
            "none of the activities of this address exist",
        )
      )
    if mine.len < ids.len:
      stderr.say "note: " & $(ids.len - mine.len) & " of the " & $ids.len &
        " activities of this address do not exist\n"
    # (the request is the activities drawn, spelt one way: the address as typed may name others, or use the other form)
    let selection = encodeBits(mine)
    var request, stem, path: string
    var found = false
    proc name(state: string): bool =
      ## Whether the files of the map of these activities, with these layers, in this state can be named; sets them.
      request =
        "selection=" & selection & "&layers=" & layersText(p.layers) & "&state=" & state
      let s = requestStem("map", request)
      if s.isNone:
        return false
      stem = s.get
      path = cacheFile(dir, stem, "geojson").get
      true

    if p.target == tList and p.state.isSome:
      # a pinned address: if its file is there it is what was asked for, and nothing needs working out
      if not name(p.state.get):
        return Prepared(status: failure("nch map", "cannot name a file"))
      found = fileExists(path)
    if not found:
      let inputs = inputsOf(st, mine, p.layers)
      if inputs.worked.activities > 0:
        stderr.say "worked out the climbs of " & $inputs.worked.activities &
          " activities: " & $inputs.worked.sectors & " new climbs\n"
      if inputs.routes == 0:
        return Prepared(
          status: failure(
            "nch map",
            "none of the " & $mine.len &
              " activities has a route (no positions in the files)",
          )
        )
      if p.target == tList and p.state.isSome and p.state.get != inputs.state:
        return Prepared(
          status: failure(
            "nch map",
            "the data of this address have changed since it was made (the database was rebuilt, or activities, " &
              "routes or climbs changed), and its files are gone; the map of these activities as they are now is " &
              "/map?selection=" & selection & "&layers=" & layersText(p.layers),
          )
        )
      if not name(inputs.state):
        return Prepared(status: failure("nch map", "cannot name a file"))
      if not fileExists(path):
        let routes =
          if lyRoutes in p.layers:
            routesOf(st, mine)
          else:
            @[]
        if lyRoutes in p.layers and routes.len < mine.len:
          stderr.say "note: " & $(mine.len - routes.len) & " of the " & $mine.len &
            " activities have no route (no positions in the files)\n"
        let heat =
          if lyHeat in p.layers:
            heatOf(st, mine)
          else:
            @[]
        if lyHeat in p.layers and lyRoutes notin p.layers and heat.len == 0:
          return Prepared(
            status: failure(
              "nch map",
              "none of the " & $mine.len &
                " activities has been through a cell (no positions in the files)",
            )
          )
        writeAtomic(
          path,
          featureCollection(routes, inputs.climbs, heat, inputs.efforts, inputs.gates),
        )
    result = Prepared(stem: stem, query: request, geojson: path)
    if withPage:
      # the page is rewritten each time (it is tiny, and may have changed since)
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
  let made = prepare(g, p, userDir(dir.get), p.web.kind != wkNone)
  if made.status != 0:
    return made.status
  case p.web.kind
  of wkServe:
    # the address pins what was made: the activities, and the state of them
    return serveWeb(
      g,
      commandName,
      WebOptions(port: p.web.port, noOpen: p.web.noOpen, newToken: p.web.newToken),
      dir.get,
      made.query,
    )
  of wkWorker:
    stdout.say made.page & "\n" & made.geojson & "\n" & made.query & "\n"
  of wkNone:
    stdout.say made.geojson & "\n"
  exitOk
