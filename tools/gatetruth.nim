## Looking at the gates of the climbs and at the efforts stored on them (a tool, run by hand; TODO "the gates of a climb have no
## direction").  It opens the database for writing (SpatiaLite is not loaded in a read-only session): give it a copy.
##
##     nim c -d:release -p:src -o:/tmp/gatetruth tools/gatetruth.nim
##     /tmp/gatetruth ride DB ACTIVITY      every crossing of the gates of the climbs the activity has an effort on, and the one used
##     /tmp/gatetruth susceptible DB        the climbs whose gate crosses their own line somewhere else (a hairpin by the gate)
##     /tmp/gatetruth truth DB              for every stored effort, how far along the climb it really starts and ends, and how each
##                                          candidate rule (direction, closest to the length, both) would choose
##
## The truth is geometric, not the gates' own: the ride is followed along the climb's line, and an effort is right if it starts
## within 40 m of the start of the line and ends within 40 m of its end, moving the way the line goes.  The gates come from
## `climbs/match.gateLines`; the pairing rule of `overPaths` (the pairs that cover the climb's length within 5%, shortest first) is
## copied here, so keep the two in step.

import std/[algorithm, math, options, os, sequtils, strutils, tables, times]
import nimchoo/packages/geo/geo
import nimchoo/packages/climbs/match
import nimchoo/packages/importer/track
import nimchoo/packages/db/statement
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

const
  lengthTol = 0.05
  endsM = 100.0
    ## an effort starts and ends within this of the ends of the climb (the offsets have a valley at 80 to 100 m)
  onRouteM = 30.0 ## a position is on the climb's line if it is within this
  minShare = 0.8 ## of the positions of an effort must be on the line, going its way

type
  Crossing = tuple[pos, dist, t, cosv: float]
  Pair = tuple[s, f: Crossing]
  Gate = tuple[a, b: XY]
  Geometry = object
    pr: Projection
    route: seq[XY]
    chain: seq[float] ## metres along the line at each of its points
    length: float
    g0, g1: Gate
    d0, d1: XY ## the direction of the first and the last segment
    dirs: seq[XY]
      ## the direction of the line at each segment, over about 30 m either side (a segment is 5 m and noisy)

  Rule = enum
    rStored = "the rule now (shortest pair first)"
    rDirection = "direction (both crossings go with the climb)"
    rLength = "closest to the climb's length"
    rBoth = "direction, then closest to the length"
    rWeak = "not against the climb (within 120 degrees), then closest to the length"

  Verdict = enum
    vGood = "right"
    vLateStart = "starts late"
    vEarlyFinish = "finishes early"
    vBoth = "starts late and finishes early"
    vOff = "mostly off the climb"

func geometryOf(sector: Path): Option[Geometry] =
  let gl = gateLines(sector)
  if gl.isNone or sector.len < 2:
    return
  var g: Geometry
  g.pr = projection(sector.lon[0], sector.lat[0])
  for i in 0 ..< sector.len:
    g.route.add g.pr.project(sector.lon[i], sector.lat[i])
  g.chain = newSeq[float](g.route.len)
  for i in 1 ..< g.route.len:
    g.chain[i] = g.chain[i - 1] + dist(g.route[i - 1], g.route[i])
  g.length = g.chain[^1]
  g.g0 = (
    g.pr.project(gl.get.start[0].lon, gl.get.start[0].lat),
    g.pr.project(gl.get.start[1].lon, gl.get.start[1].lat),
  )
  g.g1 = (
    g.pr.project(gl.get.finish[0].lon, gl.get.finish[0].lat),
    g.pr.project(gl.get.finish[1].lon, gl.get.finish[1].lat),
  )
  var k = 1
  while k < g.route.len and dist(g.route[0], g.route[k]) < 1.0:
    inc k
  var j = g.route.high - 1
  while j > 0 and dist(g.route[^1], g.route[j]) < 1.0:
    dec j
  if k >= g.route.len or j < 0:
    return
  for i in 0 ..< g.route.high:
    let a = max(0, i - 6)
    let b = min(g.route.high, i + 7)
    g.dirs.add XY(x: g.route[b].x - g.route[a].x, y: g.route[b].y - g.route[a].y)
  # the direction at the gates, over about 30 m of the line (one segment is 5 m and noisy)
  var k30 = 0
  while k30 < g.route.high and g.chain[k30] < 30.0:
    inc k30
  var j30 = g.route.high
  while j30 > 0 and g.chain[^1] - g.chain[j30] < 30.0:
    dec j30
  g.d0 = XY(x: g.route[k30].x - g.route[0].x, y: g.route[k30].y - g.route[0].y)
  g.d1 = XY(x: g.route[^1].x - g.route[j30].x, y: g.route[^1].y - g.route[j30].y)
  some(g)

