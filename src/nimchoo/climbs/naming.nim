## Naming the sectors: for each that has no name yet, ask the names module for a name from the places
## near its route, and keep it on the sector (as text).  Done after `ensureClimbs`, when a command wants the
## names.  If the names cannot be had (no network) it is a DownloadError and the command stops.

import std/options
import ../db/[statement, store]
import ../core/errors
import ../names/[climb, climbpick, countries]
import ./[match, ordinal]

{.push raises: [].}

type Named* = object
  named*, nothing*: int ## sectors given a name, and those looked at that have none near
  damaged*: seq[int64]
    ## sectors whose route cannot be read: left without a name (null), so that they are tried again, not marked as
    ## having none near

proc ensureSectorNames*(
    st: Store, names: Names
): Named {.raises: [StoreError, DownloadError].} =
  ## Name the sectors that have no name yet (a null name; "" is a sector looked at that has none near).  If the names
  ## are needed and cannot be had, a DownloadError: the sectors named so far keep their names and the rest stay null.
  let todo = st.db.query(int64, "select id from sector where name is null order by id")
  for id in todo:
    let route = parseLineString(
      st.db.scalar(
        Option[string], "select AsText(route) from sector where id = :id", id = id
      )
    )
    if route.isNone:
      result.damaged.add id
      continue
    let pick = nameClimb(names, route.get.lon, route.get.lat)
    if pick.isSome:
      st.db.execute(
        "update sector set name = :name where id = :id", name = pick.get.name, id = id
      )
      assignNumber(st, id)
      inc result.named
    else:
      st.db.execute("update sector set name = '' where id = :id", id = id)
      assignNumber(st, id)
      inc result.nothing
