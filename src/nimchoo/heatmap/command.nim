## `nch heatmap`: the routes of the selected activities as a GeoJSON file in
## the cache directory (cache.nim).  The file is named after the options, with
## the selection pinned by its key (selection/selection.nim), so the same request
## finds the same file and nothing is made twice.
##
## This module is newer than `importer` and `selection`: it reads their tables
## (selection, activity, route) and uses the selection key.

import std/[options, os, strutils]
import db_connector/db_sqlite
import ../cache
import ../cli/common
import ../db/store
import ../errors
import ../fit/time
import ../ids
import ../selection/selection
import ../serve/[launch, pages, webopts]
import ./[lines, page, params]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] heatmap [OPTIONS]

Write the routes of the selected activities (see `nch activities --select`) as a GeoJSON
file in the cache directory, and print its path.  Several rides over the same
roads show as a heatmap in any program that draws GeoJSON with transparency.
Asking again for the same thing finds the file already there.

  --check HASH     make sure the selection is still the one with this hash (the
                   hash in the file name, `check-…`).  It chooses nothing: it is a
                   safeguard, so that a file or address made earlier cannot show
                   something else.  If the selection has changed, and the file made
                   for that hash is gone, the command stops and says so.  Leave it
                   out to draw the current selection
  --style lines    how to draw (the only style so far)
  --tolerance M    simplify routes so they stray at most M metres (default 5;
                   0: do not simplify)
""" & webUsage("the heat map", "GeoJSON") & """  -h, --help       show this help
"""

const metresPerDegree = 111320.0

proc routesOf(st: Store, toleranceM: float): seq[Route] {.raises: [StoreError].} =
  ## The routes of the selected activities of the store's user, oldest first.
  let geometry =
    if toleranceM > 0:
      "AsGeoJSON(SimplifyPreserveTopology(r.geom, " &
        formatFloat(toleranceM / metresPerDegree, ffDecimal, 9) & "), 5)"
    else:
      "AsGeoJSON(r.geom, 5)"
  guard:
    for row in st.db.fastRows(sql("select a.id, a.start_t, coalesce(a.sport, ''), " &
        "a.distance_m, " & geometry & " from selection s " &
        "join activity a on a.id = s.activity_id join route r on r.activity_id = a.id " &
        "where s.user_id = ? order by a.start_t, a.id"), st.userId):
      try:
        result.add Route(id: ActivityId(parseBiggestInt(row[0])), startT: UnixTime(parseBiggestInt(row[1])),
                         sport: row[2],
                         distanceM: if row[3].len > 0: some(parseFloat(row[3]))
                                    else: none(float),
                         geometry: row[4])
      except ValueError:
        raiseStore("bad number from the database")

proc selectedCount(st: Store): int {.raises: [StoreError].} =
  guard:
    try: result = parseInt(st.db.getValue(
      sql"select count(*) from selection where user_id = ?", st.userId))
    except ValueError: raiseStore("bad number from the database")

type Prepared = object
  status: int             ## 0 if the files are there; else the exit status (already reported)
  stem, wanted: string
  geojson, page: string   ## paths (page: only if asked for)

proc prepare(g: Globals, p: Params, dir: string, withPage: bool): Prepared =
  ## Make the GeoJSON file (if it is not there) and, if asked, the page.  Reports problems.
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return Prepared(status: failure("nch heatmap", e.msg))
  try:
    let current = selectionKey(st)
    let wanted = if p.check.len > 0: p.check else: current
    let stem = fileStem("heatmap", [("check", wanted), ("style", p.style),
                                    ("tolerance", metres(p.toleranceM))])
    if stem.isNone:
      return Prepared(status: usageError("nch heatmap", usage, "cannot name a file for these options"))
    let path = cacheFile(dir, stem.get, "geojson").get
    if not fileExists(path):                   # (made before: nothing to do)
      if wanted != current:
        return Prepared(status: failure("nch heatmap", "the selection has changed since that was made " &
          "(it was " & wanted & ", it is now " & current & "); leave out --check to draw " &
          "the current selection"))
      let chosen = selectedCount(st)
      if chosen == 0:
        return Prepared(status: failure("nch heatmap", "the selection is empty (see `nch activities --select`)"))
      let routes = routesOf(st, p.toleranceM)
      if routes.len == 0:
        return Prepared(status: failure("nch heatmap", "none of the " & $chosen &
          " selected activities has a route (no positions in the files)"))
      if routes.len < chosen:
        stderr.say "note: " & $(chosen - routes.len) & " of the " & $chosen &
          " selected activities have no route\n"
      writeAtomic(path, featureCollection(routes))
    result = Prepared(stem: stem.get, wanted: wanted, geojson: path)
    if withPage:
      # the page is rewritten each time (it is tiny, and may have changed since)
      let pagePath = cacheFile(dir, stem.get, "html").get
      let html = pageHtml(extractFilename(path), "Heat map " & wanted)
      if html.isNone:
        return Prepared(status: failure("nch heatmap", "cannot make a page for " & path))
      writeAtomic(pagePath, html.get)
      result.page = pagePath
  except StoreError as e:
    result = Prepared(status: failure("nch heatmap", e.msg))
  except IOError, OSError:
    result = Prepared(status: failure("nch heatmap", "cannot write to " & dir & ": " & getCurrentExceptionMsg()))
  except TemplateError as e:
    result = Prepared(status: failure("nch heatmap", "cannot make the page: " & e.msg &
      " (the template is system/templates/heatmap.html and the libraries are system/libraries.txt, " &
      "in the cache directory; delete one to have the built-in one again)"))

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch heatmap ARGS`; returns the exit status.
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch heatmap", usage, p.problem)
  let dir = cacheDir()
  if dir.isNone:
    return failure("nch heatmap", "no place for the cache: set NCH_CACHE or HOME")
  try:
    makeCacheDirs(dir.get)
  except IOError, OSError:
    return failure("nch heatmap", "cannot make " & dir.get & ": " & getCurrentExceptionMsg())
  let made = prepare(g, p, userDir(dir.get), p.web.worker or p.web.enabled)
  if made.status != 0: return made.status
  if p.web.enabled:
    # the address pins what was made: the selection, the style and the tolerance
    let parsed = parseStem(made.stem)
    var query: seq[string]
    if parsed.isSome:
      for (k, v) in parsed.get[1]: query.add k & "=" & v
    return serveWeb(g, "heatmap", WebOptions(port: p.web.port, noOpen: p.web.noOpen, newToken: p.web.newToken),
                    dir.get, query.join("&"))
  if p.web.worker: stdout.say made.page & "\n" & made.geojson & "\n"
  else: stdout.say made.geojson & "\n"
  exitOk
