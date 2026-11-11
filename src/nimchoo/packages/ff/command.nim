## `nch ff`: the fitness and fatigue curves of the current user (see curve.nim), as CSV on
## in the cache directory for plotting elsewhere (or on standard output): one row per day (the
## value at the end of the day, in the computer's timezone), or per hour.  The file is named
## by a hash of the request: the options, with the defaults spelt out, and the state of everything the curves depend on (the
## FTHR, the model, the activities with heart rate), so a file that exists is current and is not made again.
##
## This module is newer than `model`: it works out the impulses that are lacking, and reads them.

import std/[math, options, os, strutils, times]
import ../../core/globals
import ../cache/cache
import ../util/atomic/atomic
import ../db/statement
import ../db/store
import ../../core/errors
import ../model/calc
import ../model/impulses
import ../model/models
import ../util/args/[args, usage]
import ../web/launch
import ../web/pages
import ../web/webopts
import ../ui/live
import ../ui/[style, units]
import ./[curve, page, params, stats]
import ../user/session

{.push raises: [].}

const commandName* = "ff" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch ff`, described (for tab completion).
  ffSpec().docs

const
  synopsis =
    """usage: nch [--db PATH] [--user NAME] ff [--model NAME] [--from DAY] [--to DAY]
                                      [--hourly] [--utc] [--stdout | --worker | --web]
                                      [--fitness-scale S] [--fatigue-scale S]"""
  intro =
    """Make a CSV file of the user's fitness and fatigue in the cache directory, and print its path, then the latest
values of the two curves, each with the share of the earlier days on which it was higher ("top 1%" means the value is
nearly the highest it has been): 2026-11-03 15:00  fitness: 71.5 (top 4%),  fatigue: 18.5 (top 56%).  One row a day,
the value at the end of the day (in this computer's timezone; --utc for UTC).  They are made from the impulses of the
user's activities (see `nch users --edit NAME --fthr` and `nch models`) with the decay times of the model.  They start
from 0 at the first activity with an impulse and run to --to (default: today), so they fade away after the last."""
  notes =
    """The file is named by a hash of the options and of the data it is made from, so if it is already there nothing is done:
it cannot be out of date.  (A new --to, an import or a new FTHR means a new file; old ones are not deleted.)"""

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction, the notes and the options, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" & prose(notes, width) & "\n\n" &
    optionLines(ffSpec().docs, width).join("\n") & "\n"

proc hourlyImpulses(
    db: DbConn, userId: UserId, modelId: ModelId
): seq[Hourly] {.raises: [StoreError].} =
  ## The user's impulse in each hour, over all their activities.
  db.query(
    Hourly,
    """select i.hour_t, sum(i.value) from impulse i
        join activity a on a.id = i.activity_id join file f on f.id = a.file_id
        where f.user_id = :userId and i.model_id = :modelId group by i.hour_t order by i.hour_t""",
    userId = userId,
    modelId = modelId,
  )

proc civilOf(t: int64, tz: Timezone): int64 =
  ## The date at an instant in a timezone, as Unix seconds at its start in UTC (the form of
  ## `Params.fromDay`).
  let d = fromUnix(t).inZone(tz)
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, 0, utc()).toTime.toUnix

proc dayStart(civil: int64, tz: Timezone): int64 =
  ## The instant a calendar date starts in a timezone.
  let d = fromUnix(civil).utc
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, 0, tz).toTime.toUnix

proc rows*(
    impulses: seq[Hourly], m: Model, p: Params, now: int64, tz: Timezone
): seq[string] =
  ## The CSV lines (without the header) for the impulses.  Days are those of the timezone; a
  ## daily row is labelled with the date, an hourly one with the time at the end of the hour.
  let toCivil =
    if p.toDay.isSome:
      p.toDay.get
    else:
      civilOf(now, tz)
  let midnight = dayStart(toCivil + secondsPerDay, tz) # the end of the last day
  let last = floorDiv(midnight, bucketSeconds) * bucketSeconds - bucketSeconds
  var fitness = response(impulses, m.fitnessDays, last)
  var fatigue = response(impulses, m.fatigueDays, last)
  if not p.hourly:
    fitness = dayEnds(fitness, tz)
    fatigue = dayEnds(fatigue, tz)
  let firstDay =
    if p.fromDay.isSome:
      localDate(p.fromDay.get, utc())
    else:
      ""
  let firstInstant =
    if p.fromDay.isSome:
      dayStart(p.fromDay.get, tz)
    else:
      low(int64)
  for k in 0 ..< fitness.len:
    let finish = fitness[k].hourT + bucketSeconds
    let label =
      if p.hourly:
        fromUnix(finish).inZone(tz).format("yyyy-MM-dd'T'HH:mm:sszzz")
      else:
        localDate(finish - 1, tz)
    if p.hourly:
      if finish <= firstInstant:
        continue
    elif label < firstDay:
      continue
    result.add label & "," & formatFloat(
      fitness[k].value * p.fitnessScale, ffDecimal, 4
    ) & "," & formatFloat(fatigue[k].value * p.fatigueScale, ffDecimal, 4)

proc zoneName(tz: Timezone, p: Params, toCivil: int64, isUtc: bool): string =
  ## What goes in a file name to tell timezones apart: "utc", or the offset east of UTC, in
  ## seconds, at the end of the last day ("east-10800").
  if isUtc:
    return "utc"
  "east" & $(-fromUnix(dayStart(toCivil, tz)).inZone(tz).utcOffset)

func scaleText(x: float): string =
  $x

proc csv(impulses: seq[Hourly], m: Model, p: Params, now: int64, tz: Timezone): string =
  result = "time,fitness,fatigue\n"
  for l in rows(impulses, m, p, now, tz):
    result.add l & "\n"

proc ensureImpulses(st: Session, m: Model) {.raises: [StoreError].} =
  ## Work out the impulses that are lacking (in one transaction).
  st.begin()
  var committed = false
  try:
    discard calculateMissing(st.db, st.userId, m)
    st.commit()
    committed = true
  finally:
    if not committed:
      st.rollback()

proc makeCsv(
    st: Session, m: Model, p: Params, now: int64, tz: Timezone
): string {.raises: [StoreError].} =
  ## The CSV, after working out the impulses that are lacking.
  ensureImpulses(st, m)
  csv(hourlyImpulses(st.db, st.userId, m.id), m, p, now, tz)

proc latestStats(
    st: Session, m: Model, p: Params, now: int64, tz: Timezone
): Line {.raises: [StoreError].} =
  ## The line about the latest values (see stats.nim): for today, as of the last whole hour (the
  ## label is the date and time); for an earlier last day (`--to`), at the end of it (the date).
  ## `p.toDay` is set.
  ensureImpulses(st, m)
  let impulses = hourlyImpulses(st.db, st.userId, m.id)
  let today = civilOf(now, tz)
  let nowHour = floorDiv(now, bucketSeconds) * bucketSeconds
  var asOf: int64
  var day: int64
  var label: string
  if p.toDay.get >= today:
    asOf = nowHour - bucketSeconds
    day = today
    label =
      localDate(today, utc()) & " " &
      fromUnix(asOf + bucketSeconds).inZone(tz).format("HH:mm")
  else:
    day = p.toDay.get
    asOf =
      floorDiv(dayStart(day + secondsPerDay, tz), bucketSeconds) * bucketSeconds -
      bucketSeconds
    label = localDate(day, utc())
  let fitness = response(impulses, m.fitnessDays, asOf)
  let fatigue = response(impulses, m.fatigueDays, asOf)
  statLine(
    label,
    standingAt(fitness, asOf, dayStart(day, tz), tz),
    standingAt(fatigue, asOf, dayStart(day, tz), tz),
    p.fitnessScale,
    p.fatigueScale,
  )

proc webQuery*(p: Params): string =
  ## What the address of the chart says: the options given (before the defaults are filled in,
  ## so that a page asked for tomorrow is tomorrow's).  See serve/request.nim for the names.
  var q: seq[string]
  if p.model.isSome:
    q.add "model=" & p.model.get
  if p.fromDay.isSome:
    q.add "from=" & localDate(p.fromDay.get, utc())
  if p.toDay.isSome:
    q.add "to=" & localDate(p.toDay.get, utc())
  if p.hourly:
    q.add "hourly=1"
  if p.utc:
    q.add "utc=1"
  if p.fitnessScale != 1:
    q.add "fitness-scale=" & plainNumber(p.fitnessScale)
  if p.fatigueScale != 1:
    q.add "fatigue-scale=" & plainNumber(p.fatigueScale)
  q.join("&")

proc pinnedQuery(p: Params, name, state: string): string =
  ## The address that names this chart exactly: every parameter that was left to a default is spelt out (the model, the
  ## last day), and the state of the data is added.  `p.toDay` is set.
  var q = @["state=" & state, "model=" & name]
  if p.fromDay.isSome:
    q.add "from=" & localDate(p.fromDay.get, utc())
  q.add "to=" & localDate(p.toDay.get, utc())
  if p.hourly:
    q.add "hourly=1"
  if p.utc:
    q.add "utc=1"
  if p.fitnessScale != 1:
    q.add "fitness-scale=" & plainNumber(p.fitnessScale)
  if p.fatigueScale != 1:
    q.add "fatigue-scale=" & plainNumber(p.fatigueScale)
  q.join("&")

proc requestOf(p: Params, name, state: string, tz: Timezone): string =
  ## What the files are named after: the pinned address, and the zone it was worked out in (a computer's zone is not in
  ## the address, and a chart in another zone is another chart).
  pinnedQuery(p, name, state) & "&zone=" & zoneName(tz, p, p.toDay.get, p.utc)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch ff ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch ff", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  var p = parsed.params
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure("nch ff", e.msg)
  try:
    let name = p.model.get("default")
    let m = findModel(st.db, name)
    if m.isNone:
      return failure("nch ff", "no such model: " & name & " (see `nch models`)")
    if fthrOf(st.db, st.userId).isNone:
      return failure(
        "nch ff",
        st.userName & " has no FTHR, which the impulse calculations require " &
          "(set it with `nch users --edit " & st.userName & " --fthr BPM`)",
      )
    let current = inputKey(st.db, st.userId, m.get)
    if current.len == 0:
      return failure(
        "nch ff",
        "there are no impulses for " & st.userName &
          " (they need activities with heart rate: import some)",
      )
    let key = p.state.get(current)
    let now = getTime().toUnix
    let tz =
      if p.utc:
        utc()
      else:
        local()
    if p.toDay.isNone:
      p.toDay = some(civilOf(now, tz)) # (so that the name says which day)
    let changed =
      "the data have changed since that was made (the key was " & key & ", it is now " &
      current & "); leave out --state to use the current data"
    if p.stdout:
      if key != current:
        return failure("nch ff", changed)
      stdout.say makeCsv(st, m.get, p, now, tz)
      return exitOk
    let dir = cacheDir()
    let stem = requestStem(commandName, requestOf(p, name, key, tz))
    if dir.isNone or stem.isNone:
      return failure(
        "nch ff",
        "no cache directory is known (set NCH_CACHE), or the options " &
          "cannot be made into a file name; use --stdout",
      )
    # (the paths are kept in `let`s: `.get` on a temporary Option that is assigned on to a `var` has
    # left a dangling string here, with this compiler)
    let files = userDir(dir.get)
    let csvFile = cacheFile(files, stem.get, "csv")
    let pageFile = cacheFile(files, stem.get, "html")
    let csvPath = csvFile.get
    try:
      makeCacheDirs(dir.get)
      if not fileExists(csvPath): # (made before from the same data: nothing to do)
        if key != current:
          return failure("nch ff", changed)
        writeAtomic(csvPath, makeCsv(st, m.get, p, now, tz))
      if p.web.kind != wkNone:
        # the page is rewritten each time (it is tiny, and may have changed since)
        let html = pageHtml(
          extractFilename(csvPath), "Fitness and fatigue, model " & name, p.hourly
        )
        if html.isNone:
          return failure("nch ff", "cannot make a page for " & csvPath)
        writeAtomic(pageFile.get, html.get)
    except IOError, OSError:
      return failure(
        "nch ff", "cannot write to " & dir.get & ": " & getCurrentExceptionMsg()
      )
    except TemplateError as e:
      return failure(
        "nch ff",
        "cannot make the page: " & e.msg & " (the template is " &
          "system/templates/ff.html and the libraries are system/libraries.txt, in the cache directory; " &
          "delete one to have the built-in one again)",
      )
    if p.web.kind == wkServe:
      return serveWeb(
        g,
        commandName,
        WebOptions(port: p.web.port, noOpen: p.web.noOpen, newToken: p.web.newToken),
        dir.get,
        pinnedQuery(p, name, key),
      )
    if p.web.kind == wkWorker:
      stdout.say pageFile.get & "\n" & csvPath & "\n" & pinnedQuery(p, name, key) & "\n"
      return exitOk
    stdout.say csvPath & "\n"
    if key == current: # (the latest values are of the current data)
      let colour = canColourStdout()
      stdout.say render(latestStats(st, m.get, p, now, tz), colour) & "\n"
    exitOk
  except StoreError as e:
    failure("nch ff", e.msg)
