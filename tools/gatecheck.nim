## A check of the gates of the climbs against the efforts that are stored (a tool, run by hand: TODO "the gates of a climb have no direction").
## For each stored effort it finds every pair of crossings of the start and finish gates that `overPaths` would also accept, and says
## how many efforts were made from a crossing that goes against the route (cosine of the angle between the ride and the route at the
## gate below 0.0, -0.5, -0.7, -0.9), how many sit inside a longer valid pair, and what the times would be if both crossings had to go
## the right way.  It copies the gate code of `climbs/match.nim` (which does not export it), so keep the two in step.
##
##     nim c -d:release -p:src -o:/tmp/gatecheck tools/gatecheck.nim && /tmp/gatecheck /path/to/a/copy/of/nch.db
##
## It opens the database for writing (SpatiaLite is not loaded in a read-only session): give it a copy.

import std/[algorithm, math, options, os, tables]
import nimchoo/packages/geo/geo
import nimchoo/packages/climbs/match
import nimchoo/packages/importer/track
import nimchoo/packages/db/statement
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

const
  gateRadius = 25.0
  tol = 0.05

type
  Gate = tuple[a, b: XY]
  Crossing = tuple[pos, dist, t, dir: float]

func xyOf(p: Path, pr: Projection): seq[XY] =
  for i in 0 ..< p.len:
    result.add pr.project(p.lon[i], p.lat[i])

func gateAt(centre, direction: XY): Gate =
  let n = hypot(direction.x, direction.y)
  let nx = -direction.y / n
  let ny = direction.x / n
  (
    XY(x: centre.x - gateRadius * nx, y: centre.y - gateRadius * ny),
    XY(x: centre.x + gateRadius * nx, y: centre.y + gateRadius * ny),
  )

func at(values: openArray[float], pos: float): float =
  let i = min(int(floor(pos)), values.high - 1)
  let u = pos - float(i)
  values[i] + u * (values[i + 1] - values[i])

proc crossings(
    ride: openArray[XY], cum: openArray[float], t: openArray[float], g: Gate, d: XY
): seq[Crossing] =
  for i in 0 ..< ride.high:
    let hit = intersect(ride[i], ride[i + 1], g.a, g.b)
    if hit.isSome and hit.get.ta < 1.0:
      let u = hit.get.ta
      result.add (
        float(i) + u,
        cum[i] + u * (cum[i + 1] - cum[i]),
        t.at(float(i) + u),
        ((ride[i + 1].x - ride[i].x) * d.x + (ride[i + 1].y - ride[i].y) * d.y) /
          max(
            1e-9,
            hypot(ride[i + 1].x - ride[i].x, ride[i + 1].y - ride[i].y) * hypot(
              d.x, d.y
            ),
          ),
      )

let st = openSession(paramStr(1), allFragments, access = allAccess)
let rows = st.db.query(
  tuple[aid, sid, s, f: int64],
  "select activity_id, sector_id, cast(start_t as integer), cast(finish_t as integer) from effort order by activity_id, sector_id",
)
var sectors: Table[int64, Path]
var tracks: Table[int64, seq[Path]]
var strongS, strongF, strongAny: array[3, int]
var changed, lost, sLost, sChanged = 0
var sChanges: seq[float]
var examples: seq[string]
var changes: seq[float]
var analysed, nested, multiStart, multiFinish, wrongStart, wrongFinish, extraWrong,
  extraSame = 0
