## Naming the sectors: for each that has no name yet, ask the names module for a name from the places
## near its route, and keep it on the sector (as text).  Done after `ensureClimbs`, when a command wants the
## names.  If the names cannot be had (no network) it is a DownloadError and the command stops.

import std/[options, strutils]
import db_connector/db_sqlite
import ../db/store
import ../errors
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
  var todo: seq[int64]
  guard:
    for r in st.db.fastRows(sql"select id from sector where name is null order by id"):
      try:
        todo.add parseBiggestInt(r[0])
      except ValueError:
        raiseStore("a bad sector id")
  for id in todo:
    var route: Option[Path]
    guard:
      route = parseLineString(
        st.db.getValue(sql"select AsText(route) from sector where id = ?", id)
      )
    if route.isNone:
      result.damaged.add id
      continue
    let pick = nameClimb(names, route.get.lon, route.get.lat)
    if pick.isSome:
      guard:
        st.db.exec(sql"update sector set name = ? where id = ?", pick.get.name, id)
      assignNumber(st, id)
      inc result.named
    else:
      guard:
        st.db.exec(sql"update sector set name = '' where id = ?", id)
      assignNumber(st, id)
      inc result.nothing
