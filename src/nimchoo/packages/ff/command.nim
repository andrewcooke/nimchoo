## `nch ff`: the fitness and fatigue curves of the current user (see curve.nim), shown as a chart in the browser, or as CSV in
## the cache directory for plotting elsewhere (`--file`) or on standard output (`--stdout`): one row per day (the
## value at the end of the day, in the computer's timezone), or per hour.  A chart is a live view: the file is named by the
## options (`ff-model-1-hourly.csv`) and made again on every request, from the data as they are.
##
## This module is newer than `model`: it works out the impulses that are lacking, and reads them (one lump a stretch of
## riding, at its centre), and the curves are exact at the times shown (the ends of days or hours, and now).

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
import ../ui/style
import ./[page, params]
import ../model/[curve, stats]
import ../user/session

{.push raises: [].}

const commandName* = "ff" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch ff`, described (for tab completion).
  ffSpec().docs

const
  synopsis =
    """usage: nch [--db PATH] [--user NAME] ff [--model NAME] [--after DAY] [--before DAY]
                                      [--hourly] [--utc] [--stdout | --file | --stop | [--start] [--port N] [--new-token]]"""
  intro = @[
    ~"Show the user's fitness and fatigue as a chart: served on localhost and opened in a browser (one server serves every page, and keeps running after the command returns: `--stop` stops it).  With `--file` the data are made as a CSV file in the cache directory instead, and its path is printed, then the latest values of the two curves, each with the share of the earlier days on which it was higher (\"top 1%\" means the value is nearly the highest it has been): 2026-11-03 15:00  fitness: 71.5 (top 4%),  fatigue: 18.5 (top 56%).  One row a day, the value at the end of the day (in this computer's timezone; `--utc` for UTC).  They are made from the impulses of the user's activities (see `nch users --edit NAME --fthr` and `nch models`) with the decay times and the scales of the model, counting the activities whose tags it chooses.  They start from 0 at the first activity with an impulse and run up to `--before` (default: the end of today), so they fade away after the last."
  ]
  notes = @[
    ~"The file is made again each time, from the data as they are then; its name is made from the options (`ff-model-1-hourly.csv`), so charts with different options do not overwrite each other."
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the notes and the options, wrapped to `width`.
  usageOf(synopsis, width, intro, ffSpec().docs, notes)

proc rows*(
    lumps: seq[Lump], m: Model, p: Params, now: int64, tz: Timezone
): seq[string] =
  ## The CSV lines (without the header) for the impulses (in time order).  Days are those of the timezone; a daily row is
  ## the value at the end of the day, labelled with the date, an hourly one that at the end of the hour, labelled with it.
  if lumps.len == 0:
    return
  let toCivil =
    if p.lastDay.isSome:
      p.lastDay.get
    else:
      civilOf(now, tz)
  let times =
    if p.hourly:
      hourEnds(lumps[0].t, dayStart(toCivil + secondsPerDay, tz))
    else:
      dayEnds(lumps[0].t, toCivil, tz)
  let fitness = curveAt(lumps, m.fitnessDays, times)
  let fatigue = curveAt(lumps, m.fatigueDays, times)
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
  for k, finish in times:
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
    let fit = formatFloat(fitness[k] * m.fitnessScale, ffDecimal, 4)
    let fat = formatFloat(fatigue[k] * m.fatigueScale, ffDecimal, 4)
    result.add fmt"{label},{fit},{fat}"

proc csv(lumps: seq[Lump], m: Model, p: Params, now: int64, tz: Timezone): string =
  result = "time,fitness,fatigue\n"
  for l in rows(lumps, m, p, now, tz):
    result.add l & "\n"

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

proc makeCsv(lumps: seq[Lump], m: Model, p: Params, now: int64, tz: Timezone): string =
  ## The CSV of the impulses (worked out and read once, `ensureImpulses` and `userLumps`: the file and the line about the
  ## latest values come from the same state of the database).
  csv(lumps, m, p, now, tz)

proc latestStats(
    lumps: seq[Lump], m: Model, p: Params, now: int64, tz: Timezone
): Line =
  ## The line about the latest values (see stats.nim): for today, as of now (the label is the date and time); for an
  ## earlier last day (`--before` the next), at the end of it (the date).  Each is compared with the ends of the days
  ## before.  `p.lastDay` is set.
  let today = civilOf(now, tz)
  var asOf, day: int64
  var label: string
  if p.lastDay.get >= today:
    asOf = now
    day = today
    label =
      fmt"""{localDate(today, utc())} {fromUnix(now).inZone(tz).format("HH:mm")}"""
  else:
    day = p.lastDay.get
    asOf = dayStart(day + secondsPerDay, tz)
    label = localDate(day, utc())
  if lumps.len == 0 or lumps[0].t > asOf:
    return
      statLine(label, none(Standing), none(Standing), m.fitnessScale, m.fatigueScale)
  let times = dayEnds(lumps[0].t, day - secondsPerDay, tz) & @[asOf]
  proc standingFor(tauDays: float): Option[Standing] =
    let v = curveAt(lumps, tauDays, times)
    some(standing(v[^1], v[0 ..^ 2]))

  statLine(
    label,
    standingFor(m.fitnessDays),
    standingFor(m.fatigueDays),
    m.fitnessScale,
    m.fatigueScale,
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
  q.join("&")

proc stemOf(p: Params, model: ModelId): string =
  ## What the files are named: the command, the model's number (a name may hold what a file name may not) and the options
  ## given (`ff-model-1-to-2026-11-14-hourly`).  Charts with other options are other files.
  var parts = @[commandName, fmt"model-{model}"]
  if p.firstDay.isSome:
    parts.add "from-" & localDate(p.firstDay.get, utc())
  if p.lastDay.isSome:
    parts.add "to-" & localDate(p.lastDay.get, utc())
  if p.hourly:
    parts.add "hourly"
  if p.utc:
    parts.add "utc"
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
      return failure(g, "nch ff", ~"no such model: {name} (see `nch models --all`)")
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
    var impulses: seq[Lump]
    if p.stdout or p.web.kind != wkServe:
      # (the chart that is served is made by the worker, when the page is asked for)
      ensureImpulses(st, m.get)
      impulses = userLumps(st.db, st.userId, m.get)
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
    let stem = stemOf(parsed.params, m.get.id)
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
