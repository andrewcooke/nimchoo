## `nch ff`: the fitness and fatigue curves of the current user (see curve.nim), as CSV on
## in the cache directory for plotting elsewhere (or on standard output): one row per day (the
## value at the end of the day, in the computer's timezone), or per hour.  The file is named
## after the options and a key made of everything the curves depend on (the FTHR, the model, the
## activities with heart rate), so a file that exists is current and is not made again.
##
## This module is newer than `model`: it works out the impulses that are lacking, and reads them.

import std/[math, options, os, strutils, times]
import db_connector/db_sqlite
import ../cli/common
import ../cache
import ../db/store
import ../errors
import ../model/[calc, impulses, models]
import ./[curve, params]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] ff [--model NAME] [--from DAY] [--to DAY]
                                      [--hourly] [--utc] [--stdout]
                                      [--fitness-scale S] [--fatigue-scale S]

Make a CSV file of the user's fitness and fatigue in the cache directory, and print its path.
One row a day, the value at the end of the day (in this computer's timezone; --utc for UTC).
They are made from the impulses of the user's activities (see `nch user --fthr` and
`nch model`) with the decay times of the model.  They start from 0 at the first activity with
an impulse and run to --to (default: today), so they fade away after the last.

The file is named after the options and after the data it is made from, so if it is already
there nothing is done: it cannot be out of date.  (A new --to, an import or a new FTHR means
a new file; old ones are not deleted.)

  --model NAME      the model to use (default: `default`)
  --from DAY        the first day to show, like 2018-08-27 (default: the first with an impulse)
  --to DAY          the last day to show (default: today)
  --hourly          one row an hour instead, labelled by the end of the hour (with its offset
                    from UTC: 2018-08-27T14:00:00-03:00)
  --utc             days and times in UTC, not this computer's timezone
  --stdout          print the CSV instead of making a file
  --fitness-scale S multiply the fitness by S (default 1)
  --fatigue-scale S multiply the fatigue by S (default 1; the original program used 5, to
                    make the two curves look alike)
  -h, --help        show this help
