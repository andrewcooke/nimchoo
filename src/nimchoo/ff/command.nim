## `nch ff`: the fitness and fatigue curves of the current user (see curve.nim), as CSV on
## standard output for plotting elsewhere: one row per day (the value at the end of the day,
## in the computer's timezone), or per hour.
##
## This module is newer than `model`: it works out the impulses that are lacking, and reads them.

import std/[math, options, strutils, times]
import db_connector/db_sqlite
import ../cli/common
import ../db/store
import ../errors
import ../model/[calc, impulses, models]
import ./[curve, params]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] ff [--model NAME] [--from DAY] [--to DAY]
                                      [--hourly] [--utc] [--fitness-scale S] [--fatigue-scale S]

Print the fitness and fatigue of the user as CSV: one row a day, the value at the end of the
day (in this computer's timezone; --utc for UTC).  They are made from the impulses of the user's activities (see `nch user --fthr`
and `nch model`) with the decay times of the model.  They start from 0 at the first activity
with an impulse and run to --to (default: today), so they fade away after the last.

  --model NAME      the model to use (default: `default`)
  --from DAY        the first day to show, like 2018-08-27 (default: the first with an impulse)
  --to DAY          the last day to show (default: today)
  --hourly          one row an hour instead, labelled by the end of the hour (with its offset
                    from UTC: 2018-08-27T14:00:00-03:00)
  --utc             days and times in UTC, not this computer's timezone
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

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch ff ARGS`; returns the exit status.
  let p = parseArgs(args)
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
    st.begin()                                  # (the impulses that are lacking are worked out now)
    var committed = false
    try:
      discard calculateMissing(st.db, st.userId, m.get)
      st.commit()
      committed = true
    finally:
      if not committed: st.rollback()
    let impulses = hourlyImpulses(st.db, st.userId, m.get.id)
    if impulses.len == 0:
      return failure("nch ff", "there are no impulses for " & st.userName &
                     " (they need activities with heart rate: import some)")
    stdout.say "time,fitness,fatigue\n"
    for l in rows(impulses, m.get, p, getTime().toUnix, if p.utc: utc() else: local()): stdout.say l & "\n"
    exitOk
  except StoreError as e:
    failure("nch ff", e.msg)