func at(values: openArray[float], pos: float): float =
  let i = min(int(floor(pos)), values.high - 1)
  let u = pos - float(i)
  values[i] + u * (values[i + 1] - values[i])

func cosOf(a, b: XY): float =
  a.x * b.x / max(1e-9, hypot(a.x, a.y) * hypot(b.x, b.y)) +
    a.y * b.y / max(1e-9, hypot(a.x, a.y) * hypot(b.x, b.y))

proc crossingsOf(
    ride: openArray[XY], cum, t: openArray[float], g: Gate, d: XY
): seq[Crossing] =
  for i in 0 ..< ride.high:
    let hit = intersect(ride[i], ride[i + 1], g.a, g.b)
    if hit.isSome and hit.get.ta < 1.0:
      let u = hit.get.ta
      let lo = max(0, i - 2)
      let hi = min(ride.high, i + 3)
      let h = XY(x: ride[hi].x - ride[lo].x, y: ride[hi].y - ride[lo].y)
      result.add (
        float(i) + u,
        cum[i] + u * (cum[i + 1] - cum[i]),
        t.at(float(i) + u),
        cosOf(h, d),
      )

proc pairsFor(ss, ff: seq[Crossing], length: float, rule: Rule): seq[Pair] =
  ## The pairs `overPaths` would take (the rule now), or what the other rules would: valid pairs, ordered, those that overlap
  ## one taken dropped.
  var pairs: seq[Pair]
  for s in ss:
    for f in ff:
      let covered = f.dist - s.dist
      if f.pos > s.pos and covered >= (1 - lengthTol) * length and
          covered <= (1 + lengthTol) * length:
        if rule in {rDirection, rBoth} and not (s.cosv > 0.0 and f.cosv > 0.0):
          continue
        if rule == rWeak and not (s.cosv > -0.5 and f.cosv > -0.5):
          continue
        pairs.add (s, f)
  if rule in {rLength, rBoth, rWeak}:
    pairs.sort(
      proc(a, b: Pair): int =
        cmp(abs(a.f.dist - a.s.dist - length), abs(b.f.dist - b.s.dist - length))
    )
  else:
    pairs.sort(
      proc(a, b: Pair): int =
        cmp(a.f.dist - a.s.dist, b.f.dist - b.s.dist)
    )
  for p in pairs:
    var overlaps = false
    for q in result:
      if p.s.pos < q.f.pos and q.s.pos < p.f.pos:
        overlaps = true
        break
    if not overlaps:
      result.add p

proc judge(
    g: Geometry, ride: seq[XY], t: seq[float], ts, tf: float, trace = false
): tuple[verdict: Verdict, startM, endM, share: float] =
  ## Follow the ride along the climb's line between the two times: at each position the nearest part of the line that goes the
  ## way the ride goes (within 30 m); where it starts and ends along the line, and for how much of the time it was on it.
  var i0 = -1
  var i1 = -1
  for i in 0 ..< t.len:
    if t[i] >= ts and i0 < 0:
      i0 = i
    if t[i] <= tf:
      i1 = i
  if i0 < 0 or i1 <= i0:
    return (vOff, -1.0, -1.0, 0.0)
  var valid = 0
  var first, last = -1.0
  var prevJ = -1
  var lost = 0
  for i in i0 .. i1:
    let p = ride[i]
    let h =
      if i < ride.high:
        XY(x: ride[i + 1].x - p.x, y: ride[i + 1].y - p.y)
      else:
        XY(x: p.x - ride[i - 1].x, y: p.y - ride[i - 1].y)
    let moving = hypot(h.x, h.y) > 1.5
    var lo = 0
    var hi = g.route.high
    if prevJ >= 0 and lost < 5:
      lo = max(0, prevJ - 5)
      hi = min(g.route.high, prevJ + 80)
    var best = onRouteM
    var bj = -1
    var bu = 0.0
    for j in lo ..< hi:
      let a = g.route[j]
      let b = g.route[j + 1]
      let dxy = XY(x: b.x - a.x, y: b.y - a.y)
      if moving and cosOf(h, g.dirs[j]) < 0.5:
        continue
      let d = pointSegmentDistance(p, a, b)
      if d < best:
        best = d
        bj = j
        let len2 = dxy.x * dxy.x + dxy.y * dxy.y
        bu =
          if len2 == 0:
            0.0
          else:
            max(0.0, min(1.0, ((p.x - a.x) * dxy.x + (p.y - a.y) * dxy.y) / len2))
    if trace:
      echo "      t+",
        int(t[i] - ts),
        " s  moving ",
        moving,
        "  best segment ",
        bj,
        " at ",
        (
          if bj >= 0:
          formatFloat(g.chain[bj] + bu * (g.chain[bj + 1] - g.chain[bj]), ffDecimal, 0) &
            " m"
          else: "-"
        ),
        " (",
        formatFloat(best, ffDecimal, 1),
        " m off)"
    if bj >= 0:
      let chain = g.chain[bj] + bu * (g.chain[bj + 1] - g.chain[bj])
      inc valid
      if first < 0:
        first = chain
      last = chain
      prevJ = bj
      lost = 0
    else:
      inc lost
  result.share = float(valid) / float(i1 - i0 + 1)
  result.startM = first
  result.endM = last
  let late = first > endsM
  let early = last < g.length - endsM
  result.verdict =
    if result.share < minShare or first < 0:
      vOff
    elif late and early:
      vBoth
    elif late:
      vLateStart
    elif early:
      vEarlyFinish
    else:
      vGood

