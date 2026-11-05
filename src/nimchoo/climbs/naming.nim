## Naming the sectors: for each that has not been looked at, ask the names module for a name from the places
## near its route, and keep it on the sector (as text).  Done after `ensureClimbs`, when a command wants the
## names.  If the names cannot be had now (no network), nothing is marked as looked at and the rest is left
## for another time.

import std/strutils
import db_connector/db_sqlite
import ../db/store
import ../errors
import ../names/[climb, climbpick, countries]

{.push raises: [].}

type Named* = object
  named*, nothing*: int          ## sectors given a name, and those looked at that have none
  pending*: int                  ## left for another time (the names could not be had)

proc parseRoute(text: string): tuple[lons, lats: seq[float]] =
  ## The positions of "LINESTRING Z(lon lat alt, ...)".
  let a = text.find('(')
  let b = text.rfind(')')
  if a < 0 or b <= a: return
  try:
    for part in text[a + 1 ..< b].split(','):
      let f = part.splitWhitespace
      if f.len < 2: return (@[], @[])
      result.lons.add parseFloat(f[0])
      result.lats.add parseFloat(f[1])
  except ValueError:
    result = (@[], @[])

proc ensureSectorNames*(st: Store, names: Names): Named {.raises: [StoreError].} =
  ## Name the sectors that have not been looked at.
  var todo: seq[int64]
  guard:
    for r in st.db.fastRows(sql"select id from sector where name_checked = 0 order by id"):
      try: todo.add parseBiggestInt(r[0])
      except ValueError: raiseStore("a bad sector id")
  for k, id in todo:
    var route: tuple[lons, lats: seq[float]]
    guard:
      route = parseRoute(st.db.getValue(sql"select AsText(route) from sector where id = ?", id))
    let r = nameClimb(names, route.lons, route.lats)
    case r.status
    of nsLater:
      result.pending = todo.len - k
      return
    of nsNamed:
      guard: st.db.exec(sql"update sector set name = ?, name_checked = 1 where id = ?", r.pick.name, id)
      inc result.named
    of nsNothing:
      guard: st.db.exec(sql"update sector set name_checked = 1 where id = ?", id)
      inc result.nothing
