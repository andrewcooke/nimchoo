## What `nch activities` is asked for: the command line parsed into a `Request` (`request.nim`), and the resolved filters
## turned into SQL.  Pure: no database, no clock, no terminal (the time zone is a parameter), so all of it is tested directly.

import std/[algorithm, math, options, strformat, strutils, times]
import ../fit/time
import ../util/args/args
import ../near/[distance, near]
import ../geo/box
import ../db/sqltext
import ../../core/ids
import ../text/fold/fold
import ../tags/tag
import ../subject/steps
import ./[completion, criterion, ranges, request]
export ranges, criterion, near, request

{.push raises: [].}

const timeFormats = [
  "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
  "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
] ## (a date alone is its midnight: as if written with T00:00:00)

proc parseWhen*(s: string, zone: Timezone): Option[UnixTime] =
  ## An instant typed by the user, in `zone`, as Unix seconds: exactly what is written, a date being the start of its day
  ## (`--after`, `--before`: the one rule for every form, so that `--after D --before E` meets the next range at E).
  for format in timeFormats:
    try:
      return some(UnixTime(parse(s, format, zone).toTime.toUnix))
    except TimeParseError, TimeFormatParseError, ValueError, OverflowDefect:
      discard
  none(UnixTime)

proc parseDay*(s: string, zone: Timezone): Option[Day] =
  ## A date typed by the user (`--dates`: a date, not a time), as that day in `zone`.
  try:
    let d = parse(s, "yyyy-MM-dd", zone)
    some(
      Day(start: UnixTime(d.toTime.toUnix), next: UnixTime((d + 1.days).toTime.toUnix))
    )
  except TimeParseError, TimeFormatParseError, ValueError, OverflowDefect:
    none(Day)

type
  Collected = object
    ## The criteria as the options give them, one field to each (`finish` makes the `Filter`s of them).
    names, starts: Listed
    paths: seq[string]
    tags: seq[TagPattern]
    contributed: seq[Contributed]
    distance, active: Option[Spread]
    afterT, beforeT: Option[UnixTime]
    days: seq[Day] ## --dates, in the order given, each once
    gps: Option[Gps]

  ListState = object
    ## What the options of `nch activities` fill in as they are read (`finish` makes the `Request` of it).
    c: Collected
    steps: Steps ## --all, --select, --also, --within
    delete, rename, verbose, invert: bool
    newest, oldest: Option[int] ## `--newest N`, `--oldest N`
    help: bool
    zone: Timezone
    offered: seq[Criterion] ## the criteria other packages offer
    where: Where ## --from, --near and --radius
    datesGiven, rangeGiven: bool ## --dates was given; --after or --before was
    criteriaGiven: bool ## some option other than those that say what to display

func takeCount(p: var ListState, name, value: string, oldest: bool): Problem =
  ## --newest N, -n N, --oldest N.
  var n = 0
  if not parseIntIn(value, 1, high(int), n):
    return refuse(~"`{name}` needs a number of activities, 1 or more (not '{value}')")
  p.criteriaGiven = true
  if oldest:
    p.oldest = some(n)
  else:
    p.newest = some(n)
  fine

func splitNames(values: seq[string], lower: bool): seq[string] =
  ## The names given, one to a word (a comma is part of a name).
  for v in values:
    if v.len > 0:
      result.add (if lower: v.toLowerAscii else: v)

func takeReferent(l: var Listed, value: string): bool =
  ## A word that is `latest` or `previous` goes to the reference, another is a value; true if it would be the second
  ## reference (they cannot be used together).
  let r = parseReferent(value)
  if r.isNone:
    l.values.add value
    return false
  if l.refers.isSome and l.refers != r:
    return true
  l.refers = r
  false

proc takeTexts(
    p: var ListState, name: string, values: seq[string], listed: var Listed
): Problem =
  p.criteriaGiven = true
  var found: seq[string]
  for v in values:
    if v.strip.len > 0:
      found.add v.strip
  if found.len == 0:
    return refuse(~"`{name}` needs some text")
  for t in found:
    if takeReferent(listed, t):
      return refuse(~"`{name}`: latest and previous cannot be used together")
  fine