type Loaded = object
  sectors: Table[int64, Option[Geometry]]
  paths: Table[int64, seq[Path]]
  names: Table[int64, string]

proc sectorGeometry(st: Session, l: var Loaded, id: int64): Option[Geometry] =
  if id notin l.sectors:
    let p = parseLineString(
      st.db.scalar(
        Option[string], "select AsText(route) from sector where id = :id", id = id
      )
    )
    l.sectors[id] =
      if p.isSome:
        geometryOf(p.get)
      else:
        none(Geometry)
    l.names[id] = st.db.scalar(
      string,
      "select coalesce(name, '') || case when name_n is null then '' else '#' || name_n end from sector where id = :id",
      id = id,
    )
  l.sectors[id]

proc stretches(st: Session, l: var Loaded, id: int64): seq[Path] =
  if id notin l.paths:
    var ps: seq[Path]
    for coords in readTrack(st.db, ActivityId(id)):
      if coords.len < 2:
        continue
      var p: Path
      for c in coords:
        p.lon.add c.lon
        p.lat.add c.lat
        p.t.add float(int64(c.t))
      ps.add p
    l.paths[id] = ps
  l.paths[id]

proc hms(t: float): string =
  fromUnix(int64(round(t))).utc.format("HH:mm:ss")

proc rideMode(st: Session, activity: int64) =
  var l: Loaded
  let rows = st.db.query(
    tuple[sid: int64, s, f: float],
    "select sector_id, start_t, finish_t from effort where activity_id = :a order by start_t, sector_id",
    a = activity,
  )
  for r in rows:
    let gm = sectorGeometry(st, l, r.sid)
    if gm.isNone:
      continue
    let g = gm.get
    echo "climb ",
      r.sid,
      " (",
      l.names[r.sid],
      ", ",
      int(g.length),
      " m): stored effort ",
      hms(r.s),
      " to ",
      hms(r.f),
      ", ",
      int(r.f - r.s),
      " s"
    for ride in stretches(st, l, activity):
      if ride.t.len == 0 or r.s < ride.t[0] - 1 or r.s > ride.t[^1] + 1:
        continue
      var xy: seq[XY]
      for i in 0 ..< ride.len:
        xy.add g.pr.project(ride.lon[i], ride.lat[i])
      var cum = newSeq[float](xy.len)
      for i in 1 ..< xy.len:
        cum[i] = cum[i - 1] + dist(xy[i - 1], xy[i])
      for (name, gate, d) in [("start", g.g0, g.d0), ("finish", g.g1, g.d1)]:
        for c in crossingsOf(xy, cum, ride.t, gate, d):
          let used = abs(c.t - (if name == "start": r.s else: r.f)) < 1.5
          echo "    ",
            name,
            " gate crossed at ",
            hms(c.t),
            ", ",
            (if c.cosv > 0: "with " else: "AGAINST "),
            "the climb (cos ",
            formatFloat(c.cosv, ffDecimal, 2),
            ")",
            (if used: "   <-- used by the stored effort" else: "")

