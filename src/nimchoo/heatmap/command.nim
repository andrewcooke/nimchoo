## `nch heatmap`: the routes of the selected activities as a GeoJSON file in
## the cache directory (cache.nim).  The file is named after the options, with
## the selection pinned by its key (select/selection.nim), so the same request
## finds the same file and nothing is made twice.
##
## This module is newer than `importer` and `select`: it reads their tables
## (selection, activity, route) and uses the selection key.

import std/[options, os, strutils]
import db_connector/db_sqlite
import ../cache
import ../cli/common
import ../db/store
import ../errors
import ../select/selection
import ./[lines, params]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] heatmap [OPTIONS]

Write the routes of the selected activities (see `nch select`) as a GeoJSON
file in the cache directory, and print its path.  Several rides over the same
roads show as a heatmap in any program that draws GeoJSON with transparency.
Asking again for the same thing finds the file already there.

  --sel KEY        draw the selection with this key (as in the file name);
                   default: the current selection
  --style lines    how to draw (the only style so far)
  --tolerance M    simplify routes so they stray at most M metres (default 5;
                   0: do not simplify)
  -h, --help       show this help
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
        result.add Route(id: parseBiggestInt(row[0]), startT: parseBiggestInt(row[1]),
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

proc write(path, text: string) {.raises: [IOError, OSError].} =
  ## Write the file so that nobody sees half of it: to a new name, then rename.
  createDir parentDir(path)
  let tmp = path & ".part"
  writeFile(tmp, text)
  try:
    moveFile(tmp, path)
  except OSError as e:
    raise e
  except Exception:              # (moveFile is declared to raise anything)
    raise newException(OSError, "cannot rename " & tmp)

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
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch heatmap", e.msg)
  defer: st.close()
  try:
    let current = selectionKey(st)
    let wanted = if p.sel.len > 0: p.sel else: current
    let stem = fileStem("heatmap", [("sel", wanted), ("style", p.style),
                                    ("tolerance", metres(p.toleranceM))])
    if stem.isNone:
      return usageError("nch heatmap", usage, "cannot name a file for these options")
    let path = cacheFile(dir.get, stem.get, "geojson").get
    if fileExists(path):                       # made before: nothing to do
      stdout.say path & "\n"
      return exitOk
    if wanted != current:
      return failure("nch heatmap", "the selection has changed since that was made " &
        "(it was " & wanted & ", it is now " & current & "); leave out --sel to draw " &
        "the current selection")
    let chosen = selectedCount(st)
    if chosen == 0:
      return failure("nch heatmap", "the selection is empty (see `nch select`)")
    let routes = routesOf(st, p.toleranceM)
    if routes.len == 0:
      return failure("nch heatmap", "none of the " & $chosen &
        " selected activities has a route (no positions in the files)")
    if routes.len < chosen:
      stderr.say "note: " & $(chosen - routes.len) & " of the " & $chosen &
        " selected activities have no route\n"
    write(path, featureCollection(routes))
    stdout.say path & "\n"
    exitOk
  except StoreError as e:
    failure("nch heatmap", e.msg)
  except IOError, OSError:
    failure("nch heatmap", "cannot write to " & dir.get & ": " & getCurrentExceptionMsg())
