## The rows of a listing of activities, as the table and the calendar show them: what a row is made of, and reading
## them from a query (`activities` runs the queries, so it may read the tables of `importer` and `selection`).

import std/[options, strutils]
import ../../core/[errors, ids]
import ../db/[sqltext, statement, store]
import ../fit/time
import ../user/session
import ../importer/active
import ../tags/sport
import ./table

{.push raises: [].}

func rowColumns*(verbose: bool, userId: UserId): Sql =
  ## (it carries `:me`, the user whose selection says which are chosen)
  ## What a row of the listing is made of (see table.nim); not recorded: -1 and ''.
  ## The path of the file (for `verbose`) is where it was last seen, else its name.
  sqlOf(
    "a.start_epoch as start_epoch, " & sportSql() & " as sport, " &
      "coalesce(a.distance_m, -1) as dist, " & activeSql() & " as active, " &
      # whether the user has it in their selection
      "a.id in (select activity_id from activity_selection where user_id = :me) as chosen, " &
    (
      if verbose:
      "coalesce((select min(path) from seen_file where file_id = f.id), f.name) as path, "
      else: "f.name as path, "
    ) &
      # where it started and what it is called (text made when it was imported: see names/activity.nim): in every listing
      "coalesce(a.start_place, '') as pname, coalesce(a.name, '') as aname, " & (
      # whether it has a start (said "no GPS" if not): -v only
      if verbose: "ST_Y(a.start_point) as slat, ST_X(a.start_point) as slon, "
      else: "null as slat, null as slon, "
    ) & (
      # its tags, as given, in the order of their folded forms: -v only
      if verbose:
        "coalesce((select group_concat(tag, ' ') from (select tag from activity_tag " &
          "where activity_id = a.id order by folded)), '') as tags"
      else:
        "'' as tags"
    )
  )
    .with("me", userId)

const rowFields* =
  "start_epoch, sport, dist, active, chosen, path, pname, aname, slat, slon, tags"
  ## the columns of a row, in the order `readRows` reads them

proc readRows*(st: Store, query: Sql): seq[ListRow] {.raises: [StoreError].} =
  ## The rows a query gives (the columns `rowFields`), as listed.
  for r in st.db.query(
    tuple[
      startT: int64,
      sport: string,
      dist, active: float,
      chosen: bool,
      path, place, name: string,
      lat, lon: Option[float],
      tags: string,
    ],
    query,
  ):
    let (sport, subSport) = sportParts(r.sport)
    result.add ListRow(
      startT: UnixTime(r.startT),
      sport: sport,
      subSport: subSport,
      distanceM: (if r.dist >= 0: some(r.dist) else: none(float)),
      activeS: r.active,
      selected: r.chosen,
      path: r.path,
      place: r.place,
      name: r.name,
      position: startText(r.lat, r.lon),
      tags: r.tags.splitWhitespace,
    )

proc activityCount*(st: Session): int {.raises: [StoreError].} =
  ## How many activities the user has.
  st.db.scalar(
    int,
    "select count(*) from activity a join file f on f.id = a.file_id where f.user_id = :userId",
    userId = st.userId,
  )

proc selectionRows*(st: Session, verbose: bool): seq[ListRow] {.raises: [StoreError].} =
  ## The activities in the user's selection, oldest first.
  readRows(
    st,
    "select " & rowColumns(verbose, st.userId) &
      " from activity_selection s join activity a on a.id = s.activity_id join file f on f.id = a.file_id " &
      "where s.user_id = :owner order by a.start_epoch, a.id".sqlOf.with(
        "owner", st.userId
      ),
  )