proc susceptibleMode(st: Session) =
  var l: Loaded
  let ids = st.db.query(int64, "select id from sector order by id")
  var rows: seq[tuple[efforts: int, line: string]]
  for id in ids:
    let gm = sectorGeometry(st, l, id)
    if gm.isNone:
      continue
    let g = gm.get
    var parts: seq[string]
    for (name, gate, d, own) in [
      ("start", g.g0, g.d0, 0), ("finish", g.g1, g.d1, g.route.high - 1)
    ]:
      for i in 0 ..< g.route.high:
        if i == own:
          continue
        let hit = intersect(g.route[i], g.route[i + 1], gate.a, gate.b)
        if hit.isSome:
          let seg =
            XY(x: g.route[i + 1].x - g.route[i].x, y: g.route[i + 1].y - g.route[i].y)
          let at = g.chain[i] + hit.get.ta * (g.chain[i + 1] - g.chain[i])
          parts.add name & " gate meets the line again at " & $int(at) & " m (" &
            (if cosOf(seg, d) < 0: "going the other way" else: "going the same way") &
            ")"
    if parts.len > 0:
      let n =
        st.db.scalar(int, "select count(*) from effort where sector_id = :id", id = id)
      rows.add (
        n,
        "climb " & $id & " (" & l.names[id] & ", " & $int(g.length) & " m, " & $n &
          " efforts): " & parts.join("; "),
      )
  rows.sort(
    proc(a, b: tuple[efforts: int, line: string]): int =
      cmp(b.efforts, a.efforts)
  )
  echo rows.len,
    " of ",
    ids.len,
    " climbs have a gate that meets their own line somewhere else (",
    rows.mapIt(it.efforts).foldl(a + b, 0),
    " efforts on them):"
  for r in rows:
    echo "  ", r.line

proc traceMode(st: Session, activity, sector: int64) =
  var l: Loaded
  let gm = sectorGeometry(st, l, sector)
  if gm.isNone:
    return
  let g = gm.get
  for r in st.db.query(
    tuple[s, f: float],
    "select start_t, finish_t from effort where activity_id = :a and sector_id = :c",
    a = activity,
    c = sector,
  ):
    for ride in stretches(st, l, activity):
      if ride.t.len == 0 or r.s < ride.t[0] - 1 or r.s > ride.t[^1] + 1:
        continue
      var xy: seq[XY]
      for i in 0 ..< ride.len:
        xy.add g.pr.project(ride.lon[i], ride.lat[i])
      echo "climb ",
        sector, " ", int(g.length), " m; effort ", hms(r.s), " to ", hms(r.f)
      let v = judge(g, xy, ride.t, r.s, r.f, trace = true)
      echo "  verdict: ",
        v.verdict,
        ", starts at ",
        int(v.startM),
        " m, ends at ",
        int(v.endM),
        " m, ",
        int(v.share * 100),
        "% on the line"

