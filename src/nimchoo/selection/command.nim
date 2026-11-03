## `nch list`: the activities that meet some criteria, and (with `--save`) the
## choice of those as "the selection", which other commands (heatmap ...) work on.
## The selection is kept in the database (table `selection`), for the current user,
## and replaced whenever `--save` is given; `--show` shows it.  What is listed is
## what is saved.
##
## This module is newer than `importer` and reads its tables (activity, file,
## coords, route) directly.

import std/[options, strutils, times]
import db_connector/db_sqlite
import ../cli/common
import ../db/store
import ../errors
import ./criteria

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] list [CRITERIA] [--save]
       nch [--db PATH] [--user NAME] list --show

List the activities that meet the criteria (all of them if there are none), and
with --save keep them as the "selection" that other commands use (replacing the
last one).  Criteria are combined with "and".

  --users A B C      whose activities (default: the current user)
  --from TIME        activities that start at or after TIME
  --to TIME          activities that start before the end of TIME
                     (TIME is in your time zone: 2018-08-27, 2018-08-27T09:30 or
                     with seconds; a --to date means the whole day)
  --near LAT,LON     activities whose route passes within the radius of the point
  --near latest      ... of the centre of the latest activity of the users
  --radius KM        radius for --near in kilometres (default: 100); on its own it
                     means --near latest
  --newest N         only the N newest of the activities that meet the other criteria
  --oldest N         only the N oldest of them
  --latest           the same as --newest 1
  --save             make what is listed the selection
  --show             show the selection (no criteria allowed)
  -h, --help         show this help
"""

proc localDate(t: int64): string =
  ## The date in the user's time zone.
  let d = fromUnix(t).local
  d.year.intToStr(4) & "-" & ord(d.month).intToStr(2) & "-" & d.monthday.intToStr(2)

func km(x: float): string =
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

proc range(st: Store): string {.raises: [StoreError].} =
  ## ", 2018-03-01 to 2018-09-30" for the selection of the store's user.
  guard:
    let r = st.db.getRow(sql"""select min(a.start_t), max(a.start_t)
      from selection s join activity a on a.id = s.activity_id where s.user_id = ?""",
      st.userId)
    try:
      result = ", " & localDate(parseBiggestInt(r[0])) & " to " &
               localDate(parseBiggestInt(r[1]))
    except ValueError:
      discard

proc latestCentre(st: Store, ids: string): tuple[centre: Option[(float, float)], day: string]
    {.raises: [StoreError].} =
  ## The middle of the box around the route of the latest activity of these users.
  guard:
    let a = st.db.getRow(sql("""select a.id, a.start_t from activity a join file f
      on f.id = a.file_id where f.user_id in (""" & ids & ") order by a.start_t desc limit 1"))
    if a[0].len == 0: return
    let c = st.db.getRow(sql"""select (min(lon) + max(lon)) / 2, (min(lat) + max(lat)) / 2
      from coords where activity_id = ?""", a[0])
    try:
      if c[0].len > 0:
        result = (some((parseFloat(c[1]), parseFloat(c[0]))), localDate(parseBiggestInt(a[1])))
    except ValueError:
      discard

proc show(st: Store): string {.raises: [StoreError].} =
  let n = number(st, "select count(*) from selection where user_id = " & $st.userId)
  if n == 0: "selection: empty"
  else: "selection: " & $n & (if n == 1: " activity" else: " activities") & range(st)

proc matchStats(st: Store, match: string): tuple[n: int, first, last: int64]
    {.raises: [StoreError].} =
  ## How many activities a query (giving `start_t`) finds, and when the first and
  ## the last started.
  guard:
    let r = st.db.getRow(sql("select count(*), coalesce(min(start_t), 0), " &
      "coalesce(max(start_t), 0) from (" & match & ")"))
    try:
      result = (parseInt(r[0]), parseBiggestInt(r[1]), parseBiggestInt(r[2]))
    except ValueError:
      raiseStore("bad number from the database")

proc choose(st: Store, c: Criteria): string {.raises: [StoreError].} =
  ## List (and, if asked, save); returns what to tell the user.
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
  var centre = none((float, float))
  var said = ""
  case c.near
  of nkNone: discard
  of nkPoint:
    centre = some((c.lat, c.lon))
    said = "near " & formatFloat(c.lat, ffDecimal, 4) & "," & formatFloat(c.lon, ffDecimal, 4)
  of nkLatest:
    let l = latestCentre(st, idList)
    if l.centre.isNone:
      raiseStore("--near latest: the users have no activity with a position")
    centre = l.centre
    said = "near " & formatFloat(l.centre.get[0], ffDecimal, 4) & "," &
      formatFloat(l.centre.get[1], ffDecimal, 4) & " (the centre of the latest activity, " &
      l.day & ")"
  if said.len > 0: said.add ", within " & km(c.radiusKm) & " km\n"
  let match = matchSql(userIds, c, centre, "a.id as id, a.start_t as start_t")
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
  let found = matchStats(st, match)
  let total = number(st, "select count(*) from activity a join file f on f.id = a.file_id " &
    "where f.user_id in (" & idList & ")")
  let span = if found.n > 0: ", " & localDate(found.first) & " to " & localDate(found.last)
             else: ""
  said & (if c.save: "saved " else: "matched ") & $found.n & " of " & $total &
    (if total == 1: " activity" else: " activities") &
    (if c.save: " as the selection" else: "") & span

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch list ARGS`; returns the exit status.
  let parsed = parseArgs(args, local())
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
    let text = if parsed.criteria.show: show(st) else: choose(st, parsed.criteria)
    stdout.say text & "\n"
    exitOk
  except StoreError as e:
    failure("nch list", e.msg)
