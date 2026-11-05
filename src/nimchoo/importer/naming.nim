## Naming the activities: each that has no name yet (null) gets its start place and its name from the places near its
## route (see names/activity.nim), kept on the activity as text.  Done at the end of `nch import`, so the names are
## decided in the run that imports; the first time (or after a migration) it names every activity.  If the names are
## needed and cannot be had it is a DownloadError: the activities named so far keep their names, the rest stay null.

import db_connector/db_sqlite
import std/strutils
import ../db/store
import ../errors
import ../names/[activity, countries]

{.push raises: [].}

type Named* = object
  total*: int                    ## activities that had no name
  named*: int                    ## ... of which now have one
  startOnly*: int                ## ... and only a start place
  nothing*: int                  ## ... and nothing to say

proc pending*(st: Store): seq[int64] {.raises: [StoreError].} =
  ## The activities not named yet, in the order they began.
  guard:
    for r in st.db.fastRows(sql"select id from activity where name is null order by start_t, id"):
      try: result.add parseBiggestInt(r[0])
      except ValueError: raiseStore("a bad activity id")

proc ensureActivityNames*(st: Store, names: Names, progress: proc(done, total: int) {.closure, raises: [].} = nil): Named
    {.raises: [StoreError, DownloadError].} =
  let todo = pending(st)
  result.total = todo.len
  for k, id in todo:
    var lons, lats: seq[float]
    guard:
      for r in st.db.fastRows(sql"select lon, lat from coords where activity_id = ? order by t", id):
        try:
          lons.add parseFloat(r[0])
          lats.add parseFloat(r[1])
        except ValueError: raiseStore("a bad position")
    let got = nameActivity(names, lons, lats)
    guard: st.db.exec(sql"update activity set start_place = ?, name = ? where id = ?", got.start, got.name, id)
    if got.name.len > 0: inc result.named
    elif got.start.len > 0: inc result.startOnly
    else: inc result.nothing
    if progress != nil: progress(k + 1, todo.len)