proc truthMode(st: Session) =
  var l: Loaded
  let rows = st.db.query(
    tuple[aid, sid: int64, s, f: float],
    "select activity_id, sector_id, start_t, finish_t from effort order by activity_id, sector_id, start_t",
  )
  var stored: array[Verdict, int]
  var table: array[Rule, array[Verdict, int]]
  var none: array[Rule, int]
  var fixed, still, removed, regress, lost, kept: array[Rule, int]
  var total = 0
  var examples: array[Verdict, seq[string]]
  var lateM, earlyM: seq[float]
  var lostExamples: seq[string]
  for r in rows:
    let gm = sectorGeometry(st, l, r.sid)
    if gm.isNone:
      continue
    let g = gm.get
    for ride in stretches(st, l, r.aid):
      if ride.t.len == 0 or r.s < ride.t[0] - 1 or r.s > ride.t[^1] + 1:
        continue
      var xy: seq[XY]
      for i in 0 ..< ride.len:
        xy.add g.pr.project(ride.lon[i], ride.lat[i])
      var cum = newSeq[float](xy.len)
      for i in 1 ..< xy.len:
        cum[i] = cum[i - 1] + dist(xy[i - 1], xy[i])
      let ss = crossingsOf(xy, cum, ride.t, g.g0, g.d0)
      let ff = crossingsOf(xy, cum, ride.t, g.g1, g.d1)
      inc total
      let jd = judge(g, xy, ride.t, r.s, r.f)
      let was = jd.verdict
      if jd.startM >= 0:
        lateM.add jd.startM
        earlyM.add g.length - jd.endM
      inc stored[was]
      if was != vGood and examples[was].len < 6:
        examples[was].add "activity " & $r.aid & " climb " & $r.sid & " (" &
          $int(g.length) & " m): starts at " & $int(jd.startM) & " m, ends at " &
          $int(jd.endM) & " m along it, " & $int(jd.share * 100) &
          "% of the time on the line"

      for rule in Rule:
        var found = false
        for p in pairsFor(ss, ff, g.length, rule):
          if p.s.pos < xy.len.float and ride.t.at(p.s.pos) < r.f and
              r.s < ride.t.at(p.f.pos):
            found = true
            let v = judge(g, xy, ride.t, ride.t.at(p.s.pos), ride.t.at(p.f.pos)).verdict
            inc table[rule][v]
            if was != vGood:
              if v == vGood:
                inc fixed[rule]
              else:
                inc still[rule]
            else:
              if v == vGood:
                inc kept[rule]
              else:
                inc regress[rule]
            break
        if not found:
          inc none[rule]
          if was != vGood:
            inc removed[rule]
          else:
            inc lost[rule]
            if rule == rWeak and lostExamples.len < 12:
              for p0 in pairsFor(ss, ff, g.length, rStored):
                if ride.t.at(p0.s.pos) < r.f and r.s < ride.t.at(p0.f.pos):
                  lostExamples.add "activity " & $r.aid & " climb " & $r.sid & " (" &
                    $int(g.length) & " m), " & hms(r.s) & " to " & hms(r.f) &
                    ": start crossing cos " & formatFloat(p0.s.cosv, ffDecimal, 2) &
                    ", finish crossing cos " & formatFloat(p0.f.cosv, ffDecimal, 2)
                  break
      break
  proc histogram(label: string, xs: seq[float]) =
    const cuts = [10.0, 20.0, 30.0, 40.0, 60.0, 80.0, 100.0, 150.0, 1e9]
    var counts: array[9, int]
    for x in xs:
      for i, c in cuts:
        if x < c:
          inc counts[i]
          break
    var line = label & ":"
    var lo = 0.0
    for i, c in cuts:
      line.add "  " & (if c > 1e8: ">" & $int(lo) else: $int(lo) & "-" & $int(c)) &
        " m: " & $counts[i]
      lo = c
    echo line

  for e in lostExamples:
    echo "lost by the weak rule: ", e
  histogram("how far along the climb the stored effort starts", lateM)
  histogram("how far before the end of the climb the stored effort ends", earlyM)
  echo "stored efforts: ", total
  echo "  followed along the climb's line (a position on it within ",
    int(onRouteM),
    " m going its way, start within ",
    int(endsM),
    " m of the start and end within ",
    int(endsM),
    " m of the end):"
  for v in Verdict:
    echo "    ", align($stored[v], 5), "  ", $v
  for v in Verdict:
    if examples[v].len > 0:
      echo "examples, ", $v, ":"
      for e in examples[v]:
        echo "    ", e
  echo ""
  for rule in Rule:
    echo $rule, ": the effort that overlaps each stored one is"
    for v in Verdict:
      echo "    ", align($table[rule][v], 5), "  ", $v
    echo "    ", align($none[rule], 5), "  no pair at all"
    echo "    of the stored efforts that were wrong: ",
      fixed[rule],
      " become right, ",
      still[rule],
      " stay wrong, ",
      removed[rule],
      " have no pair (removed)"
    echo "    of the stored efforts that were right: ",
      kept[rule],
      " stay right, ",
      regress[rule],
      " become wrong, ",
      lost[rule],
      " have no pair (lost)"
    echo ""

let args = commandLineParams()
if args.len < 2:
  echo "usage: gatetruth ride DB ACTIVITY | susceptible DB | truth DB | trace DB ACTIVITY CLIMB"
  quit 2
let st = openSession(args[1], allFragments, access = allAccess)
case args[0]
of "ride":
  rideMode(st, parseInt(args[2]).int64)
of "susceptible":
  susceptibleMode(st)
of "truth":
  truthMode(st)
of "trace":
  traceMode(st, parseInt(args[2]).int64, parseInt(args[3]).int64)
else:
  echo "usage: gatetruth ride DB ACTIVITY | susceptible DB | truth DB | trace DB ACTIVITY CLIMB"
  quit 2
