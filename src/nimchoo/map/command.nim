## `nch map`: the routes of the selected activities, and the climbs they went up, on a map.  A GeoJSON file in the cache
## directory holds them (every feature says what it is, in `kind`, and nothing about how it looks), and a page, drawn by
## Leaflet in the browser (`--web`), decides the look.
##
## Which activities are drawn is carried by the address of the page: `bits=...` is the list of them (selection/bits.nim)
## and `check=...` a short hash of their content, so that an address made before the database was rebuilt (when the
## ids mean other activities) or before activities were deleted is refused and not wrong.  The files are named by a
## hash of that request, in pronounceable words (`map-lusab-babad-fuzoh.geojson`), so asking again for the same thing
## finds the file already there, if the data it was made from are unchanged (the header records a key of them; if it
## differs the file is made again).
##
## This module is newer than `importer`, `selection` and `climbs`: it reads their tables and uses their libraries.

import std/[options, os, strutils, tables]
import db_connector/db_sqlite
import ../cache
import ../cli/common
import ../climbs/[attempts, report, work]
import ../db/store
import ../errors
import ../importer/keys
import ../version
import ../fit/time
import ../ids
import ../selection/[bits, selection]
import ../serve/[launch, pages, webopts]
import ./[lines, page, params]

{.push raises: [].}

const usage* =
  """usage: nch [--db PATH] [--user NAME] map [--web [--no-open] [--port N] [--new-token]]

Show the routes of the selected activities (see `nch activities --select`) on a map, and the climbs they went up,
drawn over them.  It makes a GeoJSON file in the cache directory and prints its path; with --web it also serves a page
that draws it, and opens it in a browser.  Several rides over the same roads show as a heat map; a click on a route
says which activity it is, a click on a climb says what it is.  The climbs not yet worked out are worked out first
(the first time that can take a minute).  Asking again for the same thing finds the file already there.

The address of the page records which activities it shows, so a reload shows the same ones even if the selection has
since changed.  It stops working when the database is rebuilt (the numbers then mean other activities).
""" &
  webUsage("the map", "GeoJSON") &
  """  --bits LIST      for programs: the activities to draw, as in the address (default: the current selection)
  --check HASH     for programs, with --bits: a check that they are still the activities the address was made for
  -h, --help       show this help
"""

const
  toleranceM = 5.0 ## routes are simplified so that they stray at most this far
  metresPerDegree = 111320.0

proc idList(ids: seq[int64]): string =
  for i, id in ids:
    if i > 0:
      result.add ","
    result.add $id

proc routesOf(st: Store, ids: seq[int64]): seq[Route] {.raises: [StoreError].} =
  ## The routes of the activities, oldest first.
  if ids.len == 0:
    return
  let geometry =
    "AsGeoJSON(SimplifyPreserveTopology(r.geom, " &
    formatFloat(toleranceM / metresPerDegree, ffDecimal, 9) & "), 5)"
  guard:
    for row in st.db.fastRows(
      sql(
        "select a.id, a.start_t, coalesce(a.sport, ''), a.distance_m, " & geometry &
          " from activity a join route r on r.activity_id = a.id where a.id in (" &
          idList(ids) & ") order by a.start_t, a.id"
      )
    ):
      try:
        result.add Route(
          id: ActivityId(parseBiggestInt(row[0])),
          startT: UnixTime(parseBiggestInt(row[1])),
          sport: row[2],
          distanceM:
            if row[3].len > 0:
              some(parseFloat(row[3]))
            else:
              none(float),
          geometry: row[4],
        )
      except ValueError:
        raiseStore("bad number from the database")

proc climbsOf(st: Store, ids: seq[int64]): seq[Climb] {.raises: [StoreError].} =
  ## The climbs the activities went up, the biggest first.
  let sectors = climbsOfActivities(st, ids)
  if sectors.len == 0:
    return
  let names = shownNames(st)
  guard:
    for id in sectors:
      for row in st.db.fastRows(
        sql"""select length_m, gain_m, gradient, coalesce(category, ''), AsGeoJSON(route, 5)
          from sector where id = ?""",
        id,
      ):
        try:
          result.add Climb(
            id: id,
            name: names.getOrDefault(id, "unnamed"),
            category: row[3],
            lengthM: parseFloat(row[0]),
            gainM: parseFloat(row[1]),
            gradient: parseFloat(row[2]),
            geometry: row[4],
          )
        except ValueError:
          raiseStore("bad number from the database")