var diffs: seq[float]
var gaps: seq[float]
var bySector: Table[int64, int]
for r in rows:
  if r.sid notin sectors:
    sectors[r.sid] = parseLineString(
      st.db.scalar(
        Option[string], "select AsText(route) from sector where id = :id", id = r.sid
      )
    ).get
  if r.aid notin tracks:
    var ps: seq[Path]
    for coords in readTrack(st.db, ActivityId(r.aid)):
      if coords.len < 2:
        continue
      var p: Path
      for c in coords:
        p.lon.add c.lon
        p.lat.add c.lat
        p.t.add float(int64(c.t))
      ps.add p
    tracks[r.aid] = ps
  let sector = sectors[r.sid]
  let pr = projection(sector.lon[0], sector.lat[0])
  let route = sector.xyOf(pr)
  var k = 1
  while k < route.len and dist(route[0], route[k]) < 1.0:
    inc k
  var j = route.high - 1
  while j > 0 and dist(route[^1], route[j]) < 1.0:
    dec j
  let d0 = XY(x: route[k].x - route[0].x, y: route[k].y - route[0].y)
  let d1 = XY(x: route[^1].x - route[j].x, y: route[^1].y - route[j].y)
  let g0 = gateAt(route[0], d0)
  let g1 = gateAt(route[^1], d1)
  let length = route.length
  for ride in tracks[r.aid]:
    if ride.t.len == 0 or r.s < int64(ride.t[0]) - 1 or r.s > int64(ride.t[^1]) + 1:
      continue
    let rxy = ride.xyOf(pr)
    var cum = newSeq[float](rxy.len)
    for i in 1 ..< rxy.len:
      cum[i] = cum[i - 1] + dist(rxy[i - 1], rxy[i])
    let ss = crossings(rxy, cum, ride.t, g0, d0)
    let ff = crossings(rxy, cum, ride.t, g1, d1)
    var pairs: seq[tuple[s, f: Crossing]]
    for s in ss:
      for f in ff:
        let c = f.dist - s.dist
        if f.pos > s.pos and c >= (1 - tol) * length and c <= (1 + tol) * length:
          pairs.add (s, f)
    # the chosen: the pair whose start time is the stored one
    var chosen = -1
    for i, p in pairs:
      if abs(p.s.t - float(r.s)) < 1.5 and abs(p.f.t - float(r.f)) < 1.5:
        chosen = i
    if chosen < 0:
      continue
    inc analysed
    let p = pairs[chosen]
    for (th, idx) in [(-0.5, 0), (-0.7, 1), (-0.9, 2)]:
      if p.s.dir < th:
        strongS[idx] += 1
      if p.f.dir < th:
        strongF[idx] += 1
      if p.s.dir < th or p.f.dir < th:
        strongAny[idx] += 1
    block corrected:
      var good: seq[tuple[s, f: Crossing]]
      for q in pairs:
        if q.s.dir > 0.3 and q.f.dir > 0.3:
          good.add q
      good.sort(
        proc(a, b: tuple[s, f: Crossing]): int =
          cmp(a.f.dist - a.s.dist, b.f.dist - b.s.dist)
      )
      var found = false
      for q in good:
        if q.s.pos < p.f.pos and p.s.pos < q.f.pos: # overlaps the stored effort
          found = true
          let was = p.f.t - p.s.t
          let now = q.f.t - q.s.t
          if abs(was - now) > 0.5:
            changed += 1
            changes.add now - was
          if (p.s.dir < -0.9 or p.f.dir < -0.9) and abs(was - now) > 0.5:
            sChanged += 1
            sChanges.add now - was
            if examples.len < 6:
              examples.add "activity " & $r.aid & " sector " & $r.sid & ": stored " &
                $int(was) & " s, with the right direction " & $int(now) & " s (route " &
                $int(length) & " m; start cos " & $(int(p.s.dir * 100)) &
                "%, finish cos " & $(int(p.f.dir * 100)) & "%)"
          break
      if not found:
        lost += 1
        if p.s.dir < -0.9 or p.f.dir < -0.9:
          sLost += 1
    if p.s.dir < 0:
      inc wrongStart
    if p.f.dir < 0:
      inc wrongFinish
    var outerS = p.s.t
    var outerF = p.f.t
    var outerDist = p.f.dist - p.s.dist
    for q in pairs:
      if q.s.pos <= p.s.pos and q.f.pos >= p.f.pos and
          (q.s.pos < p.s.pos or q.f.pos > p.f.pos):
        if q.s.t < outerS:
          outerS = q.s.t
        if q.f.t > outerF:
          outerF = q.f.t
        outerDist = max(outerDist, q.f.dist - q.s.dist)
    if outerS < p.s.t or outerF > p.f.t:
      inc nested
      var anyWrong = false
      for q in pairs:
        if q.s.pos <= p.s.pos and q.f.pos >= p.f.pos and
            (q.s.pos < p.s.pos or q.f.pos > p.f.pos):
          if (q.s.pos < p.s.pos and q.s.dir < 0) or (q.f.pos > p.f.pos and q.f.dir < 0):
            anyWrong = true
      if anyWrong:
        inc extraWrong
      else:
        inc extraSame
      diffs.add (p.s.t - outerS) + (outerF - p.f.t)
      gaps.add outerDist - (p.f.dist - p.s.dist)
      bySector[r.sid] = bySector.getOrDefault(r.sid) + 1
    break
changes.sort()
echo "if both crossings had to go the right way (within about 70 degrees of the route): ",
  changed, " efforts change time, ", lost, " have no pair left"
if changes.len > 0:
  echo "change in seconds (corrected minus stored): median ",
    changes[changes.len div 2],
    " min ",
    changes[0],
    " max ",
    changes[^1],
    " p10 ",
    changes[changes.len div 10],
    " p90 ",
    changes[changes.len * 9 div 10]
echo "crossing against the route direction, by how far (cos below -0.5 / -0.7 / -0.9, i.e. more than 120 / 134 / 154 degrees off): start ",
  strongS, " finish ", strongF, " either ", strongAny
sChanges.sort()
echo "of the strongly wrong-way ones: ",
  sChanged,
  " have another pair with the right direction (time change: median ",
  (if sChanges.len > 0: sChanges[sChanges.len div 2] else: 0.0),
  " s, max ",
  (if sChanges.len > 0: sChanges[^1] else: 0.0),
  " s), ",
  sLost,
  " have none"
for e in examples:
  echo "  ", e
echo "efforts analysed: ", analysed, " of ", rows.len
echo "chosen start crossing against the route direction: ",
  wrongStart, "; chosen finish crossing against: ", wrongFinish
echo "nested: extra crossing is against the direction (hairpin-like): ",
  extraWrong, ", in the same direction (a second pass / a stop at the top): ", extraSame
echo "efforts that sit inside a longer valid pair of crossings (an ambiguous gate): ",
  nested
diffs.sort()
gaps.sort()
if diffs.len > 0:
  echo "seconds the longer pair would add: median ",
    diffs[diffs.len div 2], " max ", diffs[^1], " p90 ", diffs[diffs.len * 9 div 10]
  echo "metres: median ", gaps[gaps.len div 2], " max ", gaps[^1]
var sec: seq[(int, int64)]
for k, v in bySector:
  sec.add (v, k)
sec.sort(Descending)
for (v, k) in sec[0 ..< min(8, sec.len)]:
  echo "sector ", k, ": ", v, " efforts, length ", int(sectors[k].lon.len), " points"
