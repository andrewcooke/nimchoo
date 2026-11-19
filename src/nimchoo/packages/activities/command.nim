## `nch activities`: the activities, and the selection.  With no criteria it shows the selection, the activities that
## the commands which work on activities (climbs, map, delete ...) use by default; with criteria or `--all` it
## searches all the activities, and `--select` keeps what is listed as the selection.  The selection is kept in the
## database (table `selection`), for the current user, and replaced whenever `--select` is given.
##
## This module is newer than `importer` and reads its tables (activity, file, coords, route) directly.

import std/[options, sequtils, strformat, strutils, tables, times]
import ./cmdname
export cmdname
import ../../core/[extension, globals]
import ../db/statement
import ../importer/naming
import ../geo/position
import ../names/[open, places]
import ../selection/selection
import ../db/store
import ./deleterun as deleteRun
import ../../core/errors
import ../../core/logfile
import ../ui/live
import ../ui/style
import ../ui/vocabulary
import ../util/args/[args, usage]
import ./[rows, table]
import ./criteria
import ../text/fold/fold
import ../user/session

{.push raises: [].}

const
  synopsis =
    """usage: nch [--db PATH] [--user NAME] activities [CRITERIA] [--select] [-v]
       nch [--db PATH] [--user NAME] activities --all [--select]
       nch [--db PATH] [--user NAME] activities [CRITERIA | --all] --delete -f"""
  # (the prose is wrapped to the window by `prose`: its line breaks are the source's only)
  intro =
    """Show the activities of the selection: the ones that other commands (climbs, map ...) use unless they are
told otherwise.  With criteria (or `--all`) all the activities are searched instead, those that meet the criteria
(combined with "and") are shown, and with `--select` they become the selection (replacing the last one)."""
  notes =
    """"latest" is the newest activity among those that meet the criteria that do not use
"latest": so `--sports cycling --distance latest~10%` is cycling rides within 10% of
the length of your latest cycling ride.  (`--latest`, the flag, is `--newest 1`.)

"previous" is the one activity that was selected before (`nch activities` shows it): select it
with `--select`, then `--sports previous --distance previous~10%` finds rides like it.  It is an
error unless exactly one activity is selected."""

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch activities`, described (for tab completion).
  criteriaSpec(g.extensions.get(activityCriterion)).docs

proc usageText*(width: int, offered: seq[Criterion] = @[]): seq[Line] =
  ## The usage: the synopsis, the introduction, the options (made from their descriptions) and the notes, all wrapped to
  ## `width` (the synopsis lines are not).
  usageOf(
    synopsisLines(synopsis),
    proseLines(intro, width),
    optionLines(criteriaSpec(offered).docs, width),
    proseLines(notes, width),
  )

func radiusText(x: float): string =
  ## 100.0 -> "100", 2.5 -> "2.5"
  let t = $x
  if t.endsWith(".0"):
    t[0 ..< t.len - 2]
  else:
    t

proc startOf(
    st: Store, activityId: ActivityId
): Option[(float, float)] {.raises: [StoreError].} =
  ## Where an activity started (latitude, longitude); none if it has no positions.
  let c = st.db.scalar(
    tuple[lat, lon: Option[float]],
    "select ST_Y(start), ST_X(start) from activity where id = :id",
    id = activityId,
  )
  if c.lat.isSome and c.lon.isSome:
    result = some((c.lat.get, c.lon.get))

proc present(st: Session, column: string): seq[(string, int)] {.raises: [StoreError].} =
  ## The values of a column (sport or sub_sport: a name of ours, which cannot be bound) among the activities of
  ## the user, with how many each has, most first; "none" for not recorded.
  st.db.query(
    (string, int),
    "select coalesce(a." & column & ", 'none'), count(*) " &
      "from activity a join file f on f.id = a.file_id where f.user_id = :userId " &
      "group by 1 order by 2 desc, 1",
    userId = st.userId,
  )

proc checkNames(
    st: Session, what, column: string, wanted: seq[string]
) {.raises: [StoreError].} =
  ## Refuse a sport (or sub-sport) the users' activities do not have, and say which
  ## they do have.
  if wanted.len == 0:
    return
  let have = present(st, column)
  for w in wanted:
    if have.allIt(it[0] != w):
      var shown: seq[string]
      for (name, n) in have:
        shown.add name & " " & $n
      raiseStore(
        "no activity of those users has the " & what & " '" & w & "' (they have: " &
          (if shown.len > 0: shown.join(", ") else: "no activities") & ")"
      )

proc listing(
    rows: seq[ListRow],
    zone: Timezone,
    c: Criteria,
    choices: Option[int],
    saved = none(int),
    marks = false,
): seq[Line] =
  ## The table and its last line (`marks`: the selection in brackets, where there is no colour).
  result = table(rows, zone, c.verbose, marks)
  result.add footerLine(rows, choices, selectedStyle, saved)

proc showSelection*(
    st: Session, c: Criteria, zone: Timezone, marks = false
): seq[Line] {.raises: [StoreError].} =
  ## The stored selection of the store's user, as a listing.
  let rows = selectionRows(st, c.verbose)
  if rows.len == 0:
    return @[
      plain(
        "nothing is selected: `nch activities --all` lists every activity; with criteria and `--select` some are chosen"
      )
    ]
  result = listing(rows, zone, c, none(int), marks = marks)

proc latestAmong(
    st: Store, match: Sql
): Option[tuple[id: ActivityId, row: ListRow]] {.raises: [StoreError].} =
  ## The newest activity of those a query finds (one giving `id` and the row columns).
  let ordered = " from (" & match & ") order by start_t desc, id desc limit 1"
  let rows = readRows(st, "select " & rowFields & ordered)
  if rows.len == 0:
    return none(tuple[id: ActivityId, row: ListRow])
  some((id: st.db.scalar(ActivityId, "select id" & ordered), row: rows[0]))

proc previousSelected(
    st: Session
): tuple[id: ActivityId, row: ListRow] {.raises: [StoreError].} =
  ## The one activity of the stored selection (what `previous` means).  An error unless
  ## there is exactly one.
  let n = st.db.scalar(
    int, "select count(*) from selection where user_id = :userId", userId = st.userId
  )
  if n != 1:
    raiseStore(
      "`previous` needs a selection of exactly one activity, and it has " & $n &
        " (see `nch activities`)"
    )
  let rows = readRows(
    st,
    "select " & rowColumns(false, st.userId) & " from selection s join activity a " &
      "on a.id = s.activity_id join file f on f.id = a.file_id where s.user_id = :owner".sqlOf.with(
        "owner", st.userId
      ),
  )
  (
    id: st.db.scalar(
      ActivityId,
      "select activity_id from selection where user_id = :userId",
      userId = st.userId,
    ),
    row: rows[0],
  )

proc resolve(
    st: Store,
    c: var Criteria,
    which: Reference,
    id: ActivityId,
    row: ListRow,
    points: var Points,
    sources: var tuple[start, passes: string],
) {.raises: [StoreError].} =
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
    let r = st.db.scalar(
      tuple[name, start: string],
      "select coalesce(name, ''), coalesce(start_place, '') from activity where id = :id",
      id = id,
    )
    let name = r.name
    let start = r.start
    if c.nameRef == which:
      c.namesExact.add name
      c.nameRef = refNone
    if c.startRef == which:
      c.startsExact.add start
      c.startRef = refNone
  if c.distanceRel.isSome and c.distanceRel.get.refers == which:
    if row.distanceM.isNone:
      raiseStore("the " & nameOf & " activity has no recorded distance")
    c.distanceM = around(row.distanceM.get, c.distanceRel.get.tol)
    c.distanceRel = none(Relative)
  if c.activeRel.isSome and c.activeRel.get.refers == which:
    if row.activeS.isNone:
      raiseStore("the " & nameOf & " activity has no recorded active time")
    c.activeS = around(row.activeS.get, c.activeRel.get.tol)
    c.activeRel = none(Relative)
  let refers = if which == refLatest: nkLatest else: nkPrevious
  if c.start.kind == refers or c.passes.kind == refers:
    let at = startOf(st, id)
    if at.isNone:
      raiseStore(fmt"the {nameOf} activity has no start position (to measure from)")
    let said = fmt"the start of the {nameOf} activity"
    if c.start.kind == refers:
      (points.start, sources.start, c.start) = (at, said, Spot())
    if c.passes.kind == refers:
      (points.passes, sources.passes, c.passes) = (at, said, Spot())

proc numbersAsIds(
    st: Session, c: var Criteria, notes: var seq[Line]
) {.raises: [StoreError].} =
  ## A whole number in `--names` that no activity's name holds is the number of an activity (`--names 737`): a name that
  ## has the digits wins, so a number can always be searched for as text by being in a name.  A note says which it was.
  var texts: seq[string]
  for t in c.names:
    var n: int
    let whole =
      t.len > 0 and t.allIt(it in {'0' .. '9'}) and parseIntIn(t, 1, high(int), n)
    if whole and
        st.db.scalar(
          int,
          "select count(*) from activity a join file f on f.id = a.file_id where f.user_id = :owner and instr(fold(a.name), :typed) > 0",
          owner = st.userId,
          typed = foldText(t),
        ) == 0 and
        st.db.scalar(
          int,
          "select count(*) from activity a join file f on f.id = a.file_id where f.user_id = :owner and a.id = :id",
          owner = st.userId,
          id = n,
        ) > 0:
      c.nameIds.add int64(n)
      notes.add plain(fmt"no activity name has '{t}': using activity {n}")
    else:
      texts.add t
  c.names = texts

type Resolved = object
  ## The criteria with `latest` and `previous` worked out, the conditions of the criteria other packages offer, and the
  ## notes that say which activities they came to.
  c: Criteria
  extra: Sql ## the offered criteria, each " and (...)"
  points: Points ## where --from and --near came to
  notes: seq[Line]

proc resolveCriteria(
    st: Session, criteria: Criteria, zone: Timezone
): Resolved {.raises: [StoreError].} =
  ## `previous` (in --from, --near, --distance, --active, --sports, --sub-sports) is the one activity
  ## that was selected before; `latest` is the newest activity among those that meet the
  ## criteria that do not mention `latest`.  `previous` is found first, so a criterion that
  ## uses it is one of those among which `latest` is found.
  var c = criteria
  let userIds = @[st.userId]
  var extra = Sql()
  for o in c.contributed:
    let r = o.resolve(st, o.values)
    extra = extra & sqlOf(" and (") & r.condition & sqlOf(")")
    for n in r.notes:
      if n.len > 0:
        result.notes.add plain(n)
  numbersAsIds(st, c, result.notes)
  checkNames(st, "sport", "sport", c.sports)
  checkNames(st, "sub-sport", "sub_sport", c.subSports)
  var points: Points
  var sources: tuple[start, passes: string]
  if usesPrevious(c):
    let prev = previousSelected(st)
    result.notes.add plain("previous: " & activityText(prev.row, zone))
    resolve(st, c, refPrevious, prev.id, prev.row, points, sources)
  if usesLatest(c):
    let base = withoutLatest(c)
    let found = latestAmong(
      st,
      matchSql(
        userIds,
        base,
        Points(),
        sqlOf("a.id as id, ") & rowColumns(false, st.userId),
        extra,
      ),
    )
    if found.isNone:
      raiseStore(
        "`latest` is the newest activity that meets the other criteria, and none does"
      )
    result.notes.add plain("latest: " & activityText(found.get.row, zone))
    resolve(st, c, refLatest, found.get.id, found.get.row, points, sources)
  for (spot, at, said) in [
    (addr c.start, addr points.start, addr sources.start),
    (addr c.passes, addr points.passes, addr sources.passes),
  ]:
    case spot[].kind
    of nkPoint:
      at[] = some((spot[].lat, spot[].lon))
    of nkPlace:
      let p = placeNamed(st, spot[].place)
      at[] = some((p.lat, p.lon))
      said[] = p.said
    of nkNone, nkLatest, nkPrevious:
      discard # (latest and previous are worked out above)
  for (what, at, said, km) in [
    ("starting near", points.start, sources.start, c.startKm),
    ("passing near", points.passes, sources.passes, c.passKm),
  ]:
    if at.isSome:
      let where = positionText((lon: at.get[1], lat: at.get[0]))
      let why =
        if said.len > 0:
          fmt" ({said})"
        else:
          ""
      result.notes.add plain(fmt"{what} {where}{why}, within {radiusText(km)}km")
  result.c = c
  result.extra = extra
  result.points = points

proc matchingIds*(
    st: Session, criteria: Criteria, zone: Timezone
): tuple[ids: seq[int64], notes: seq[Line]] {.raises: [StoreError].} =
  ## The ids of the current user's activities the criteria mean: the selection if there are no criteria and no `--all`,
  ## else the activities found among all of them.  (And the notes that say which activity `latest` or `previous` was.)
  var query: Sql
  if not (criteria.all or criteria.given):
    query = sqlOf("select activity_id from selection where user_id = :owner").with(
        "owner", st.userId
      )
  else:
    let r = resolveCriteria(st, criteria, zone)
    result.notes = r.notes
    query =
      "select id from (" &
      matchSql(@[st.userId], r.c, r.points, sqlOf("a.id as id"), r.extra) & ")"
  result.ids = st.db.query(int64, query & " order by 1")

proc listActivities*(
    st: Session, criteria: Criteria, zone: Timezone, marks = false
): tuple[lines: seq[Line], saved: int] {.raises: [StoreError].} =
  ## List the activities that meet the criteria, or the selection if there are none (and keep them as the selection if
  ## asked); `saved` is how many were kept, -1 if not asked.
  if not (criteria.all or criteria.given):
    # no criteria: the selection
    result.lines = showSelection(st, criteria, zone, marks)
    result.saved = -1
    return
  let r = resolveCriteria(st, criteria, zone)
  let c = r.c
  result.lines = r.notes
  let match = matchSql(
    @[st.userId],
    c,
    r.points,
    sqlOf("a.id as id, ") & rowColumns(c.verbose, st.userId),
    r.extra,
  )
  if c.select:
    st.replaceSelection(st.db.query(int64, sqlOf("select id from (") & match & ")"))
  var rows =
    readRows(st, "select " & rowFields & " from (" & match & ") order by start_t, id")
  if not (c.select or c.all):
    # the select style is the selection after this command: criteria without --select change nothing, so nothing listed is in it (with
    # --select everything listed is; with --all, the activities that are selected among them all)
    for r in rows.mitems:
      r.selected = false
  let total = st.db.scalar(
    int,
    "select count(*) from activity a join file f on f.id = a.file_id where f.user_id = :userId",
    userId = st.userId,
  )
  result.lines.add listing(
    rows, zone, c, some(total), (if c.select: some(rows.len) else: none(int)), marks
  )
  result.saved = if c.select: rows.len else: -1

proc renameActivities(g: Globals, st: Session, ids: seq[int64]): int {.raises: [].} =
  ## `--rename`: forget the names of the activities and make them again, as an import does.
  let names = openNames(
    g,
    st,
    commandName,
    proc(line: string) {.closure, raises: [].} =
      g.say osErr, line & "\n"
    ,
  )
  if names.isNone:
    return failure(
      g, "nch activities",
      "no place for the cache, where the names are kept: set NCH_CACHE or HOME",
    )
  try:
    st.forgetNames(ids)
    let n = ensureActivityNames(st, names.get)
    let left =
      if n.left > 0:
        fmt"; {n.leftText}"
      else:
        ""
    g.say osOut,
      fmt"named {n.total} activities again: {n.named} with a name, {n.startOnly} with only a start place, {n.nothing} with neither{left}" &
        "\n"
    exitOk
  except StoreError, DownloadError:
    failure(
      g,
      "nch activities",
      getCurrentExceptionMsg() &
        " (the names not made are made by the next `nch import`)",
    )

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch activities ARGS`; returns the exit status.
  let zone = local()
  let offered = g.extensions.get(activityCriterion)
  let parsed = parseArgs(args, zone, offered)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(helpWidth(stdout), offered)
    return exitOk
  of pkProblem:
    return usageError(
      g, "nch activities", usageText(helpWidth(stderr), offered), parsed.problem
    )
  of pkOk:
    discard
  let criteria = parsed.params
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure(g, "nch activities", e.msg)
  try:
    if criteria.delete:
      let m = matchingIds(st, criteria, zone)
      for l in m.notes:
        g.say osOut, l.text & "\n"
      let searched = criteria.all or criteria.given
      return runDelete(
        g,
        st,
        m.ids,
        criteria.force,
        if searched:
          "no activity meets the criteria: nothing to delete"
        else:
          "nothing is selected: `nch activities CRITERIA --select` chooses activities, or give criteria or `--all`",
      )
    if criteria.rename:
      let m = matchingIds(st, criteria, zone)
      for l in m.notes:
        g.say osOut, l.text & "\n"
      if m.ids.len == 0:
        return failure(
          g,
          "nch activities",
          if criteria.all or criteria.given:
            "no activity meets the criteria: nothing to rename"
          else:
            "nothing is selected: `nch activities CRITERIA --select` chooses activities, or give criteria or `--all`",
        )
      return renameActivities(g, st, m.ids)
    let paint = paintOf(g, osOut)
    let r = listActivities(st, criteria, zone, not paint.colour)
    if r.saved >= 0:
      g.log.log(
        lvInfo,
        commandName,
        leSaved,
        $r.saved & (if r.saved == 1: " activity" else: " activities"),
      )
    for l in r.lines:
      g.sayRendered osOut, render(l, paint) & "\n"
    exitOk
  except StoreError as e:
    failure(g, "nch activities", e.msg)