type Prepared = object
  status: int ## 0 if the files are there; else the exit status (already reported)
  stem, query: string ## the name of the files, and what pins the page in an address
  geojson, page: string ## paths (page: only if asked for)

proc startsWithFile(path, prefix: string): bool =
  ## Whether the file begins with `prefix`.
  try:
    let f = open(path)
    defer:
      f.close()
    var head = newString(prefix.len)
    result = f.readBuffer(addr head[0], prefix.len) == prefix.len and head == prefix
  except IOError:
    result = false

proc prepare(g: Globals, p: Params, dir: string, withPage: bool): Prepared =
  ## Make the GeoJSON file (if it is not there) and, if asked, the page.  Reports problems.
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return Prepared(status: failure("nch map", e.msg))
  try:
    # the activities: those of the address, else the selection
    var ids: seq[int64]
    var bitsText = p.bits
    if p.bits.len > 0:
      let d = decodeBits(p.bits, maxActivityId(st))
      if d.problem.len > 0:
        return Prepared(status: usageError("nch map", usage, d.problem))
      ids = d.ids
    else:
      ids = selectedIds(st)
      bitsText = encodeBits(ids)
    let mine = ownedIds(st, ids)
    let check = checkOf(st, mine)
    if p.check.len > 0 and p.check != check:
      return Prepared(
        status: failure(
          "nch map",
          "the activities of this address are not the ones it was made for " &
            "(the database has been rebuilt, or activities were deleted): run `nch map` again",
        )
      )
    if mine.len == 0:
      return Prepared(
        status: failure(
          "nch map",
          if p.bits.len == 0:
            "the selection is empty (see `nch activities --select`)"
          else:
            "none of the activities of this address exist",
        )
      )
    if mine.len < ids.len:
      stderr.say "note: " & $(ids.len - mine.len) & " of the " & $ids.len &
        " activities of this address do not exist\n"
    let request = "bits=" & bitsText & "&check=" & check
    # what the file is made from: the data of each package it reads, and the version of the program
    let routeKey = routesKey(st, mine)
    if routeKey.count == 0:
      return Prepared(
        status: failure(
          "nch map",
          "none of the " & $mine.len &
            " activities has a route (no positions in the files)",
        )
      )
    let worked = ensureClimbs(st)
    if worked.activities > 0:
      stderr.say "worked out the climbs of " & $worked.activities & " activities: " &
        $worked.sectors & " new climbs\n"
    let climbs = climbsOf(st, mine)
    let inputs = inputsKey(
      "map " & nchCommit & " tolerance " & $toleranceM,
      [
        ("activities", contentKey(st, mine)),
        ("routes", routeKey.key),
        ("climbs", climbsKey(climbs)),
      ],
    )
    # the files are named by a hash of the request; if the name is found to be another request's, the next is tried
    var stem = ""
    var path = ""
    for attempt in 0 .. 5:
      let s = requestStem(
        "map",
        if attempt == 0:
          request
        else:
          request & "#" & $attempt,
      )
      if s.isNone:
        return Prepared(status: failure("nch map", "cannot name a file"))
      stem = s.get
      path = cacheFile(dir, stem, "geojson").get
      if not fileExists(path) or startsWithFile(path, requestPrefixFor(request)):
        break
    if not startsWithFile(path, filePrefixFor(request, inputs)):
      # not there, or made from other inputs: made again, in place
      let routes = routesOf(st, mine)
      if routes.len < mine.len:
        stderr.say "note: " & $(mine.len - routes.len) & " of the " & $mine.len &
          " activities have no route (no positions in the files)\n"
      writeAtomic(path, featureCollection(routes, climbs, request, inputs))
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
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch map", usage, p.problem)
  let dir = cacheDir()
  if dir.isNone:
    return failure("nch map", "no place for the cache: set NCH_CACHE or HOME")
  try:
    makeCacheDirs(dir.get)
  except IOError, OSError:
    return
      failure("nch map", "cannot make " & dir.get & ": " & getCurrentExceptionMsg())
  let made = prepare(g, p, userDir(dir.get), p.web.worker or p.web.enabled)
  if made.status != 0:
    return made.status
  if p.web.enabled:
    # the address pins what was made: the activities, and the check of them
    return serveWeb(
      g,
      cmMap,
      WebOptions(port: p.web.port, noOpen: p.web.noOpen, newToken: p.web.newToken),
      dir.get,
      made.query,
    )
  if p.web.worker:
    stdout.say made.page & "\n" & made.geojson & "\n" & made.query & "\n"
  else:
    stdout.say made.geojson & "\n"
  exitOk
