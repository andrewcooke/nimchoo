## How far the stored hourly impulses, and one impulse per activity, are from an impulse worked out by the minute, in the
## fitness and fatigue at the end of every day of the author's history (dev/ff.md: the rework's first step).  Reads the
## database (the default one, or NCH_DB) and changes nothing.  Default model, the default user's FTHR.
##
##     nim c -r -d:release tools/ffcompare.nim

import std/[algorithm, math, options, strformat, times]
import nimchoo/core/ids
import nimchoo/packages/db/[statement, store]
import nimchoo/packages/heartrate/stored
import nimchoo/packages/model/[calc, impulses]
from nimchoo/registry import allFragments, allAccess

type Event = tuple[t, v: float] ## a lump of impulse at an instant (Unix seconds)

proc curve(events: seq[Event], tau: float, at: seq[float]): seq[float] =
  ## The curve (each lump fading with decay time `tau` seconds) at each time of `at` (in order).
  var y = 0.0
  var t =
    if events.len > 0:
      events[0].t
    else:
      0.0
  var k = 0
  for a in at:
    while k < events.len and events[k].t <= a:
      y = y * exp(-(events[k].t - t) / tau) + events[k].v
      t = events[k].t
      inc k
    result.add y * exp(-(a - t) / tau)

proc main() =
  let st = openReadOnly(resolveDbPath(none(string)), allFragments, allAccess)
  let user = UserId(st.db.scalar(int64, "select id from user where is_default = 1"))
  let fthr = fthrOf(st.db, user).get
  let m = defaultModel()
  var minute, hour, starts, middles, ends, centres, stretches: seq[Event]
  var spans: seq[(float, float)] ## each activity's first and last reading
  for id in st.db.query(
    int64, "select activity_id from heartrate_series order by activity_id"
  ):
    let r = readReadings(st.db, ActivityId(id))
    if r.len < 2:
      continue
    var total, weighted = 0.0
    for (b, v) in bucketImpulse(r, fthr, m, 60):
      minute.add (float(b + 60), v)
      total += v
      weighted += v * float(b + 30)
    for (b, v) in bucketImpulse(r, fthr, m, 3600):
      hour.add (float(b + 3600), v)
    # one impulse for each stretch of riding (`segment`), at its centre: the minutes are put to the stretch they are in
    let segs = st.db.query(
      tuple[s0, s1: int64],
      "select start_t, end_t from segment where activity_id = :id order by n",
      id = id,
    )
    var sums = newSeq[tuple[total, weighted: float]](segs.len)
    for (b, v) in bucketImpulse(r, fthr, m, 60):
      let mid = b + 30
      var k = 0
      var best = int64.high
      for j, sg in segs:
        let away =
          if mid < sg.s0:
            sg.s0 - mid
          elif mid > sg.s1:
            mid - sg.s1
          else:
            0
        if away < best:
          best = away
          k = j
      sums[k].total += v
      sums[k].weighted += v * float(mid)
    for sm in sums:
      if sm.total > 0:
        stretches.add (sm.weighted / sm.total, sm.total)
    if total <= 0:
      continue
    let (t0, t1) = (float(int64(r[0][0])), float(int64(r[^1][0])))
    spans.add (t0, t1)
    starts.add (t0, total)
    middles.add (0.5 * (t0 + t1), total)
    ends.add (t1, total)
    centres.add (weighted / total, total)
  for s in [
    addr minute,
    addr hour,
    addr starts,
    addr middles,
    addr ends,
    addr centres,
    addr stretches,
  ]:
    s[].sort do(a, b: Event) -> int:
      cmp(a.t, b.t)
  # the end of every local day, from the first impulse to 60 days after the last
  var days: seq[float]
  var d = fromUnix(int64(minute[0].t)).local
  d = dateTime(d.year, d.month, d.monthday, zone = local()) + 1.days
  let last = minute[^1].t + 60 * 86400
  while d.toTime.toUnix.float <= last:
    days.add d.toTime.toUnix.float
    d = d + 1.days
  echo fmt"{days.len} days, {minute.len} minutes with impulse, {centres.len} activities; FTHR {fthr}, default model"
  for (name, tauDays) in [("fatigue", m.fatigueDays), ("fitness", m.fitnessDays)]:
    let tau = tauDays * 86400
    let reference = curve(minute, tau, days)
    let top = reference.max
    echo fmt"{name} (tau {tauDays:g} days): the reference's highest {top:.1f}, its mean {reference.sum / float(days.len):.1f}"
    echo "  method                         largest difference   mean difference   largest, as % of the highest"
    for (label, ev) in [
      ("by the hour (now)", hour),
      ("one impulse, at the start", starts),
      ("one impulse, in the middle", middles),
      ("one impulse, at the end", ends),
      ("one impulse, at its centre", centres),
      ("one a stretch, at its centre", stretches),
    ]:
      let c = curve(ev, tau, days)
      var largest, total = 0.0
      var worst = 0
      for k in 0 ..< days.len:
        let diff = abs(c[k] - reference[k])
        if diff > largest:
          largest = diff
          worst = k
        total += diff
      # is a ride under way at that day's end?  (its first and last readings either side of it)
      var across = false
      for (a0, a1) in spans:
        if a0 < days[worst] and a1 > days[worst]:
          across = true
      let at = fromUnix(int64(days[worst])).local.format("yyyy-MM-dd")
      let why = if across: "a ride under way at midnight" else: ""
      echo fmt"  {label:<30} {largest:>18.3f} {total / float(days.len):>17.3f} {100 * largest / top:>26.2f}%   {at} {why}"

main()
