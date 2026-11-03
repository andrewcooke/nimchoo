## `nch list`: the activities that meet some criteria, and (with `--save`) the
## choice of those as "the selection", which other commands (heatmap ...) work on.
## The selection is kept in the database (table `selection`), for the current user,
## and replaced whenever `--save` is given; `--show` shows it.  What is listed is
## what is saved.
##
## This module is newer than `importer` and reads its tables (activity, file,
## coords, route) directly.

import std/[options, sequtils, strutils, times]
import db_connector/db_sqlite
import ../cli/common
import ../db/store
import ../errors
import ../ui/[live, logfile, style, vocabulary]
import ./[criteria, table]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] list [CRITERIA] [--save]
       nch [--db PATH] [--user NAME] list --show

List the activities that meet the criteria (all of them if there are none), and
with --save keep them as the "selection" that other commands use (replacing the
last one).  Criteria are combined with "and".

  --users A B C      whose activities (default: the current user)
  --sport A B        only these sports (cycling, running, swimming ...); "none"
                     means not recorded; "latest" the sport of the latest activity
  --sub-sport A B    only these sub-sports (road, trail, open_water ...).  Many
                     files say "generic" or nothing, so this misses some rides
  --distance RANGE   distance in km: 40- (40 or more), 10-50, -5 (up to 5);
                     0.5- for half a km; 42~2 (between 40 and 44), latest~10%
  --active RANGE     active time: 1h-, 30m-2h, -45m (units d h m s, as printed);
                     2h~15m, latest~10%
  --from TIME        activities that start at or after TIME
  --to TIME          activities that start before the end of TIME
                     (TIME is in your time zone: 2018-08-27, 2018-08-27T09:30 or
                     with seconds; a --to date means the whole day)
  --near LAT,LON     activities whose route passes within the radius of the point
  --near latest      ... of the centre of the latest activity
  --radius KM        radius for --near in kilometres (default: 100); on its own it
                     means --near latest
  -n, --newest N     only the N newest of the activities that meet the other criteria
  --oldest N         only the N oldest of them
  --latest           the same as --newest 1
  --save             make what is listed the selection
  --show             show the selection (no criteria allowed)
  -v, --verbose      show more of each activity
  -h, --help         show this help

