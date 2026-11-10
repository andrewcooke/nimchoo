## The rows of a listing of activities, as the table and the calendar show them: what a row is made of, and reading
## them from a query (`activities` runs the queries, so it may read the tables of `importer` and `selection`).  Other
## packages that show activities (`calendar`) ask for rows here.

import std/options
import ../../core/[errors, ids]
import ../db/[sqltext, statement, store]
import ../fit/time
import ../user/session
import ./table

{.push raises: [].}

func rowColumns*(verbose: bool, userId: UserId): Sql =
  ## (it carries `:me`, the user whose selection says which are chosen)
  ## What a row of the listing is made of (see table.nim); not recorded: -1 and ''.
  ## The path of the file (for `verbose`) is where it was last seen, else its name.
  sqlOf(
    "a.start_t as start_t, coalesce(a.sport, '') as sport, " &
      "coalesce(a.sub_sport, '') as sub, coalesce(a.distance_m, -1) as dist, " &
      "coalesce(a.timer_s, -1) as active, f.name as file, " &
      "(select name from user where id = f.user_id) as user, " &
      # whether the user has it in their selection
      "a.id in (select activity_id from selection where user_id = :me) as chosen, " & (
      if verbose:
      "coalesce((select min(path) from seen_file where file_id = f.id), f.name) as path, "
      else: "f.name as path, "
    ) &
      # where it started and what it is called (text made when it was imported: see names/activity.nim): in every listing
      "coalesce(a.start_place, '') as pname, coalesce(a.name, '') as aname, " & (
      # whether it has a start (said "no GPS" if not): -v only
      if verbose: "ST_Y(a.start) as slat, ST_X(a.start) as slon"
      else: "null as slat, null as slon"
    )
  )
    .with("me", userId)

const rowFields* =
  "start_t, sport, sub, dist, active, file, user, chosen, path, pname, aname, slat, slon"
  ## the columns of a row, in the order `readRows` reads them

proc readRows*(st: Store, query: Sql): seq[ListRow] {.raises: [StoreError].} =
  ## The rows a query gives (the columns `rowFields`), as listed.
  for r in st.db.query(
    tuple[
      startT: int64,
      sport, subSport: string,
      dist, active: float,
      file, user: string,
      chosen: bool,
      path, place, name: string,
      lat, lon: Option[float],
    ],
    query,
  ):
    result.add ListRow(
      startT: UnixTime(r.startT),
      sport: r.sport,
      subSport: r.subSport,
      distanceM: (if r.dist >= 0: some(r.dist) else: none(float)),
      activeS: (if r.active >= 0: some(r.active) else: none(float)),
      file: r.file,
      user: r.user,
      selected: r.chosen,
      path: r.path,
      place: r.place,
      name: r.name,
      position: positionText(r.lat, r.lon),
    )

proc selectionRows*(st: Session, verbose: bool): seq[ListRow] {.raises: [StoreError].} =
  ## The activities in the user's selection, oldest first.
  readRows(
    st,
    "select " & rowColumns(verbose, st.userId) &
      " from selection s join activity a on a.id = s.activity_id join file f on f.id = a.file_id " &
      "where s.user_id = :owner order by a.start_t, a.id".sqlOf.with("owner", st.userId),
  )

proc allRows*(st: Session, verbose: bool): seq[ListRow] {.raises: [StoreError].} =
  ## Every activity of the user, oldest first, those in the selection marked.
  readRows(
    st,
    "select " & rowColumns(verbose, st.userId) &
      " from activity a join file f on f.id = a.file_id " &
      "where f.user_id = :owner order by a.start_t, a.id".sqlOf.with("owner", st.userId),
  )
