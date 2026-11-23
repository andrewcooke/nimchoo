## `nch activities`: the activities, and the selection.  With no criteria it shows the selection, the activities that
## the commands which work on activities (climbs, map ...) use by default; with criteria or `--all` it
## searches all the activities, and `--select` keeps what is listed as the selection.  The selection is kept in the
## database (table `activity_selection`), for the current user, and replaced whenever `--select` is given.
##
## This module is newer than `importer` and reads its tables (activity, file, coords, route) directly.

import std/[options, sequtils, strformat, strutils, tables, times]
import ./cmdname
import ../subject/steps
export cmdname
import ../../core/[extension, globals]
import ../db/statement
import ../importer/naming
import ../geo/position
import ../cache/cache
import ../names/[open, places]
import ../selection/selection
import ../db/store
import ./deleterun as deleteRun
import ../../core/errors
import ../../core/logfile
import ../ui/style
import ../ui/vocabulary
import ../util/args/[args, usage]
import ./[rows, table]
import ./criteria
import ../text/fold/fold
import ../util/lookup/lookup
import ../user/session

{.push raises: [].}

const synopsis =
  """usage: nch [--db PATH] [--user NAME] activities [CRITERIA [--within | --also]] [--select] [-v]
       nch [--db PATH] [--user NAME] activities --all [--select]
       nch [--db PATH] [--user NAME] activities [CRITERIA [--within] | --all] --delete"""

func intro(): seq[Line] =
  # (the prose is wrapped to the window by `prose`: its line breaks are the source's only)
  @[
    ~"Show the activities of the selection: the ones that other commands (climbs, map ...) use unless they are told otherwise.  With criteria (or `--all`), what is shown is found in these steps:",
    ~"1. Start with all your activities.",
    ~"2. The special value `previous` is the current selection, if it is one activity.",
    step(3, withinStep(words)),
    ~"4. Apply the filters (criteria) that do not use `latest`, combined with \"and\".",
    ~"5. The special value `latest` is the most recent activity remaining.",
    ~"6. Apply the filters that use `latest`, combined with \"and\".",
    ~"7. If `--invert`, use instead the activities of step 3 that steps 4 and 6 left out.",
    ~"8. Apply `--newest` and `--oldest`.",
    step(9, alsoStep(words)),
    ~"10. If `--delete` or `--rename`, delete or rename the result, and stop.",
    step(11, selectStep(words)),
    step(12, displayStep(words)),
    ~"`latest` and `previous` can be referred to in criteria (`--distance latest~10%`, `--from latest`, `--names previous` ...).  `--delete` and `--rename` cannot be used with `--also` or `--select`.",
    ~"If no criteria are given, steps 3 to 9 are skipped and the current selection is used.  `--all` is the criterion that keeps everything: `nch activities --all` lists every activity, and `--all --delete` deletes them all.",
  ]

