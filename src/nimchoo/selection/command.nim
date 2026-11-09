## `nch activities`: the activities, and the selection.  With no criteria it shows the selection, the activities that
## the commands which work on activities (climbs, map, delete ...) use by default; with criteria or `--all` it
## searches all the activities, and `--select` keeps what is listed as the selection.  The selection is kept in the
## database (table `selection`), for the current user, and replaced whenever `--select` is given.
##
## This module is newer than `importer` and reads its tables (activity, file, coords, route) directly.

import std/[options, sequtils, strutils, tables, terminal, times]
import ../cli/catalog
import ../core/globals
import ../modules
import ../climbs/[display, report]
import ../packages/db/statement
import ../packages/db/store
import ../delete/run as deleteRun
import ../importer/batch
import ../importer/run as importRun
import ../core/errors
import ../packages/fit/time
import ../core/logfile
import ../packages/ui/live
import ../packages/ui/style
import ../packages/ui/vocabulary
import ../packages/text/fold/fold
import ./[calendar, criteria, table]

{.push raises: [].}

const usage* =
  """usage: nch [--db PATH] [--user NAME] activities [CRITERIA] [--select] [-v] [--calendar]
       nch [--db PATH] [--user NAME] activities --all [--select]
       nch [--db PATH] [--user NAME] activities [CRITERIA | --all] --delete -f
       nch [--db PATH] [--user NAME] activities --import [-q] [--slow] [-j N] PATH...

Show the activities of the selection: the ones that other commands (climbs, map ...) use unless they are
told otherwise.  With criteria (or --all) all the activities are searched instead, those that meet the criteria
(combined with "and") are shown, and with --select they become the selection (replacing the last one).

  --all              every activity, not just the selection
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
                     it) contains TEXT: --climb farellones (all of them), --climb farellones₂ (or "farellones 2")
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
  --select           make what is listed the selection (needs criteria or --all)
  --delete           delete the activities (with no criteria and no --all, those of the selection) and everything
                     made from them: coordinates, route, heart rate, impulses, efforts.  The climbs found in
                     them stay (they are shared), and so do the names on those.  The file of an activity is forgotten
                     as well: importing its folder again would bring the activity back.  Nothing is deleted without
                     -f (it says what it would delete); on a terminal there are then 5 seconds in which to press Ctrl-C
  -f, --force        really do it (with --delete)
  --import PATH...   put the activities in FIT files into the database.  Each PATH is a file, or a directory that is
                     searched (recursively) for *.fit files.  A file whose path, size and modification time are as when
                     it was last looked at is skipped without being read (this includes files that could not be
                     imported); a file that cannot be imported is reported and the others carry on.  What happened is
                     written to the log (see `nch log --help`).  The new activities are then named, from the places
                     they went through (the names are downloaded the first time they are needed).  The activities
                     added become your selection, ready for `nch climbs` or `nch map` (if nothing was added
                     the selection is left as it was).  It takes no criteria; it takes these:
    -q, --quiet      report only failures and the summary
    --slow           read and check every file, even those unchanged since last time (finds files that were moved or
                     copied; retries failures)
    -j, --jobs N     use N threads to read and decode the files (the database is written by one thread, in the order
                     of the files, so the result is the same); 1: no threads.  Default: the number of processors,
                     but not more than 8
  -v, --verbose      show more of each activity: where it started (its coordinates, or
                     "no GPS" if the file has no positions), the place it started and its name
                     (made when it was imported), and the path of its file
  --calendar         show the activities on a calendar instead of a table: a row for each month
                     that has one (with -v, every month from the first to the last), the days
                     in columns by weekday (weeks start on Monday).  White: an activity that was
                     listed; blue: one that is also in the selection; grey: none
  -h, --help         show this help

"latest" is the newest activity among those that meet the criteria that do not use
"latest": so  --sport cycling --distance latest~10%  is cycling rides within 10% of
the length of your latest cycling ride.  (--latest, the flag, is --newest 1.)

"previous" is the one activity that was selected before (`nch activities` shows it): select it
with --select, then  --sport previous --distance previous~10%  finds rides like it.  It is an
error unless exactly one activity is selected.
"""

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

proc present(st: Store, column: string): seq[(string, int)] {.raises: [StoreError].} =
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
    st: Store, what, column: string, wanted: seq[string]
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