"""

proc hourlyImpulses(db: DbConn, userId, modelId: int64): seq[Hourly] {.raises: [StoreError].} =
  ## The user's impulse in each hour, over all their activities.
  guard:
    for r in db.fastRows(sql"""select i.hour_t, sum(i.value) from impulse i
        join activity a on a.id = i.activity_id join file f on f.id = a.file_id
        where f.user_id = ? and i.model_id = ? group by i.hour_t order by i.hour_t""", userId, modelId):
      try: result.add (parseBiggestInt(r[0]), parseFloat(r[1]))
      except ValueError: raiseStore("bad impulse row")

proc civilOf(t: int64, tz: Timezone): int64 =
  ## The date at an instant in a timezone, as Unix seconds at its start in UTC (the form of
  ## `Params.fromDay`).
  let d = fromUnix(t).inZone(tz)
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, 0, utc()).toTime.toUnix

proc dayStart(civil: int64, tz: Timezone): int64 =
  ## The instant a calendar date starts in a timezone.
  let d = fromUnix(civil).utc
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, 0, tz).toTime.toUnix

proc rows*(impulses: seq[Hourly], m: Model, p: Params, now: int64, tz: Timezone): seq[string] =
  ## The CSV lines (without the header) for the impulses.  Days are those of the timezone; a
  ## daily row is labelled with the date, an hourly one with the time at the end of the hour.
  let toCivil = if p.toDay.isSome: p.toDay.get else: civilOf(now, tz)
  let midnight = dayStart(toCivil + secondsPerDay, tz)          # the end of the last day
  let last = floorDiv(midnight, bucketSeconds) * bucketSeconds - bucketSeconds
  var fitness = response(impulses, m.fitnessDays, last)
  var fatigue = response(impulses, m.fatigueDays, last)
  if not p.hourly:
    fitness = dayEnds(fitness, tz)
    fatigue = dayEnds(fatigue, tz)
  let firstDay = if p.fromDay.isSome: localDate(p.fromDay.get, utc()) else: ""
  let firstInstant = if p.fromDay.isSome: dayStart(p.fromDay.get, tz) else: low(int64)
  for k in 0 ..< fitness.len:
    let finish = fitness[k].hourT + bucketSeconds
    let label = if p.hourly: fromUnix(finish).inZone(tz).format("yyyy-MM-dd'T'HH:mm:sszzz")
                else: localDate(finish - 1, tz)
    if p.hourly:
      if finish <= firstInstant: continue
    elif label < firstDay: continue
    result.add label & "," & formatFloat(fitness[k].value * p.fitnessScale, ffDecimal, 4) &
      "," & formatFloat(fatigue[k].value * p.fatigueScale, ffDecimal, 4)

proc zoneName(tz: Timezone, p: Params, toCivil: int64, isUtc: bool): string =
  ## What goes in a file name to tell timezones apart: "utc", or the offset east of UTC, in
  ## seconds, at the end of the last day ("east-10800").
  if isUtc: return "utc"
  "east" & $(-fromUnix(dayStart(toCivil, tz)).inZone(tz).utcOffset)

func scaleText(x: float): string = $x

proc write(path, text: string) {.raises: [IOError, OSError].} =
  ## Write the file so that nobody sees half of it: to a new name, then rename.
  createDir parentDir(path)
  let tmp = path & ".part"
  writeFile(tmp, text)
  try:
    moveFile(tmp, path)
  except OSError as e:
    raise e
  except Exception:              # (moveFile is declared to raise anything)
    raise newException(OSError, "cannot rename " & tmp)

proc csv(impulses: seq[Hourly], m: Model, p: Params, now: int64, tz: Timezone): string =
  result = "time,fitness,fatigue\n"
  for l in rows(impulses, m, p, now, tz): result.add l & "\n"

proc makeCsv(st: Store, m: Model, p: Params, now: int64, tz: Timezone): string
    {.raises: [StoreError].} =
  ## The CSV, after working out the impulses that are lacking (in one transaction).
  st.begin()
  var committed = false
  try:
    discard calculateMissing(st.db, st.userId, m)
    st.commit()
    committed = true
  finally:
    if not committed: st.rollback()
  csv(hourlyImpulses(st.db, st.userId, m.id), m, p, now, tz)

proc cacheName(p: Params, name, key: string, tz: Timezone): Option[string] =
  ## The path of the file for the options and the data, if one can be made.
  var options = @[("key", key), ("model", name), ("res", if p.hourly: "hour" else: "day"),
                  ("to", localDate(p.toDay.get, utc())),
                  ("tz", zoneName(tz, p, p.toDay.get, p.utc)),
                  ("fitscale", scaleText(p.fitnessScale)), ("fatscale", scaleText(p.fatigueScale))]
  if p.fromDay.isSome: options.add ("from", localDate(p.fromDay.get, utc()))
  let stem = fileStem("ff", options)
  let dir = cacheDir()
  if stem.isNone or dir.isNone: return none(string)
  cacheFile(dir.get, stem.get, "csv")

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch ff ARGS`; returns the exit status.
  var p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch ff", usage, p.problem)
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch ff", e.msg)
  defer: st.close()
  try:
    let name = if p.model.len > 0: p.model else: "default"
    let m = findModel(st.db, name)
    if m.isNone: return failure("nch ff", "no such model: " & name & " (see `nch model`)")
    if fthrOf(st.db, st.userId).isNone:
      return failure("nch ff", st.userName & " has no FTHR, which the impulses are worked out from " &
                     "(see `nch user --fthr`)")
    let key = inputKey(st.db, st.userId, m.get)
    if key.len == 0:
      return failure("nch ff", "there are no impulses for " & st.userName &
                     " (they need activities with heart rate: import some)")
    let now = getTime().toUnix
    let tz = if p.utc: utc() else: local()
    if p.toDay.isNone: p.toDay = some(civilOf(now, tz))     # (so that the name says which day)
    if p.stdout:
      stdout.say makeCsv(st, m.get, p, now, tz)
      return exitOk
    let file = cacheName(p, name, key, tz)
    if file.isNone:
      return failure("nch ff", "no cache directory is known (set NCH_CACHE), or the options " &
                     "cannot be made into a file name; use --stdout")
    if not fileExists(file.get):                          # (made before from the same data: nothing to do)
      let text = makeCsv(st, m.get, p, now, tz)
      try:
        write(file.get, text)
      except IOError, OSError:
        return failure("nch ff", "cannot write " & file.get & ": " & getCurrentExceptionMsg())
    stdout.say file.get & "\n"
    exitOk
  except StoreError as e:
    failure("nch ff", e.msg)
