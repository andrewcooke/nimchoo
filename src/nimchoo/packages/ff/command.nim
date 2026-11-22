## `nch ff`: the fitness and fatigue curves of the current user (see curve.nim), shown as a chart in the browser, or as CSV in
## the cache directory for plotting elsewhere (`--file`) or on standard output (`--stdout`): one row per day (the
## value at the end of the day, in the computer's timezone), or per hour.  A chart is a live view: the file is named by the
## options (`ff-default-hourly.csv`) and made again on every request, from the data as they are.
##
## This module is newer than `model`: it works out the impulses that are lacking, and reads them.

import std/[math, options, os, strformat, strutils, times]
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
    """usage: nch [--db PATH] [--user NAME] ff [--model NAME] [--after DAY] [--before DAY]
                                      [--hourly] [--utc] [--stdout | --file | --stop | [--start] [--port N] [--new-token]]
                                      [--fitness-scale S] [--fatigue-scale S]"""
  intro = @[
    ~"Show the user's fitness and fatigue as a chart: served on localhost and opened in a browser (one server serves every page, and keeps running after the command returns: `--stop` stops it).  With `--file` the data are made as a CSV file in the cache directory instead, and its path is printed, then the latest values of the two curves, each with the share of the earlier days on which it was higher (\"top 1%\" means the value is nearly the highest it has been): 2026-11-03 15:00  fitness: 71.5 (top 4%),  fatigue: 18.5 (top 56%).  One row a day, the value at the end of the day (in this computer's timezone; `--utc` for UTC).  They are made from the impulses of the user's activities (see `nch users --edit NAME --fthr` and `nch models`) with the decay times of the model.  They start from 0 at the first activity with an impulse and run up to `--before` (default: the end of today), so they fade away after the last."
  ]
  notes = @[
    ~"The file is made again each time, from the data as they are then; its name is made from the options (`ff-default-hourly.csv`), so charts with different options do not overwrite each other."
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the notes and the options, wrapped to `width`.
  usageOf(synopsis, width, intro, ffSpec().docs, notes)

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
  ## `Params.firstDay`).
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
    if p.lastDay.isSome:
      p.lastDay.get
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
    if p.firstDay.isSome:
      localDate(p.firstDay.get, utc())
    else:
      ""
  let firstInstant =
    if p.firstDay.isSome:
      dayStart(p.firstDay.get, tz)
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
    let fit = formatFloat(fitness[k].value * p.fitnessScale, ffDecimal, 4)
    let fat = formatFloat(fatigue[k].value * p.fatigueScale, ffDecimal, 4)
    result.add fmt"{label},{fit},{fat}"

proc csv(impulses: seq[Hourly], m: Model, p: Params, now: int64, tz: Timezone): string =
  result = "time,fitness,fatigue\n"
  for l in rows(impulses, m, p, now, tz):
    result.add fmt"{l}\n"

proc ensureImpulses(st: Session, m: Model) {.raises: [StoreError].} =
  ## Work out the impulses that are lacking (in one transaction).
  st.beginWrite()
  var committed = false
  try:
    discard calculateMissing(st.db, st.userId, m)
    st.commit()
    committed = true
  finally:
    if not committed:
      st.rollback()

proc makeCsv(
    impulses: seq[Hourly], m: Model, p: Params, now: int64, tz: Timezone
): string =
  ## The CSV of the impulses (worked out and read once, `ensureImpulses` and `hourlyImpulses`: the file and the line about the
  ## latest values come from the same state of the database).
  csv(impulses, m, p, now, tz)

proc latestStats(
    impulses: seq[Hourly], m: Model, p: Params, now: int64, tz: Timezone
): Line =
  ## The line about the latest values (see stats.nim): for today, as of the last whole hour (the
  ## label is the date and time); for an earlier last day (`--before` the next), at the end of it (the date).
  ## `p.lastDay` is set.
  let today = civilOf(now, tz)
  let nowHour = floorDiv(now, bucketSeconds) * bucketSeconds
  var asOf: int64
  var day: int64
  var label: string
  if p.lastDay.get >= today:
    asOf = nowHour - bucketSeconds
    day = today
    label =
      fmt"""{localDate(today, utc())} {fromUnix(asOf + bucketSeconds).inZone(tz).format("HH:mm")}"""
  else:
    day = p.lastDay.get
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
  if p.firstDay.isSome:
    q.add "after=" & localDate(p.firstDay.get, utc())
  if p.lastDay.isSome:
    q.add "before=" & localDate(p.lastDay.get + secondsPerDay, utc())
  if p.hourly:
    q.add "hourly=1"
  if p.utc:
    q.add "utc=1"
  if p.fitnessScale != 1:
    q.add "fitness-scale=" & plainNumber(p.fitnessScale)
  if p.fatigueScale != 1:
    q.add "fatigue-scale=" & plainNumber(p.fatigueScale)
  q.join("&")

proc stemOf(p: Params, model: string): string =
  ## What the files are named: the command, the model and the options given (`ff-default-hourly-to-2026-11-14`).  Charts with
  ## other options are other files.
  var parts = @[commandName, model]
  if p.firstDay.isSome:
    parts.add "from-" & localDate(p.firstDay.get, utc())
  if p.lastDay.isSome:
    parts.add "to-" & localDate(p.lastDay.get, utc())
  if p.hourly:
    parts.add "hourly"
  if p.utc:
    parts.add "utc"
  if p.fitnessScale != 1:
    parts.add "fitness-scale-" & plainNumber(p.fitnessScale)
  if p.fatigueScale != 1:
    parts.add "fatigue-scale-" & plainNumber(p.fatigueScale)
  parts.join("-")

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch ff ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch ff", usageText(g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch ff", parsed.fix, run)
  of pkOk:
    discard
  var p = parsed.params
  if p.web.kind == wkStop:
    # (the server is shared by every page: nothing of the chart is needed to stop it)
    let dir = cacheDir()
    if dir.isNone:
      return failure(g, "nch ff", noCacheDir)
    return stopWeb(g, commandName, p.web.stopPort, dir.get)
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure(g, "nch ff", e.msg)
  try:
    let name = p.model.get("default")
    let m = findModel(st.db, name)
    if m.isNone:
      return failure(g, "nch ff", ~"no such model: {name} (see `nch models`)")
    if fthrOf(st.db, st.userId).isNone:
      return failure(
        g,
        "nch ff",
        ~"{st.userName} has no FTHR, which the impulse calculations require (set it with `nch users --edit {st.userName} --fthr BPM`)",
      )
    if not hasHeartRate(st.db, st.userId):
      return failure(
        g,
        "nch ff",
        ~"there are no impulses for {st.userName} (they need activities with heart rate: import some)",
      )
    let now = getTime().toUnix
    let tz =
      if p.utc:
        utc()
      else:
        local()
    if p.lastDay.isNone:
      p.lastDay = some(civilOf(now, tz)) # (the last day: today, when the chart is made)
    var impulses: seq[Hourly]
    if p.stdout or p.web.kind != wkServe:
      # (the chart that is served is made by the worker, when the page is asked for)
      ensureImpulses(st, m.get)
      impulses = hourlyImpulses(st.db, st.userId, m.get.id)
    if p.stdout:
      g.say osOut, makeCsv(impulses, m.get, p, now, tz)
      return exitOk
    let dir = cacheDir()
    if dir.isNone:
      return failure(g, "nch ff", ~"{noCacheDir}; use `--stdout`")
    if p.web.kind == wkServe:
      # the chart is made by the worker, whenever the page is asked for
      return serveWeb(
        g,
        commandName,
        WebOptions(port: p.web.port, start: p.web.start, newToken: p.web.newToken),
        dir.get,
        commandName,
        webQuery(parsed.params),
      )
    let stem = stemOf(parsed.params, name)
    if not isFileStem(stem):
      return failure(
        g,
        "nch ff",
        ~"the model's name cannot be made into a file name (letters, digits and . _ , - only): {name}",
      )
    # (the paths are kept in `let`s: `.get` on a temporary Option that is assigned on to a `var` has
    # left a dangling string here, with this compiler)
    let files = userDir(dir.get)
    let csvFile = cacheFile(files, stem, "csv")
    let pageFile = cacheFile(files, stem, "html")
    let csvPath = csvFile.get
    try:
      makeCacheDirs(dir.get)
      writeAtomic(csvPath, makeCsv(impulses, m.get, p, now, tz))
      if p.web.kind == wkWorker:
        let html = pageHtml(
          extractFilename(csvPath), fmt"Fitness and fatigue, model {name}", p.hourly
        )
        writeAtomic(pageFile.get, html)
    except IOError, OSError:
      return cannotWrite(g, "nch ff", dir.get)
    except TemplateError as e:
      return templateFailure(g, "nch ff", e.msg)
    if p.web.kind == wkWorker:
      g.show(osOut, ~"<file {pageFile.get}>")
      g.show(osOut, ~"<file {csvPath}>")
      return exitOk
    g.show(osOut, ~"<file {csvPath}>")
    g.show(osOut, latestStats(impulses, m.get, p, now, tz))
    exitOk
  except StoreError as e:
    failure(g, "nch ff", e.msg)
  finally:
    st.close()