const notes = @[
  ~"So `--tags 'sport:cycling*' --distance latest~10%` is cycling rides within 10% of the length of your latest cycling ride; select one ride with `--select`, then `--distance previous~10% --active previous~10%` finds rides like it.  `previous` is an error unless exactly one activity is selected."
]

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch activities`, described (for tab completion).
  criteriaSpec(g.extensions.get(activityCriterion)).docs

proc usageText*(width: int, offered: seq[Criterion] = @[]): seq[Line] =
  ## The usage: the synopsis, the introduction, the options (made from their descriptions) and the notes, all wrapped to
  ## `width` (the synopsis lines are not).
  usageOf(synopsis, width, intro(), criteriaSpec(offered).docs, notes)

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

proc listing(
    rows: seq[ListRow],
    zone: Timezone,
    width: int,
    verbose: bool,
    choices: Option[int],
    marks = false,
    isSelection = false,
): seq[Line] =
  ## The table and its last line (`marks`: the selection in brackets, where there is no colour; `isSelection`: the rows
  ## are the selection).
  result = table(rows, zone, verbose, width, marks)
  result.add footerLine(rows, choices, isSelection, marks)

proc showSelection*(
    st: Session, verbose: bool, zone: Timezone, width: int, marks = false
): seq[Line] {.raises: [StoreError].} =
  ## The stored selection of the store's user, as a listing.
  let rows = selectionRows(st, verbose)
  if rows.len == 0:
    return @[
      ~"nothing is selected: `nch activities --all` lists every activity; with criteria and `--select` some are chosen"
    ]
  result = listing(
    rows,
    zone,
    width,
    verbose,
    some(activityCount(st)),
    marks = marks,
    isSelection = true,
  )

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
    int,
    "select count(*) from activity_selection where user_id = :userId",
    userId = st.userId,
  )
  if n != 1:
    raiseStore(
      "`previous` needs a selection of exactly one activity, and it has " & $n &
        " (see `nch activities`)"
    )
  let rows = readRows(
    st,
    "select " & rowColumns(false, st.userId) &
      " from activity_selection s join activity a " &
      "on a.id = s.activity_id join file f on f.id = a.file_id where s.user_id = :owner".sqlOf.with(
        "owner", st.userId
      ),
  )
  (
    id: st.db.scalar(
      ActivityId,
      "select activity_id from activity_selection where user_id = :userId",
      userId = st.userId,
    ),
    row: rows[0],
  )

type
  Env = object
    ## What the filters need besides themselves, found before they are resolved: the activities they refer to, what a number
    ## in `--names` meant, the conditions of the criteria other packages offer, and the places named.
    anchors: array[Referent, Option[Anchor]]
    nameTexts: Option[seq[string]]
      ## `--names` without the numbers that meant an activity
    nameIds: seq[int64]
    conditions: Table[string, Sql] ## by the option that offered them
    places: Table[string, tuple[lat, lon: float, said: string]]

  Search = object
    ## The filters with `latest` and `previous` worked out, and the notes that say which activities they came to.
    filters: seq[Resolved]
    invert: bool
    limit: Option[Limit]
    among: Among
      ## every activity, or only the selection (`--within`: `latest` is found there too)
    notes: seq[Line]

func nameOf(r: Referent): string =
  case r
  of rfLatest: "latest"
  of rfPrevious: "previous"

proc anchorOf(
    st: Store, id: ActivityId, row: ListRow
): Anchor {.raises: [StoreError].} =
  ## What a criterion can use of the activity: its row, its name and start place whole (they are not in the row unless it was
  ## listed with -v) and where it started.
  let r = st.db.scalar(
    tuple[name, start: string],
    "select coalesce(name, ''), coalesce(start_place, '') from activity where id = :id",
    id = id,
  )
  Anchor(
    distanceM: row.distanceM,
    activeS: row.activeS,
    name: r.name,
    startPlace: r.start,
    start: startOf(st, id),
  )

proc anchor(env: Env, r: Referent): Anchor =
  ## The activity `r` stands for (found before the filters are resolved: a missing one is a bug).
  doAssert env.anchors[r].isSome,
    "the activity a criterion refers to was not looked for"
  env.anchors[r].get

proc resolveFilter(f: Filter, env: Env): Resolved {.raises: [StoreError].} =
  ## The filter with its values: what it refers to is taken from `env`.  (A criterion that needs a value the activity does not
  ## have is an error that says so.)
  case f.kind
  of ftNames:
    Resolved(
      kind: rtNames,
      typed: env.nameTexts.get(f.listed.values),
      exact:
        (if f.listed.refers.isSome: @[env.anchor(f.listed.refers.get).name]
        else: @[]),
      ids: env.nameIds,
    )
  of ftStarts:
    Resolved(
      kind: rtStarts,
      typed: f.listed.values,
      exact: (
        if f.listed.refers.isSome:
          @[env.anchor(f.listed.refers.get).startPlace]
        else:
          @[]
      ),
    )
  of ftPaths:
    Resolved(kind: rtPaths, paths: f.paths)
  of ftTags:
    Resolved(kind: rtTags, tags: f.patterns)
  of ftContributed:
    Resolved(kind: rtCondition, condition: env.conditions.must(f.contributed.option))
  of ftDistance:
    if not f.spread.byReference:
      Resolved(kind: rtDistance, range: f.spread.range)
    else:
      let d = env.anchor(f.spread.refers).distanceM
      if d.isNone:
        raiseStore(
          "the " & nameOf(f.spread.refers) & " activity has no recorded distance"
        )
      Resolved(kind: rtDistance, range: around(d.get, f.spread.tol))
  of ftActive:
    if not f.spread.byReference:
      Resolved(kind: rtActive, range: f.spread.range)
    else:
      let t = env.anchor(f.spread.refers).activeS
      if t.isNone:
        raiseStore(
          "the " & nameOf(f.spread.refers) & " activity has no recorded active time"
        )
      Resolved(kind: rtActive, range: around(t.get, f.spread.tol))
  of ftAfter:
    Resolved(kind: rtAfter, at: f.at)
  of ftBefore:
    Resolved(kind: rtBefore, at: f.at)
  of ftGps:
    Resolved(kind: rtGps, gps: f.gps)
  of ftFrom, ftNear:
    var at: (float, float)
    case f.place.kind
    of plPoint:
      at = (f.place.lat, f.place.lon)
    of plPlace:
      let p = env.places.must(f.place.name)
      at = (p.lat, p.lon)
    of plReferent:
      let start = env.anchor(f.place.refers).start
      if start.isNone:
        raiseStore(
          fmt"the {nameOf(f.place.refers)} activity has no start position (to measure from)"
        )
      at = start.get
    if f.kind == ftFrom:
      Resolved(kind: rtFrom, lat: at[0], lon: at[1], km: startKm(f.radius))
    else:
      Resolved(kind: rtNear, lat: at[0], lon: at[1], km: passKm(f.radius))

proc numbersAsIds(
    st: Session, texts: seq[string], notes: var seq[Line]
): tuple[texts: seq[string], ids: seq[int64]] {.raises: [StoreError].} =
  ## A whole number in `--names` that no activity's name holds is the number of an activity (`--names 737`): a name that
  ## has the digits wins, so a number can always be searched for as text by being in a name.  A note says which it was.
  for t in texts:
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
      result.ids.add int64(n)
      notes.add plain(fmt"no activity name has '{t}': using activity {n}")
    else:
      result.texts.add t

proc resolveScope(
    st: Session, scope: Scope, zone: Timezone
): Search {.raises: [StoreError].} =
  ## `previous` (in --from, --near, --distance, --active, --names, --starts) is the one activity
  ## that was selected before; `latest` is the newest activity among those that meet the
  ## criteria that do not mention `latest` (as the usage's steps say).  `previous` is found first, so a criterion that
  ## uses it is one of those among which `latest` is found.
  let filters = scope.filtersOf
  result.among = scope.amongOf
  var env: Env
  for f in filters:
    case f.kind
    of ftContributed:
      let r = f.contributed.resolve(st, f.contributed.values)
      env.conditions[f.contributed.option] = r.condition
      for n in r.notes:
        if n.len > 0:
          result.notes.add plain(n)
    of ftNames:
      let found = numbersAsIds(st, f.listed.values, result.notes)
      env.nameTexts = some(found.texts)
      env.nameIds = found.ids
    of ftFrom, ftNear:
      if f.place.kind == plPlace and f.place.name notin env.places:
        let p = placeNamed(st, f.place.name)
        env.places[f.place.name] = (lat: p.lat, lon: p.lon, said: p.said)
    of ftStarts, ftPaths, ftTags, ftDistance, ftActive, ftAfter, ftBefore, ftGps:
      discard
  if usesPrevious(filters):
    let prev = previousSelected(st)
    result.notes.add plain("previous: " & activityText(prev.row, zone))
    env.anchors[rfPrevious] = some(anchorOf(st, prev.id, prev.row))
  if usesLatest(filters):
    var base: seq[Resolved]
    for f in filters:
      # (as the usage's steps say: every filter that does not use `latest`)
      let rest = f.withoutLatest
      if rest.isSome:
        base.add resolveFilter(rest.get, env)
    let found = latestAmong(
      st,
      matchSql(
        st.userId,
        base,
        sqlOf("a.id as id, ") & rowColumns(false, st.userId),
        among = result.among,
      ),
    )
    if found.isNone:
      raiseStore(
        "`latest` is the newest activity that meets the other criteria, and none does"
      )
    result.notes.add plain("latest: " & activityText(found.get.row, zone))
    env.anchors[rfLatest] = some(anchorOf(st, found.get.id, found.get.row))
  for f in filters:
    result.filters.add resolveFilter(f, env)
  for (f, r) in zip(filters, result.filters):
    if f.kind in {ftFrom, ftNear}:
      let what = if f.kind == ftFrom: "starting near" else: "passing near"
      let where = positionText((lon: r.lon, lat: r.lat))
      let said =
        case f.place.kind
        of plPoint:
          ""
        of plPlace:
          env.places.must(f.place.name).said
        of plReferent:
          fmt"the start of the {nameOf(f.place.refers)} activity"
      let why =
        if said.len > 0:
          fmt" ({said})"
        else:
          ""
      result.notes.add plain(fmt"{what} {where}{why}, within {radiusText(r.km)}km")
  result.invert = scope.inverts
  result.limit = scope.limitOf

proc matchingIds*(
    st: Session, scope: Scope, zone: Timezone
): tuple[ids: seq[int64], notes: seq[Line]] {.raises: [StoreError].} =
  ## The ids of the current user's activities the scope means: the selection if there are no criteria and no `--all`,
  ## else the activities found among all of them.  (And the notes that say which activity `latest` or `previous` was.)
  var query: Sql
  if not scope.searches:
    query = sqlOf("select activity_id from activity_selection where user_id = :owner")
      .with("owner", st.userId)
  else:
    let r = resolveScope(st, scope, zone)
    result.notes = r.notes
    query =
      "select id from (" &
      matchSql(st.userId, r.filters, sqlOf("a.id as id"), r.invert, r.limit, r.among) &
      ")"
  result.ids = st.db.query(int64, query & " order by 1")

proc listActivities*(
    st: Session, request: Request, zone: Timezone, width: int, marks = false
): tuple[lines: seq[Line], saved: Option[int]] {.raises: [StoreError].} =
  ## List the activities of the scope, the selection if that is what it is (and keep them as the selection if asked); `saved`
  ## is how many were kept, if they were.
  doAssert request.action.kind == akList
  let verbose = request.action.verbose
  if not request.scope.searches:
    # no criteria: the selection
    result.lines = showSelection(st, verbose, zone, width, marks)
    return
  let r = resolveScope(st, request.scope, zone)
  result.lines = r.notes
  # the usage's steps: every activity, or the selection (--within); the filters; the limit
  let found = matchSql(st.userId, r.filters, sqlOf("a.id"), r.invert, r.limit, r.among)
  # --also adds the selection
  var listed = sqlOf("a.id in (") & found & ")"
  if request.scope.kind == scMatching and request.scope.also:
    listed =
      listed &
      sqlOf(
        " or a.id in (select activity_id from activity_selection where user_id = :alsoOwner)"
      )
      .with("alsoOwner", st.userId)
  let shown =
    sqlOf("select a.id as id, ") & rowColumns(verbose, st.userId) &
    " from activity a join file f on f.id = a.file_id where " & listed
  # --select replaces it (before the list is drawn, so that the select style shows the selection after the command)
  if request.action.select:
    let ids = st.db.query(int64, sqlOf("select id from (") & shown & ")")
    st.replaceSelection(ids)
    result.saved = some(ids.len)
  # the list; the select style marks those listed that are in the selection after the command
  let rows =
    readRows(st, "select " & rowFields & " from (" & shown & ") order by start_t, id")
  let total = activityCount(st)
  result.lines.add listing(
    rows, zone, width, verbose, some(total), marks, isSelection = request.action.select
  )

proc renameActivities(g: Globals, st: Session, ids: seq[int64]): int {.raises: [].} =
  ## `--rename`: forget the names of the activities and make them again, as an import does.
  let names = openNames(
    g,
    st,
    commandName,
    proc(line: Line) {.closure, raises: [].} =
      g.show(osErr, line),
  )
  if names.isNone:
    return failure(g, "nch activities", noCacheDir)
  try:
    st.forgetNames(ids)
    let n = ensureActivityNames(st, names.get)
    g.done(
      ~"named {counted(n.total, \"activity\", \"activities\")} again: {n.detailText}"
    )
    exitOk
  except StoreError, DownloadError:
    failure(
      g,
      "nch activities",
      ~"{getCurrentExceptionMsg()} (the names not made are made by the next `nch import`)",
    )

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch activities ARGS`; returns the exit status.
  let zone = local()
  let offered = g.extensions.get(activityCriterion)
  let parsed = parseArgs(args, zone, offered)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut), offered)
    return exitOk
  of pkProblem:
    return usageError(
      g, "nch activities", usageText(g.textWidth(osErr), offered), parsed.problem
    )
  of pkUnit:
    return unitRetry(g, "nch activities", parsed.fix, run)
  of pkOk:
    discard
  let request = parsed.params
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure(g, "nch activities", e.msg)
  try:
    case request.action.kind
    of akDelete:
      let m = matchingIds(st, request.scope, zone)
      for l in m.notes:
        g.show(osOut, l)
      let searched = request.scope.searches
      return runDelete(
        g,
        st,
        m.ids,
        parsed.yes,
        if searched:
          ~"no activity meets the criteria: nothing to delete"
        else:
          ~"nothing is selected: `nch activities CRITERIA --select` chooses activities, or give criteria or `--all`",
        zone,
      )
    of akRename:
      let m = matchingIds(st, request.scope, zone)
      for l in m.notes:
        g.show(osOut, l)
      if m.ids.len == 0:
        g.warn(
          if request.scope.searches:
            ~"no activity meets the criteria: nothing to rename"
          else:
            ~"nothing is selected: `nch activities CRITERIA --select` chooses activities, or give criteria or `--all`"
        )
        return exitOk
      return renameActivities(g, st, m.ids)
    of akList:
      let r = listActivities(st, request, zone, g.textWidth(osOut), not g.colour[osOut])
      if r.saved.isSome:
        g.log.log(
          lvInfo, commandName, leSaved, counted(r.saved.get, "activity", "activities")
        )
      g.showAll(osOut, r.lines)
      exitOk
  except StoreError as e:
    failure(g, "nch activities", e.msg)