func rowColumns(verbose: bool, userId: UserId): Sql =
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

const rowFields =
  "start_t, sport, sub, dist, active, file, user, chosen, path, pname, aname, slat, slon"
  ## the columns of a row, in the order `readRows` reads them

proc readRows(st: Store, query: Sql): seq[ListRow] {.raises: [StoreError].} =
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

proc listing(
    rows: seq[ListRow],
    zone: Timezone,
    c: Criteria,
    screen: Screen,
    choices: Option[int],
    saved = none(int),
): seq[Line] =
  ## The table (or the calendar) and its last line.
  result =
    if c.calendar:
      calendarLines(rows, zone, c.verbose, screen)
    else:
      table(rows, zone, c.verbose)
  result.add footerLine(rows, choices, selectedColour, saved)

proc skippedWarning(rows: seq[ListRow], zone: Timezone, c: Criteria): seq[Line] =
  ## The last line of a calendar of the months with data, if it left some out.
  if not c.calendar or c.verbose:
    return
  let n = skippedMonths(rows, zone)
  if n > 0:
    result.add @[
      span(
        "warning: " & $n & (if n == 1: " month" else: " months") &
          " with no activity not shown, at the yellow month names; use --verbose to show them",
        yellow,
      )
    ]

proc showSelection*(
    st: Store, c: Criteria, zone: Timezone, screen = Screen(colour: true)
): seq[Line] {.raises: [StoreError].} =
  ## The stored selection of the store's user, as a listing.
  let rows = readRows(
    st,
    "select " & rowColumns(c.verbose, st.userId) &
      " from selection s join activity a on a.id = s.activity_id join file f on f.id = a.file_id " &
      "where s.user_id = :owner order by a.start_t, a.id".sqlOf.with("owner", st.userId),
  )
  if rows.len == 0:
    return @[
      plain(
        "nothing is selected: `nch activities --all` lists every activity; with criteria and --select some are chosen"
      )
    ]
  result = listing(rows, zone, c, screen, none(int))
  result.add skippedWarning(rows, zone, c)

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
    st: Store
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
    centre: var Option[(float, float)],
    source: var string,
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
  if c.near == (if which == refLatest: nkLatest else: nkPrevious):
    centre = startOf(st, id)
    if centre.isNone:
      raiseStore(
        "the " & nameOf & " activity has no start position (--near " & nameOf & ")"
      )
    source = "the start of the " & nameOf & " activity"
    c.near = nkNone

type Resolved = object
  ## The criteria with `latest`, `previous` and the climbs worked out, and the notes that say which activities they came to.
  c: Criteria
  centre: Option[(float, float)]
  notes: seq[Line]

proc resolveCriteria(
    st: Store, criteria: Criteria, zone: Timezone
): Resolved {.raises: [StoreError].} =
  ## `previous` (in --near, --distance, --active, --sport, --sub-sport) is the one activity
  ## that was selected before; `latest` is the newest activity among those that meet the
  ## criteria that do not mention `latest`.  `previous` is found first, so a criterion that
  ## uses it is one of those among which `latest` is found.
  var c = criteria
  let userIds = @[st.userId]
  if c.climbs.len > 0:
    # the climbs whose name as shown ("Farellones₂", retired ones too) holds the text, whatever its case and accents
    # ("farellones 2" and "farellones2" mean "farellones₂" as well)
    let shown = shownNames(st)
    for t in c.climbs:
      var found = false
      for id, name in shown:
        for form in ordinalForms(t):
          if foldText(name).contains(foldText(form)):
            found = true
            if id notin c.climbIds:
              c.climbIds.add id
      if not found:
        raiseStore(
          "no climb has '" & t & "' in its name (`nch climbs --all` lists them)"
        )
  checkNames(st, "sport", "sport", c.sports)
  checkNames(st, "sub-sport", "sub_sport", c.subSports)
  var centre = none((float, float))
  var centreFrom = ""
  if usesPrevious(c):
    let prev = previousSelected(st)
    result.notes.add plain("previous: " & activityText(prev.row, zone))
    resolve(st, c, refPrevious, prev.id, prev.row, centre, centreFrom)
  if usesLatest(c):
    let base = withoutLatest(c)
    let found = latestAmong(
      st,
      matchSql(
        userIds,
        base,
        none((float, float)),
        sqlOf("a.id as id, ") & rowColumns(false, st.userId),
      ),
    )
    if found.isNone:
      raiseStore(
        "`latest` is the newest activity that meets the other criteria, and none does"
      )
    result.notes.add plain("latest: " & activityText(found.get.row, zone))
    resolve(st, c, refLatest, found.get.id, found.get.row, centre, centreFrom)
  if c.near == nkPoint:
    centre = some((c.lat, c.lon))
  if centre.isSome:
    result.notes.add plain(
      "near " & formatFloat(centre.get[0], ffDecimal, 4) & "," &
        formatFloat(centre.get[1], ffDecimal, 4) &
        (if centreFrom.len > 0: " (" & centreFrom & ")" else: "") & ", within " &
        radiusText(c.radiusKm) & "km"
    )
  result.c = c
  result.centre = centre