proc takeNames(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  takeTexts(p, name, values, p.c.names)

proc takeStarts(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  takeTexts(p, name, values, p.c.starts)

proc takePaths(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  p.criteriaGiven = true
  for v in values:
    if v.strip.len > 0:
      p.c.paths.add v.strip
  if p.c.paths.len == 0:
    return refuse(~"`{name}` needs some text")
  fine

proc takeTags(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  ## --tags: patterns of tags, each with `*` for anything.
  p.criteriaGiven = true
  for v in values:
    let r = parsePattern(v)
    if r.problem.isSome:
      return refuse(~"`{name}`: {r.problem.get}")
    p.c.tags.add r.pattern.get
  if p.c.tags.len == 0:
    return refuse(~"`{name}` needs a tag (`*` for anything: `bike:*`)")
  fine

proc takeContributed(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  ## An option that another package offers: the words are kept for it to resolve.
  p.criteriaGiven = true
  for o in p.offered:
    if name in o.doc.names:
      if o.doc.arity == aList and values.len == 0:
        return refuse(~"`{name}` needs at least one word")
      for c in p.c.contributed.mitems:
        if c.option == o.doc.names[0]:
          c.values.add values
          return fine
      p.c.contributed.add Contributed(
        option: o.doc.names[0], values: values, resolve: o.resolve
      )
      return fine
  raiseAssert name & " is an option of the spec, which has just the offered ones"

func contributedOption(o: Criterion): Opt[ListState] =
  ## The option of an offered criterion, as the parser has them.
  result = Opt[ListState](
    names: o.doc.names,
    arity: o.doc.arity,
    applyList: takeContributed,
    apply: proc(
        p: var ListState, name, value: string
    ): Problem {.nimcall, raises: [].} =
      takeContributed(p, name, (if value.len > 0: @[value] else: @[])),
    metavar: o.doc.metavar.get(""),
    help: o.doc.help,
    completion: o.doc.completion,
  )

func distanceFill(v, unit: string): Option[string] =
  ## `--distance 40-` -> `40km-`, `42km~200` -> `42km~200m`: for `withUnit`.
  fillUnits(v, unit, distanceUnitsBelow)

func timeFill(v, unit: string): Option[string] =
  ## `--active 90-` -> `90h-`, `2h~15` -> `2h~15m`: for `withUnit`.
  fillUnits(v, unit, timeUnitsBelow)

type SpreadWords = object ## How a range of one kind is named in the problems with it.
  what: string ## "distance", "active time"
  shorter: string ## "smaller", "shorter": the end that comes first
  around: string ## the forms of `~`: "42km~2km, 500m~50m"
  ranges: string ## the forms of a range: "40km-, 10-50km, -5km, 500m-, 42~2km"
  note: string ## after them: "; units d h m s"

func takeSpread(
    v: string, endOf: EndParser, w: SpreadWords, into: var Option[Spread]
): Problem =
  ## A range (`10km-50km`) or a spread (`42km~2km`, `latest~10%`) of one kind: the one reader of `--distance` and
  ## `--active`.
  if '~' in v:
    let ar = parseAround(v, endOf)
    if ar.isNone:
      return refuse(
        ~"cannot read the {w.what} '{v}' (use {w.around}, latest~10% or previous~10%)"
      )
    into = some(
      if ar.get.byReference:
        Spread(byReference: true, refers: ar.get.refers, tol: ar.get.tol)
      else:
        Spread(byReference: false, range: around(ar.get.centre, ar.get.tol))
    )
  else:
    let r = parseRange(v, endOf)
    if r.isNone:
      if isBackwards(v, endOf):
        return refuse(~"the {w.what} range '{v}' is backwards ({w.shorter} end first)")
      return refuse(
        ~"cannot read the {w.what} range '{v}' (use {w.ranges}, latest~10% or previous~10%{w.note})"
      )
    into = some(Spread(byReference: false, range: r.get))
  fine

const
  distanceWords = SpreadWords(
    what: "distance",
    shorter: "smaller",
    around: "42km~2km, 500m~50m",
    ranges: "40km-, 10-50km, -5km, 500m-, 42~2km",
  )
  activeWords = SpreadWords(
    what: "active time",
    shorter: "shorter",
    around: "2h~15m",
    ranges: "1h-, 30m-2h, -45m, 2h~15m",
    note: "; units d h m s",
  )

proc takeDistance(p: var ListState, name, v: string): Problem {.nimcall.} =
  p.criteriaGiven = true
  takeSpread(v, metresEnd, distanceWords, p.c.distance)

proc takeActive(p: var ListState, name, v: string): Problem {.nimcall.} =
  p.criteriaGiven = true
  takeSpread(v, secondsEnd, activeWords, p.c.active)

proc takeWhen(p: var ListState, v: string, before: bool): Problem =
  ## --after T, --before T: the instant as written.
  p.criteriaGiven = true
  p.rangeGiven = true
  let t = parseWhen(v, p.zone)
  if t.isNone:
    return refuse(~"cannot read the time '{v}' (use 2018-08-27 or 2018-08-27T09:30)")
  if before:
    p.c.beforeT = t
  else:
    p.c.afterT = t
  fine

proc takeDates(
    p: var ListState, name: string, values: seq[string]
): Problem {.nimcall.} =
  ## --dates DATE...: the activities of those days.
  p.criteriaGiven = true
  p.datesGiven = true
  for v in values:
    if v.strip.len == 0:
      continue
    let d = parseDay(v.strip, p.zone)
    if d.isNone:
      return refuse(~"`{name}` takes dates, like 2018-08-27 (not '{v}')")
    if d.get notin p.c.days:
      p.c.days.add d.get
  if p.c.days.len == 0:
    return refuse(~"`{name}` needs a date, like 2018-08-27")
  fine

func takeGps(p: var ListState, wanted: Gps): Problem =
  ## --gps and --no-gps, which contradict each other.
  p.criteriaGiven = true
  if p.c.gps.isSome and p.c.gps.get != wanted:
    return refuse(~"`--gps` and `--no-gps` cannot be used together")
  p.c.gps = some(wanted)
  fine

const words* = Words(
  command: "activities",
  things: "activities",
  every: "every activity",
  selection: "selection",
) ## how the activities are named in the steps that involve the selection

proc criteriaSpec*(offered: seq[Criterion] = @[]): Spec[ListState] =
  ## The options of `nch activities`, in the order the usage lists them, each with its help; the criteria that other
  ## packages offer come after the sports, names and paths.
  result = Spec[ListState](
    opts:
      @[
        listOption[ListState](
          ["--names"],
          takeNames,
          "TEXT...",
          ~"activities whose name contains any of the TEXTs, whatever its case or accents: `--names toyo` finds \"El Toyo and back\", `--names toyo farellones` finds either; a text with spaces is quoted; a whole number that no name contains is an activity's number (`--names 737`); \"none\": no name; \"latest\" or \"previous\": the same name as that activity",
        ),
        listOption[ListState](
          ["--starts"],
          takeStarts,
          "TEXT...",
          ~"the same for the place the activity started (\"Providencia\", \"near Lo Barnechea\"): `--starts providencia`",
        ),
        listOption[ListState](
          ["--paths"],
          takePaths,
          "TEXT...",
          ~"the same for the path of the file the activity was imported from (or any other path the same file was seen at): `--paths bowman`, `--paths 2026-10`",
        ),
        listOption[ListState](
          ["--tags"],
          takeTags,
          "TAG...",
          ~"activities that have a tag matching each (all of them: \"and\"), whatever its case or accents; `*` is anything: `--tags bike:cotic`, `--tags 'sport:cycling*'` (quoted, or the shell reads the `*`).  An import gives each activity its sport as a tag: `sport:cycling:road`, or `sport:cycling` when the file says nothing more",
          completion = completesFrom(completeTags),
        ),
        custom(
          ListState,
          ["--distance"],
          true,
          "RANGE",
          ~"distance, with its unit (`km` or `m`; a unit left out is filled in, after asking: `10-50` as `10km-50km`, `42km~200` as `42km~200m`): 40km- (40 or more), 10km-50km, -5km (up to 5), 500m-; 42km~2km (between 40 and 44), latest~10%, previous~10%",
          body = takeDistance(p, name, value),
        )
          .withUnit("km", distanceFill),
        custom(
          ListState,
          ["--active"],
          true,
          "RANGE",
          ~"active time: 1h-, 30m-2h, -45m (units d h m s, as printed; a unit left out is filled in, after asking: `30-90m` as `30m-90m`, `2h~15` as `2h~15m`, a bare number as hours); 2h~15m, latest~10%, previous~10%",
          body = takeActive(p, name, value),
        )
          .withUnit("h", timeFill),
        custom(
          ListState,
          ["--after"],
          true,
          "TIME",
          ~"activities that start at or after TIME",
          body = takeWhen(p, value, false),
        ),
        custom(
          ListState,
          ["--before"],
          true,
          "TIME",
          ~"activities that start before TIME (TIME is in your time zone: 2018-08-27, 2018-08-27T09:30 or with seconds; a date is the start of that day, as if written with T00:00:00: `--after 2018-08-01 --before 2018-09-01` is August)",
          body = takeWhen(p, value, true),
        ),
        listOption[ListState](
          ["--dates"],
          takeDates,
          "DATE...",
          ~"activities that start on one of those days (dates: `--dates 2018-08-27` is `--after 2018-08-27 --before 2018-08-28`; `--dates 2018-08-27 2018-09-02` is either day)",
        ),
        custom(
          ListState,
          ["--gps"],
          false,
          "",
          ~"only activities that have positions (a GPS track)",
          body = takeGps(p, gpsWith),
        ),
        custom(
          ListState,
          ["--no-gps"],
          false,
          "",
          ~"only activities that have none (indoor rides, treadmill runs ...)",
          body = takeGps(p, gpsWithout),
        ),
        custom(
          ListState,
          ["--invert"],
          false,
          "",
          ~"the activities that do NOT meet the criteria (all of them taken together): everything that fails to match, including those that have nothing recorded for a criterion.  \"latest\" and \"previous\" are found before inverting; `--newest` and `--oldest` apply after.  Needs a criterion",
          body = (p.criteriaGiven = true; p.invert = true; fine),
        ),
        custom(
          ListState,
          ["-n", "--newest"],
          true,
          "N",
          ~"only the N newest of the activities that meet the other criteria",
          body = takeCount(p, name, value, false),
        ),
        custom(
          ListState,
          ["--oldest"],
          true,
          "N",
          ~"only the N oldest of them",
          body = takeCount(p, name, value, true),
        ),
      ] & stepOptions(ListState, words) &
      @[
        custom(
          ListState,
          ["--rename"],
          false,
          "",
          ~"name the activities again (with no criteria and no `--all`, those of the selection): where each started and what it is called, from the places and your landmarks as they are now (after `nch landmarks --add`, say)",
          body = (p.rename = true; fine),
        ),
        custom(
          ListState,
          ["--delete"],
          false,
          "",
          ~"delete the activities (with no criteria and no `--all`, those of the selection) and everything made from them: coordinates, route, heart rate, impulses, efforts.  The climbs found in them stay (they are shared), and so do the names on those.  The file of an activity is forgotten as well: importing its folder again would bring the activity back.  It asks first, saying what would be deleted (`-y` answers yes; with no terminal and no `-y` nothing is deleted)",
          body = (p.delete = true; fine),
        ),
        custom(
          ListState,
          ["-v", "--verbose"],
          false,
          "",
          ~"show more of each activity: where it started (its coordinates, or \"no GPS\" if the file has no positions), the place it started and its name (made when it was imported), its tags, and the path of its file",
          body = (p.verbose = true; fine),
        ),
        helpFlag(ListState),
      ]
  )
  var at = 0
    # (the offered ones go before --distance: with the criteria that say what an activity is called or where)
  while at < result.opts.len and "--distance" notin result.opts[at].names:
    inc at
  for k, o in offered:
    result.opts.insert(contributedOption(o), at + k)
  var inv = 0
  while inv < result.opts.len and "--invert" notin result.opts[inv].names:
    inc inv
  for k, o in nearOptions(ListState, where, "activities", true):
    result.opts.insert(o, inv + k)

func placeOf(spot: Spot): Option[Place] =
  ## What `--from` or `--near` said (none: it was not given).
  case spot.kind
  of nkNone:
    none(Place)
  of nkPoint:
    some(Place(kind: plPoint, lat: spot.lat, lon: spot.lon))
  of nkPlace:
    some(Place(kind: plPlace, name: spot.place))
  of nkLatest:
    some(Place(kind: plReferent, refers: rfLatest))
  of nkPrevious:
    some(Place(kind: plReferent, refers: rfPrevious))

func filtersOf(c: Collected, w: Where): seq[Filter] =
  ## The criteria that were given, each once.
  if c.names.values.len > 0 or c.names.refers.isSome:
    result.add Filter(kind: ftNames, listed: c.names)
  if c.starts.values.len > 0 or c.starts.refers.isSome:
    result.add Filter(kind: ftStarts, listed: c.starts)
  if c.paths.len > 0:
    result.add Filter(kind: ftPaths, paths: c.paths)
  if c.tags.len > 0:
    result.add Filter(kind: ftTags, patterns: c.tags)
  for o in c.contributed:
    result.add Filter(kind: ftContributed, contributed: o)
  if c.distance.isSome:
    result.add Filter(kind: ftDistance, spread: c.distance.get)
  if c.active.isSome:
    result.add Filter(kind: ftActive, spread: c.active.get)
  if c.afterT.isSome:
    result.add Filter(kind: ftAfter, at: c.afterT.get)
  if c.beforeT.isSome:
    result.add Filter(kind: ftBefore, at: c.beforeT.get)
  if c.days.len > 0:
    result.add Filter(kind: ftDates, days: c.days)
  if c.gps.isSome:
    result.add Filter(kind: ftGps, gps: c.gps.get)
  let start = placeOf(w.start)
  if start.isSome:
    result.add Filter(kind: ftFrom, place: start.get, radius: w.radius)
  let passes = placeOf(w.passes)
  if passes.isSome:
    result.add Filter(kind: ftNear, place: passes.get, radius: w.radius)

func finish(st: ListState): Parsed[Request] =
  ## What was read, if the options go together: the action on the scope.  (What the types cannot say is refused here.)
  func bad(why: Line): Parsed[Request] =
    problemWith[Request](why)

  var w = st.where
  discard w.settle(true)
    # (--radius alone: around where the latest started; never refused here)
  let filters = filtersOf(st.c, w)
  let given = st.criteriaGiven or w.given
  if st.steps.all and filters.len > 0:
    return bad(
      ~"`--all` is every activity: it does not go with criteria (`--newest` and `--oldest` do)"
    )
  if st.delete and (st.steps.select or st.verbose):
    return bad(~"`--delete` shows nothing: it does not go with `--select` or `-v`")
  if st.rename and (st.delete or st.steps.select or st.verbose):
    return bad(
      ~"`--rename` shows nothing: it does not go with `--delete`, `--select` or `-v`"
    )
  if (st.delete or st.rename) and st.steps.also:
    return bad(
      ~"`--also` adds the whole selection to what is found: `--delete` and `--rename` do not take it (it is too easy to act on more than was meant)"
    )
  let stepsWrong = stepProblem(st.steps, given, words)
  if stepsWrong.isSome:
    return bad(stepsWrong.get)
  if st.invert and filters.len == 0:
    return bad(
      ~"`--invert` needs a criterion to invert (`--tags`, `--names`, `--distance` ...)"
    )
  if st.newest.isSome and st.oldest.isSome:
    return bad(~"`--newest` and `--oldest` cannot be used together")
  if st.datesGiven and st.rangeGiven:
    return bad(
      ~"`--dates` are days of their own: they do not go with `--after` or `--before`"
    )
  if st.c.afterT.isSome and st.c.beforeT.isSome and st.c.afterT.get >= st.c.beforeT.get:
    return bad(~"`--after` is not before `--before`")
  let limit =
    if st.newest.isSome:
      some(Limit(kind: lkNewest, count: st.newest.get))
    elif st.oldest.isSome:
      some(Limit(kind: lkOldest, count: st.oldest.get))
    else:
      none(Limit)
  let action =
    if st.delete:
      Action(kind: akDelete)
    elif st.rename:
      Action(kind: akRename)
    else:
      Action(kind: akList, verbose: st.verbose, select: st.steps.select)
  let scope =
    if st.steps.all:
      Scope(kind: scAll, allLimit: limit)
    elif given:
      Scope(
        kind: scMatching,
        filters: filters,
        invert: st.invert,
        limit: limit,
        among: st.steps.among,
        also: st.steps.also,
      )
    else:
      Scope(kind: scSelection)
  parsedOk(Request(action: action, scope: scope))

proc parseArgs*(
    args: seq[string], zone: Timezone, offered: seq[Criterion] = @[]
): Parsed[Request] =
  ## The command line of `nch activities`.  Options with values: `--tags A B`, `--names`, `--starts`,
  ## `--paths`, `--climbs` (words up to the next option), `--delete`, `--rename`, `--dates` (dates), `--after T`, `--before T`, `--from` and `--near` (LAT,LON, a place, latest, previous), `--radius DISTANCE` (`3km`, `500m`);
  ## `--newest N` (or `-n N`), `--oldest N`, `--invert`, `--all` (every activity), `--select`
  ## (keep what is listed as the selection), and `-v`/`--verbose` (what to display).  With no
  ## criterion and no `--all` it is the selection that is meant.
  parseCommand(
    args, criteriaSpec(offered), ListState(zone: zone, offered: offered), finish
  )

func textSql*(
    column, name: string,
    typed: seq[string],
    exact: seq[Option[string]],
    ids: seq[int64] = @[],
): Sql =
  ## " and (instr(fold(a.name), :nameT0) > 0 or a.name = :nameE0)": the typed text (folded) found anywhere in the
  ## value, whatever its case and accents (see fold.nim), or the whole value (what `latest` came to).  "none" typed, or
  ## an exact none (the activity referred to has no value), is no value: null or "".  Nothing if there is nothing to match.
  if typed.len == 0 and exact.len == 0 and ids.len == 0:
    return
  var parts: seq[string]
  for i, id in ids:
    let n = name & "I" & $i
    parts.add "a.id = :" & n
    result.args.add (n, arg(id))
  for i, t in typed:
    if t.toLowerAscii == "none":
      parts.add "(" & column & " is null or " & column & " = '')"
    else:
      let n = name & "T" & $i
      parts.add "instr(fold(" & column & "), :" & n & ") > 0"
      result.args.add (n, arg(foldText(t.strip)))
  for i, e in exact:
    if e.isNone:
      parts.add "(" & column & " is null or " & column & " = '')"
    else:
      let n = name & "E" & $i
      parts.add column & " = :" & n
      result.args.add (n, arg(e.get))
  result.text = " and (" & parts.join(" or ") & ")"

func pathSql*(paths: seq[string]): Sql =
  ## " and (instr(fold(f.name), :path0) > 0 or exists (select 1 from seen_file ...))": the text found in any path the
  ## file was imported from (a file can have been seen at several), or in the file's name; whatever its case and
  ## accents (see fold.nim).
  if paths.len == 0:
    return
  var parts: seq[string]
  for i, t in paths:
    let n = "path" & $i
    parts.add "(instr(fold(f.name), :" & n &
      ") > 0 or exists (select 1 from seen_file s where s.file_id = f.id and instr(fold(s.path), :" &
      n & ") > 0))"
    result.args.add (n, arg(foldText(t.strip)))
  result.text = " and (" & parts.join(" or ") & ")"

func datesSql*(days: seq[Day]): Sql =
  ## " and ((a.start_epoch >= :day0 and a.start_epoch < :dayEnd0) or ...)": the activity starts on one of the days.
  if days.len == 0:
    return
  var parts: seq[string]
  for i, d in days:
    let (a, b) = ("day" & $i, "dayEnd" & $i)
    parts.add fmt"(a.start_epoch >= :{a} and a.start_epoch < :{b})"
    result.args.add (a, arg(int64(d.start)))
    result.args.add (b, arg(int64(d.next)))
  result.text = " and (" & parts.join(" or ") & ")"

func rangeSql*(column, name: string, r: NumRange): Sql =
  ## " and a.distance_m >= :distanceLo and a.distance_m <= :distanceHi": the ends that are given, both inclusive.
  ## (Not recorded, NULL, is never in a range.)
  if r.lo.isSome:
    result.text.add " and " & column & " >= :" & name & "Lo"
    result.args.add (name & "Lo", arg(r.lo.get))
  if r.hi.isSome:
    result.text.add " and " & column & " <= :" & name & "Hi"
    result.args.add (name & "Hi", arg(r.hi.get))

func nearSql(
    centre: (float, float), km: float, idColumn, table, column, name: string
): Sql =
  ## " and (the row's box meets the circle's)", with the point and the radius bound as :NAMELon, :NAMELat and :NAMEM for
  ## the test of the distance that follows.
  let (lat, lon) = centre
  var probes: seq[string]
  for k, b in circleBoxes(lon, lat, km * 1000.0):
    let n = name & "Box" & $k
    probes.add inBox(
      idColumn,
      table,
      column,
      ":" & n & "West, :" & n & "South, :" & n & "East, :" & n & "North",
    )
    result.args.add (n & "West", arg(b.minX))
    result.args.add (n & "South", arg(b.minY))
    result.args.add (n & "East", arg(b.maxX))
    result.args.add (n & "North", arg(b.maxY))
  result.text = " and (" & probes.join(" or ") & ")"
  result =
    result.with(name & "Lon", lon).with(name & "Lat", lat).with(name & "M", km * 1000)

func matchSql*(
    userId: UserId,
    filters: seq[Resolved],
    columns = sqlOf("a.id"),
    invert = false,
    limit = none(Limit),
    among = amEvery,
): Sql =
  ## A query for the activities of the user `userId` that meet the filters, giving
  ## `columns` (of `a`, the activity, and `f`, its file).  The one place the
  ## criteria become SQL, used to list them, to count them and to save them.  Every value is bound by name (`sqltext.nim`).
  ## The filters are only `Resolved` ones: nothing in them is still to be found out.  `among` is where it looks: every
  ## activity, or only the selection (`--within`; `--invert` then means those of the selection that do not meet them).
  result =
    "select " & columns & " from activity a join file f on f.id = a.file_id " &
    "where f.user_id = :user"
  result = result.with("user", int64(userId))
  case among
  of amEvery:
    discard
  of amSelection:
    result =
      result &
      " and a.id in (select activity_id from activity_selection where user_id = :user)"
  var ordered = filters
  ordered.sort(
    proc(a, b: Resolved): int =
      cmp(ord(a.kind), ord(b.kind))
  )
  var filt = Sql()
    # the criteria, each as " and ...": with --invert, the whole is negated
  for f in ordered:
    case f.kind
    of rtNames:
      filt = filt & textSql("a.name", "name", f.typed, f.exact, f.ids)
    of rtStarts:
      filt = filt & textSql("a.start_place", "start", f.typed, f.exact)
    of rtPaths:
      filt = filt & pathSql(f.paths)
    of rtTags:
      filt = filt & tagsSql(f.tags)
    of rtCondition:
      filt = filt & sqlOf(" and (") & f.condition & sqlOf(")")
    of rtDistance:
      filt = filt & rangeSql("a.distance_m", "distance", f.range)
    of rtActive:
      filt = filt & rangeSql("a.timer_s", "active", f.range)
    of rtGps:
      case f.gps
      of gpsWith:
        filt = filt & " and exists (select 1 from track k where k.activity_id = a.id)"
      of gpsWithout:
        filt =
          filt & " and not exists (select 1 from track k where k.activity_id = a.id)"
    of rtAfter:
      filt = filt & sqlOf(" and a.start_epoch >= :afterT").with("afterT", int64(f.at))
    of rtBefore:
      filt = filt & sqlOf(" and a.start_epoch < :beforeT").with("beforeT", int64(f.at))
    of rtDates:
      filt = filt & datesSql(f.days)
    of rtFrom:
      # activities that START within the radius: the spatial index finds those in a box, and the distance on the ground
      # decides (an activity without a start is never near)
      filt =
        filt & nearSql((f.lat, f.lon), f.km, "a.id", "activity", "start_point", "start") &
        " and ST_Distance(a.start_point, MakePoint(:startLon, :startLat, 4326), 1) <= :startM"
    of rtNear:
      # activities whose ROUTE passes within the radius: the index of the routes (a route's row is its activity's id) finds
      # those whose box meets the circle's, and the distance on the ground from the point to the line decides (quickly:
      # `near/distance`)
      filt =
        filt & nearSql((f.lat, f.lon), f.km, "a.id", "route", "geom", "pass") &
        " and exists (select 1 from route r where r.activity_id = a.id and " &
        withinSql("r.geom", "pass", f.lat, f.km * 1000) & ")"
  # an activity that fails a test because a value is not recorded (null) fails to match, so it matches the inverse
  result =
    result & (
      if invert:
        " and not coalesce((1" & filt & "), 0)"
      else:
        filt
    )
  if limit.isSome:
    case limit.get.kind
    of lkNewest:
      result =
        result &
        sqlOf(" order by a.start_epoch desc limit :newest").with(
          "newest", limit.get.count
        )
    of lkOldest:
      result =
        result &
        sqlOf(" order by a.start_epoch asc limit :oldest").with(
          "oldest", limit.get.count
        )
