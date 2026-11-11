## Naming the sectors: for each that has no name yet, ask the names module for a name from the places
## near its route, and keep it on the sector (as text).  Done after `ensureClimbs`, when a command wants the
## names.  If the names cannot be had (no network) it is a DownloadError and the command stops.

import std/[options, strutils]
import ../db/statement
import ../db/store
import ../../core/[errors, globals, logfile]
import ../names/climb
import ../names/climbpick
import ../names/countries
import ../names/open
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

func damagedText*(n: Named): string =
  ## What to say about climbs that were not named because their route cannot be read.
  $n.damaged.len & (if n.damaged.len == 1: " climb has" else: " climbs have") &
    " a route that cannot be read (damaged data) and " &
    (if n.damaged.len == 1: "was" else: "were") & " not named: " & n.damaged.join(", ")

proc nameClimbs*(
    g: Globals,
    st: Store,
    command: string,
    say: proc(line: string) {.closure, raises: [].},
): Option[Named] {.raises: [StoreError, DownloadError].} =
  ## Name the climbs that have no name yet, as `command` (what the log calls it): the names for the places are opened
  ## (`openNames`: the cache, `--offline`, the downloads told in the log and, through `say`, on the screen) and, if they can
  ## be had, the climbs are named; a warning for climbs that cannot be read goes to `say` and the log, and what was done to
  ## the log.  None if there is no cache directory to keep the names in.  Used by `nch climbs` and by the import.
  let names = openNames(g, st, command, say)
  if names.isNone:
    return none(Named)
  let named = ensureSectorNames(st, names.get)
  if named.damaged.len > 0:
    say "warning: " & damagedText(named)
    g.log.log(lvWarn, command, leAdvisory, damagedText(named))
  if named.named + named.nothing > 0:
    g.log.log(
      lvInfo,
      command,
      leDone,
      "named " & $named.named & " climbs (" & $named.nothing & " with no name near)",
    )
  some(named)
