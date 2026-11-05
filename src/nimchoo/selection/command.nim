## `nch list`: the activities that meet some criteria, and (with `--save`) the
## choice of those as "the selection", which other commands (heatmap ...) work on.
## The selection is kept in the database (table `selection`), for the current user,
## and replaced whenever `--save` is given; `--show` shows it.  What is listed is
## what is saved.
##
## This module is newer than `importer` and reads its tables (activity, file,
## coords, route) directly.

import std/[options, sequtils, strutils, tables, terminal, times]
import db_connector/db_sqlite
import ../cli/common
import ../climbs/report
import ../db/store
import ../errors
import ../fit/time
import ../ui/[live, logfile, style, vocabulary]
import ./[calendar, criteria, fold, table]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] list [CRITERIA] [--save]
       nch [--db PATH] [--user NAME] list --show

List the activities that meet the criteria (all of them if there are none), and
with --save keep them as the "selection" that other commands use (replacing the
last one).  Criteria are combined with "and".

  --users A B C      whose activities (default: the current user)
  --sport A B        only these sports (cycling, running, swimming ...); "none"
                     means not recorded; "latest" or "previous": that activity's sport
  --sub-sport A B    only these sub-sports (road, trail, open_water ...).  Many
                     files say "generic" or nothing, so this misses some rides
  --name TEXT        activities whose name contains TEXT, whatever its case or accents:
                     --name toyo finds "El Toyo and back"; several words are alternatives
                     (--name toyo farellones); a name with spaces is quoted; "none": no name;
                     "latest" or "previous": the same name as that activity
  --start TEXT       the same for the place the activity started ("Providencia", "near Lo
                     Barnechea"): --start providencia
  --path TEXT        the same for the path of the file the activity was imported from (or any
                     other path the same file was seen at): --path bowman, --path 2026-10
  --climb TEXT       activities that have an effort on a climb whose name (as `nch climbs --all` shows
                     it) contains TEXT: --climb farellones (all of them), --climb "farellones (2/3)"
                     (one); retired climbs too.  It is an error if no climb has the text
  --distance RANGE   distance in km: 40- (40 or more), 10-50, -5 (up to 5);
                     0.5- for half a km; 42~2 (between 40 and 44), latest~10%,
                     previous~10%
  --active RANGE     active time: 1h-, 30m-2h, -45m (units d h m s, as printed);
                     2h~15m, latest~10%, previous~10%
  --from TIME        activities that start at or after TIME
  --to TIME          activities that start before the end of TIME
                     (TIME is in your time zone: 2018-08-27, 2018-08-27T09:30 or
                     with seconds; a --to date means the whole day)
  --gps              only activities that have positions (a GPS track)
  --no-gps           only activities that have none (indoor rides, treadmill runs ...)
  --near LAT,LON     activities that start within the radius of the point
  --near latest      ... of where the latest activity started (or "previous")
  --radius KM        radius for --near in kilometres (default: 100); on its own it
                     means --near latest
  --invert           the activities that do NOT meet the criteria (all of them taken together):
                     everything that fails to match, including those that have nothing
                     recorded for a criterion.  "latest" and "previous" are found before
                     inverting; --newest and --oldest apply after.  Needs a criterion
  -n, --newest N     only the N newest of the activities that meet the other criteria
  --oldest N         only the N oldest of them
  --latest           the same as --newest 1
  --save             make what is listed the selection
  --show             show the selection (no criteria allowed)
  -v, --verbose      show more of each activity: where it started (its coordinates, or
                     "no GPS" if the file has no positions), the place it started and its name
                     (made when it was imported), and the path of its file
  --calendar         show the activities on a calendar instead of a table: a row for each month
                     that has one (with -v, every month from the first to the last), the days
                     in columns by weekday (weeks start on Monday).  White: an activity that was
                     listed; yellow: one that is also in the selection; grey: none
  -h, --help         show this help

"latest" is the newest activity among those that meet the criteria that do not use
"latest": so  --sport cycling --distance latest~10%  is cycling rides within 10% of
the length of your latest cycling ride.  (--latest, the flag, is --newest 1.)

"previous" is the one activity that was selected before (see --show): list it with
--save, then  --sport previous --distance previous~10%  finds rides like it.  It is an
error unless exactly one activity is selected.
"""

func radiusText(x: float): string =
  ## 100.0 -> "100", 2.5 -> "2.5"
  let t = $x
  if t.endsWith(".0"): t[0 ..< t.len - 2] else: t

proc userIdOf(st: Store, name: string): UserId {.raises: [StoreError].} =
  guard:
    let v = st.db.getValue(sql"select id from user where name = ?", name)
    if v.len == 0: raiseStore("no such user: " & name)
    try: result = UserId(parseBiggestInt(v))
    except ValueError: raiseStore("bad user id " & v)

proc number(st: Store, query: string): int {.raises: [StoreError].} =
  guard:
    try: result = parseInt(st.db.getValue(sql(query)))
    except ValueError: raiseStore("bad number from the database")

proc startOf(st: Store, activityId: ActivityId): Option[(float, float)] {.raises: [StoreError].} =
  ## Where an activity started (latitude, longitude); none if it has no positions.
  guard:
    let c = st.db.getRow(sql"select ST_Y(start), ST_X(start) from activity where id = ?", activityId)
    try:
      if c[0].len > 0: result = some((parseFloat(c[0]), parseFloat(c[1])))
    except ValueError:
      discard

proc present(st: Store, column, idList: string): seq[(string, int)]
    {.raises: [StoreError].} =
  ## The values of a column (sport or sub_sport) among the activities of these
  ## users, with how many each has, most first; "none" for not recorded.
  guard:
    for row in st.db.fastRows(sql("select coalesce(a." & column & ", 'none'), count(*) " &
        "from activity a join file f on f.id = a.file_id where f.user_id in (" & idList &
        ") group by 1 order by 2 desc, 1")):
      try: result.add (row[0], parseInt(row[1]))
      except ValueError: raiseStore("bad number from the database")

proc checkNames(st: Store, what, column, idList: string, wanted: seq[string])
    {.raises: [StoreError].} =
  ## Refuse a sport (or sub-sport) the users' activities do not have, and say which
  ## they do have.
  if wanted.len == 0: return
  let have = present(st, column, idList)
  for w in wanted:
    if have.allIt(it[0] != w):
      var shown: seq[string]
      for (name, n) in have: shown.add name & " " & $n
      raiseStore("no activity of those users has the " & what & " '" & w & "' (they have: " &
        (if shown.len > 0: shown.join(", ") else: "no activities") & ")")

func rowColumns(verbose: bool, userId: UserId): string =
  ## What a row of the listing is made of (see table.nim); not recorded: -1 and ''.
  ## The path of the file (for `verbose`) is where it was last seen, else its name.
  "a.start_t as start_t, coalesce(a.sport, '') as sport, " &
    "coalesce(a.sub_sport, '') as sub, coalesce(a.distance_m, -1) as dist, " &
    "coalesce(a.timer_s, -1) as active, f.name as file, " &
    "(select name from user where id = f.user_id) as user, " &
    # whether the user has it in their selection
    "a.id in (select activity_id from selection where user_id = " & $userId & ") as chosen, " &
    (if verbose: "coalesce((select min(path) from seen_file where file_id = f.id), f.name) as path, "
     else: "f.name as path, ") &
    # where it started and what it is called (text made when it was imported: see names/activity.nim): in every listing
    "coalesce(a.start_place, '') as pname, coalesce(a.name, '') as aname, " &
    # whether it has a start (said "no GPS" if not): -v only
    (if verbose: "coalesce(ST_Y(a.start), '') as slat, coalesce(ST_X(a.start), '') as slon"
     else: "'' as slat, '' as slon")

const rowFields = "start_t, sport, sub, dist, active, file, user, chosen, path, pname, aname, slat, slon"
  ## the columns of a row, in the order `readRows` reads them

proc readRows(st: Store, query: string): seq[ListRow] {.raises: [StoreError].} =
  ## The rows a query gives (the columns `rowFields`), as listed.
  guard:
    for r in st.db.fastRows(sql(query)):
      try:
        let dist = parseFloat(r[3])
        let active = parseFloat(r[4])
        result.add ListRow(startT: UnixTime(parseBiggestInt(r[0])), sport: r[1], subSport: r[2],
                           distanceM: if dist >= 0: some(dist) else: none(float),
                           activeS: if active >= 0: some(active) else: none(float),
                           file: r[5], user: r[6], selected: r[7] == "1", path: r[8],
                           place: r[9], name: r[10],
                           position: positionText(r[11], r[12]))
      except ValueError:
        raiseStore("bad number from the database")

func moreThanOneUser(rows: seq[ListRow]): bool =
  rows.anyIt(it.user != rows[0].user)

proc listing(rows: seq[ListRow], zone: Timezone, c: Criteria, screen: Screen,
             choices: Option[int]): seq[Line] =
  ## The table (or the calendar) and its last line.
  result = if c.calendar: calendarLines(rows, zone, c.verbose, screen)
           else: table(rows, zone, rows.len > 0 and moreThanOneUser(rows), c.verbose)
  result.add footerLine(rows, choices, if c.calendar: selectedColour else: yellow)

proc skippedWarning(rows: seq[ListRow], zone: Timezone, c: Criteria): seq[Line] =
  ## The last line of a calendar of the months with data, if it left some out.
  if not c.calendar or c.verbose: return
  let n = skippedMonths(rows, zone)
  if n > 0:
    result.add @[span("warning: " & $n & (if n == 1: " month" else: " months") &
      " with no activity not shown, at the yellow month names; use --verbose to show them", yellow)]

proc showSelection*(st: Store, c: Criteria, zone: Timezone, screen = Screen(colour: true)): seq[Line]
    {.raises: [StoreError].} =
  ## The stored selection of the store's user, as a listing.
  let rows = readRows(st, "select " & rowColumns(c.verbose, st.userId) & " from selection s join activity a on " &
    "a.id = s.activity_id join file f on f.id = a.file_id where s.user_id = " & $st.userId &
    " order by a.start_t, a.id")
  if rows.len == 0: return @[plain("selection: empty")]
  result = listing(rows, zone, c, screen, none(int))
  result.add skippedWarning(rows, zone, c)

proc latestAmong(st: Store, match: string): Option[tuple[id: ActivityId, row: ListRow]]
    {.raises: [StoreError].} =
  ## The newest activity of those a query finds (one giving `id` and the row columns).
  let ordered = " from (" & match & ") order by start_t desc, id desc limit 1"
  let rows = readRows(st, "select " & rowFields & ordered)
  if rows.len == 0: return none(tuple[id: ActivityId, row: ListRow])
  guard:
    try:
      result = some((id: ActivityId(parseBiggestInt(st.db.getValue(sql("select id" & ordered)))), row: rows[0]))
    except ValueError:
      raiseStore("bad number from the database")

proc previousSelected(st: Store): tuple[id: ActivityId, row: ListRow] {.raises: [StoreError].} =
  ## The one activity of the stored selection (what `previous` means).  An error unless
  ## there is exactly one.
  let n = number(st, "select count(*) from selection where user_id = " & $st.userId)
  if n != 1:
    raiseStore("`previous` needs a selection of exactly one activity, and it has " & $n &
               " (see `nch list --show`)")
  let rows = readRows(st, "select " & rowColumns(false, st.userId) & " from selection s join activity a " &
    "on a.id = s.activity_id join file f on f.id = a.file_id where s.user_id = " & $st.userId)
  guard:
    try:
      result = (id: ActivityId(parseBiggestInt(st.db.getValue(
        sql"select activity_id from selection where user_id = ?", st.userId))), row: rows[0])
    except ValueError:
      raiseStore("bad number from the database")

proc resolve(st: Store, c: var Criteria, which: Reference, id: ActivityId, row: ListRow,
             centre: var Option[(float, float)], source: var string)
    {.raises: [StoreError].} =
  ## Replace the criteria measured against `which` by what they mean for this activity.
  let nameOf = if which == refLatest: "latest" else: "previous"
  if c.sportRef == which:
    c.sports.add (if row.sport.len > 0: row.sport else: "none")
    c.sportRef = refNone
  if c.subSportRef == which:
    c.subSports.add (if row.subSport.len > 0: row.subSport else: "none")
    c.subSportRef = refNone
  if c.nameRef == which or c.startRef == which:
    # the name and the start place of that activity, whole (they are not in the row unless it was listed with -v)
    var name, start: string
    guard:
      let r = st.db.getRow(sql"select coalesce(name, ''), coalesce(start_place, '') from activity where id = ?", id)
      name = r[0]
      start = r[1]
    if c.nameRef == which:
      c.namesExact.add name
      c.nameRef = refNone
    if c.startRef == which:
      c.startsExact.add start
      c.startRef = refNone
  if c.distanceRel.isSome and c.distanceRel.get.refers == which:
    if row.distanceM.isNone: raiseStore("the " & nameOf & " activity has no recorded distance")
    c.distanceM = around(row.distanceM.get, c.distanceRel.get.tol)
    c.distanceRel = none(Relative)
  if c.activeRel.isSome and c.activeRel.get.refers == which:
    if row.activeS.isNone: raiseStore("the " & nameOf & " activity has no recorded active time")
    c.activeS = around(row.activeS.get, c.activeRel.get.tol)
    c.activeRel = none(Relative)
  if c.near == (if which == refLatest: nkLatest else: nkPrevious):
    centre = startOf(st, id)
    if centre.isNone: raiseStore("the " & nameOf & " activity has no start position (--near " & nameOf & ")")
    source = "the start of the " & nameOf & " activity"
    c.near = nkNone

proc listActivities*(st: Store, criteria: Criteria, zone: Timezone,
                     screen = Screen(colour: true)): tuple[lines: seq[Line], saved: int]
    {.raises: [StoreError].} =
  ## List the activities that meet the criteria (and keep them as the selection if
  ## asked); `saved` is how many were kept, -1 if not asked.
  ##
  ## `previous` (in --near, --distance, --active, --sport, --sub-sport) is the one activity
  ## that was selected before; `latest` is the newest activity among those that meet the
  ## criteria that do not mention `latest`.  `previous` is found first, so a criterion that
  ## uses it is one of those among which `latest` is found.
  var c = criteria
  var userIds: seq[UserId]
  if c.users.len == 0:
    userIds.add st.userId
  else:
    for name in c.users:
      let id = userIdOf(st, name)
      if id notin userIds: userIds.add id
  var ids: seq[string]
  for id in userIds: ids.add $id
  let idList = ids.join(", ")
  if c.climbs.len > 0:
    # the climbs whose name as shown ("Farellones (2/3)", retired ones too) holds the text, whatever its case and accents
    let shown = shownNames(st)
    for t in c.climbs:
      var found = false
      for id, name in shown:
        if foldText(name).contains(foldText(t)):
          found = true
          if id notin c.climbIds: c.climbIds.add id
      if not found:
        raiseStore("no climb has '" & t & "' in its name (`nch climbs --all` lists them)")
  checkNames(st, "sport", "sport", idList, c.sports)
  checkNames(st, "sub-sport", "sub_sport", idList, c.subSports)
  var centre = none((float, float))
  var centreFrom = ""
  if usesPrevious(c):
    let prev = previousSelected(st)
    result.lines.add plain("previous: " & activityText(prev.row, zone))
    resolve(st, c, refPrevious, prev.id, prev.row, centre, centreFrom)
  if usesLatest(c):
    let base = withoutLatest(c)
    let found = latestAmong(st, matchSql(userIds, base, none((float, float)),
                                         "a.id as id, " & rowColumns(false, st.userId)))
    if found.isNone:
      raiseStore("`latest` is the newest activity that meets the other criteria, and none does")
    result.lines.add plain("latest: " & activityText(found.get.row, zone))
    resolve(st, c, refLatest, found.get.id, found.get.row, centre, centreFrom)
  if c.near == nkPoint:
    centre = some((c.lat, c.lon))
  if centre.isSome:
    result.lines.add plain("near " & formatFloat(centre.get[0], ffDecimal, 4) & "," &
      formatFloat(centre.get[1], ffDecimal, 4) &
      (if centreFrom.len > 0: " (" & centreFrom & ")" else: "") &
      ", within " & radiusText(c.radiusKm) & "km")
  let match = matchSql(userIds, c, centre, "a.id as id, " & rowColumns(c.verbose, st.userId))
  if c.save:
    st.begin()
    var committed = false
    try:
      guard:
        st.db.exec(sql"delete from selection where user_id = ?", st.userId)
        st.db.exec(sql(saveSql(st.userId, match)))
      st.commit()
      committed = true
    finally:
      if not committed: st.rollback()
  let rows = readRows(st, "select " & rowFields & " from (" & match & ") order by start_t, id")
  let total = number(st, "select count(*) from activity a join file f on f.id = a.file_id " &
    "where f.user_id in (" & idList & ")")
  result.lines.add listing(rows, zone, c, screen, some(total))
  result.saved = if c.save: rows.len else: -1
  if c.save:
    result.lines.add @[span("saved " & $rows.len & (if rows.len == 1: " activity" else: " activities") &
      " as the selection", leSaved)]
  result.lines.add skippedWarning(rows, zone, c)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch list ARGS`; returns the exit status.
  let zone = local()
  let parsed = parseArgs(args, zone)
  if parsed.help:
    stdout.say usage
    return exitOk
  if parsed.problem.len > 0:
    return usageError("nch list", usage, parsed.problem)
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch list", e.msg)
  try:
    var lines: seq[Line]
    let colour = canColourStdout()
    let screen = Screen(colour: colour, width: if isatty(stdout): terminalWidth() else: 0)
    if parsed.criteria.show:
      lines = showSelection(st, parsed.criteria, zone, screen)
    else:
      let r = listActivities(st, parsed.criteria, zone, screen)
      lines = r.lines
      if r.saved >= 0:
        g.log.log(lvInfo, "list", leSaved, $r.saved & (if r.saved == 1: " activity" else: " activities"))
    for l in lines: stdout.say render(l, colour) & "\n"
    exitOk
  except StoreError as e:
    failure("nch list", e.msg)