proc matchingIds*(
    st: Store, criteria: Criteria, zone: Timezone
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
      "select id from (" & matchSql(@[st.userId], r.c, r.centre, sqlOf("a.id as id")) &
      ")"
  result.ids = st.db.query(int64, query & " order by 1")

proc listActivities*(
    st: Store, criteria: Criteria, zone: Timezone, screen = Screen(colour: true)
): tuple[lines: seq[Line], saved: int] {.raises: [StoreError].} =
  ## List the activities that meet the criteria, or the selection if there are none (and keep them as the selection if
  ## asked); `saved` is how many were kept, -1 if not asked.
  if not (criteria.all or criteria.given):
    # no criteria: the selection
    result.lines = showSelection(st, criteria, zone, screen)
    result.saved = -1
    return
  let r = resolveCriteria(st, criteria, zone)
  let c = r.c
  result.lines = r.notes
  let match = matchSql(
    @[st.userId], c, r.centre, sqlOf("a.id as id, ") & rowColumns(c.verbose, st.userId)
  )
  if c.select:
    st.begin()
    var committed = false
    try:
      st.db.execute("delete from selection where user_id = :userId", userId = st.userId)
      st.db.execute(saveSql(st.userId, match))
      st.commit()
      committed = true
    finally:
      if not committed:
        st.rollback()
  let rows =
    readRows(st, "select " & rowFields & " from (" & match & ") order by start_t, id")
  let total = st.db.scalar(
    int,
    "select count(*) from activity a join file f on f.id = a.file_id where f.user_id = :userId",
    userId = st.userId,
  )
  result.lines.add listing(
    rows, zone, c, screen, some(total), (if c.select: some(rows.len)
    else: none(int))
  )
  result.saved = if c.select: rows.len else: -1
  result.lines.add skippedWarning(rows, zone, c)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch activities ARGS`; returns the exit status.
  let zone = local()
  let parsed = parseArgs(args, zone)
  if parsed.help:
    stdout.say usage
    return exitOk
  if parsed.problem.len > 0:
    return usageError("nch activities", usage, parsed.problem)
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch activities", e.msg)
  try:
    if parsed.criteria.importPaths.len > 0:
      let c = parsed.criteria
      return runImport(
        g,
        c.importPaths,
        ImportOptions(
          steps: allImportSteps,
          quiet: c.quiet,
          slow: c.slow,
          jobs: (if c.jobs > 0: c.jobs else: defaultJobs()),
        ),
      )
    if parsed.criteria.delete:
      let m = matchingIds(st, parsed.criteria, zone)
      for l in m.notes:
        stdout.say l.text & "\n"
      let searched = parsed.criteria.all or parsed.criteria.given
      return runDelete(
        g,
        st,
        m.ids,
        parsed.criteria.force,
        if searched:
          "no activity meets the criteria: nothing to delete"
        else:
          "nothing is selected: `nch activities CRITERIA --select` chooses activities, or give criteria or --all",
      )
    let colour = canColourStdout()
    let screen = Screen(
      colour: colour,
      width:
        if isatty(stdout):
          terminalWidth()
        else:
          0,
    )
    let r = listActivities(st, parsed.criteria, zone, screen)
    if r.saved >= 0:
      g.log.log(
        lvInfo,
        $cmActivities,
        leSaved,
        $r.saved & (if r.saved == 1: " activity" else: " activities"),
      )
    for l in r.lines:
      stdout.say render(l, colour) & "\n"
    exitOk
  except StoreError as e:
    failure("nch activities", e.msg)