"latest" is the newest activity among those that meet the criteria that do not use
"latest": so  --sport cycling --distance latest~10%  is cycling rides within 10% of
the length of your latest cycling ride.  (--latest, the flag, is --newest 1.)
"""

proc localDate(t: int64): string =
  ## The date in the user's time zone.
  let d = fromUnix(t).local
  d.year.intToStr(4) & "-" & ord(d.month).intToStr(2) & "-" & d.monthday.intToStr(2)

func radiusText(x: float): string =
  ## 100.0 -> "100", 2.5 -> "2.5"
  let t = $x
  if t.endsWith(".0"): t[0 ..< t.len - 2] else: t

proc userIdOf(st: Store, name: string): int64 {.raises: [StoreError].} =
  guard:
    let v = st.db.getValue(sql"select id from user where name = ?", name)
    if v.len == 0: raiseStore("no such user: " & name)
    try: result = parseBiggestInt(v)
    except ValueError: raiseStore("bad user id " & v)

proc number(st: Store, query: string): int {.raises: [StoreError].} =
  guard:
    try: result = parseInt(st.db.getValue(sql(query)))
    except ValueError: raiseStore("bad number from the database")

proc centreOf(st: Store, activityId: int64): Option[(float, float)] {.raises: [StoreError].} =
  ## The middle of the box around the route of an activity; none if it has no positions.
  guard:
    let c = st.db.getRow(sql"""select (min(lon) + max(lon)) / 2, (min(lat) + max(lat)) / 2
      from coords where activity_id = ?""", activityId)
    try:
      if c[0].len > 0: result = some((parseFloat(c[1]), parseFloat(c[0])))
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

func rowColumns(verbose: bool): string =
  ## What a row of the listing is made of (see table.nim); not recorded: -1 and ''.
  ## The path of the file (for `verbose`) is where it was last seen, else its name.
  "a.start_t as start_t, coalesce(a.sport, '') as sport, " &
    "coalesce(a.sub_sport, '') as sub, coalesce(a.distance_m, -1) as dist, " &
    "coalesce(a.timer_s, -1) as active, f.name as file, " &
    "(select name from user where id = f.user_id) as user, " &
    (if verbose:
       "coalesce((select min(path) from seen_file where file_id = f.id), f.name) as path"
     else: "f.name as path")

proc readRows(st: Store, query: string): seq[ListRow] {.raises: [StoreError].} =
  ## The rows a query gives (start_t, sport, sub, dist, active, file, user, path), as listed.
  guard:
    for r in st.db.fastRows(sql(query)):
      try:
        let dist = parseFloat(r[3])
        let active = parseFloat(r[4])
        result.add ListRow(startT: parseBiggestInt(r[0]), sport: r[1], subSport: r[2],
                           distanceM: if dist >= 0: some(dist) else: none(float),
                           activeS: if active >= 0: some(active) else: none(float),
                           file: r[5], user: r[6], path: r[7])
      except ValueError:
        raiseStore("bad number from the database")

func moreThanOneUser(rows: seq[ListRow]): bool =
  rows.anyIt(it.user != rows[0].user)

proc listing(rows: seq[ListRow], zone: Timezone, verbose: bool, choices: Option[int]): seq[Line] =
  ## The table and its last line.
  result = table(rows, zone, rows.len > 0 and moreThanOneUser(rows), verbose)
  result.add plain(footer(rows, choices))

proc showSelection*(st: Store, c: Criteria, zone: Timezone): seq[Line]
    {.raises: [StoreError].} =
  ## The stored selection of the store's user, as a listing.
  let rows = readRows(st, "select " & rowColumns(c.verbose) & " from selection s join activity a on " &
    "a.id = s.activity_id join file f on f.id = a.file_id where s.user_id = " & $st.userId &
    " order by a.start_t, a.id")
  if rows.len == 0: return @[plain("selection: empty")]
  listing(rows, zone, c.verbose, none(int))

proc latestAmong(st: Store, match: string): Option[tuple[id: int64, row: ListRow]]
    {.raises: [StoreError].} =
  ## The newest activity of those a query finds (one giving `id` and the row columns).
  let ordered = " from (" & match & ") order by start_t desc, id desc limit 1"
  let rows = readRows(st, "select start_t, sport, sub, dist, active, file, user, path" & ordered)
  if rows.len == 0: return none(tuple[id: int64, row: ListRow])
  guard:
    try:
      result = some((id: parseBiggestInt(st.db.getValue(sql("select id" & ordered))), row: rows[0]))
    except ValueError:
      raiseStore("bad number from the database")

proc listActivities*(st: Store, criteria: Criteria, zone: Timezone): tuple[lines: seq[Line], saved: int]
    {.raises: [StoreError].} =
  ## List the activities that meet the criteria (and keep them as the selection if
  ## asked); `saved` is how many were kept, -1 if not asked.
  ##
  ## `latest` (in --near, --distance, --active, --sport, --sub-sport) is the newest
  ## activity among those that meet the criteria that do not mention `latest`.
  var c = criteria
  var userIds: seq[int64]
  if c.users.len == 0:
    userIds.add st.userId
  else:
    for name in c.users:
      let id = userIdOf(st, name)
      if id notin userIds: userIds.add id
  var ids: seq[string]
  for id in userIds: ids.add $id
  let idList = ids.join(", ")
  checkNames(st, "sport", "sport", idList, c.sports)
  checkNames(st, "sub-sport", "sub_sport", idList, c.subSports)
  var centre = none((float, float))
  if usesLatest(c):
    let base = withoutLatest(c)
    let found = latestAmong(st, matchSql(userIds, base, none((float, float)),
                                         "a.id as id, " & rowColumns(false)))
    if found.isNone:
      raiseStore("`latest` is the newest activity that meets the other criteria, and none does")
    let (refId, ref0) = (found.get.id, found.get.row)
    result.lines.add plain("latest: " & table(@[ref0], zone, false, false)[1].text.splitWhitespace.join(" "))
    if c.sportLatest: c.sports.add (if ref0.sport.len > 0: ref0.sport else: "none")
    if c.subSportLatest: c.subSports.add (if ref0.subSport.len > 0: ref0.subSport else: "none")
    if c.distanceLatest.isSome:
      if ref0.distanceM.isNone: raiseStore("the latest activity has no recorded distance")
      c.distanceM = around(ref0.distanceM.get, c.distanceLatest.get)
    if c.activeLatest.isSome:
      if ref0.activeS.isNone: raiseStore("the latest activity has no recorded active time")
      c.activeS = around(ref0.activeS.get, c.activeLatest.get)
    if c.near == nkLatest:
      centre = centreOf(st, refId)
      if centre.isNone: raiseStore("the latest activity has no positions (--near latest)")
  case c.near
  of nkNone, nkLatest: discard
  of nkPoint: centre = some((c.lat, c.lon))
  if centre.isSome:
    result.lines.add plain("near " & formatFloat(centre.get[0], ffDecimal, 4) & "," &
      formatFloat(centre.get[1], ffDecimal, 4) &
      (if c.near == nkLatest: " (the centre of the latest activity)" else: "") &
      ", within " & radiusText(c.radiusKm) & " km")
  let match = matchSql(userIds, c, centre, "a.id as id, " & rowColumns(c.verbose))
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
  let rows = readRows(st, "select start_t, sport, sub, dist, active, file, user, path from (" &
    match & ") order by start_t, id")
  let total = number(st, "select count(*) from activity a join file f on f.id = a.file_id " &
    "where f.user_id in (" & idList & ")")
  result.lines.add listing(rows, zone, c.verbose, some(total))
  result.saved = if c.save: rows.len else: -1
  if c.save:
    result.lines.add @[span("saved " & $rows.len & (if rows.len == 1: " activity" else: " activities") &
      " as the selection", leSaved)]

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
  defer: st.close()
  try:
    var lines: seq[Line]
    if parsed.criteria.show:
      lines = showSelection(st, parsed.criteria, zone)
    else:
      let r = listActivities(st, parsed.criteria, zone)
      lines = r.lines
      if r.saved >= 0:
        g.log.log(lvInfo, "list", leSaved, $r.saved & (if r.saved == 1: " activity" else: " activities"))
    let colour = canColourStdout()
    for l in lines: stdout.say render(l, colour) & "\n"
    exitOk
  except StoreError as e:
    failure("nch list", e.msg)
