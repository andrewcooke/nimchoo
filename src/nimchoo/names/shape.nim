## The shape of an activity, from its route alone (pure): the first step of naming activities (TODO.md, "Names refactor and
## activity naming").  Three shapes are told apart, and a fourth for rides too small to name:
##
##   A  out and back: ends near where it began, and the way back starts over the way out (what comes later may differ: a
##      different road for the last stretch home is still "<destination> and back");
##   B  a loop: ends near where it began, and the way back is (almost) all a different road;
##   C  one place to another: does not end near where it began;
##   mixed: ends near where it began, and the way back is partly over the way out but does not start so;
##   local: never gets far from the start.
##
## The route is taken every 50 m along the way (so a ride is a few thousand points however it was recorded).  The turning
## point is the point furthest from the start.  "Near where it began" is within a quarter of that distance.  The way back is
## the part of the route after the turning point; a point of it is "over the way out" if some point of the way out is within
## 50 m.  Two shares are measured: of the whole way back (`retraced`) and of its first third (`retracedNear`, the part nearest
## the destination).  Out and back is 0.9 of either; a loop is under 0.1 of the whole; the rest is mixed.  Every number is a
## constant here, settled by looking at real rides: of 1,028 closed rides of the author, `retracedNear` is under 0.1 for 394
## and 0.9 or more for 462, with few between, and it finds the "El Toyo and back" rides that come home another way.

import std/[math, tables]
import ../geo

{.push raises: [].}

const
  stepM* = 50.0 ## the route is taken every this many metres
  localFarM* = 1500.0 ## furthest from the start under this: local
  closedFraction* = 0.25
    ## ends within this fraction of the furthest distance of the start: closed
  nearM* = 50.0 ## "over the way out"
  loopBelow* = 0.1 ## under this share of the way back over the way out: a loop
  outAndBackFrom* = 0.9
    ## this share or more (of the whole way back, or of its first third): out and back

type
  ShapeKind* = enum
    skLocal = "local"
    skOutAndBack = "out and back"
    skLoop = "loop"
    skMixed = "mixed"
    skOneWay = "one way"

  Shape* = object
    kind*: ShapeKind
    lengthM*: float ## along the route
    farM*: float ## the furthest from the start (straight line)
    endM*: float ## from the start to the end (straight line)
    retraced*: float
      ## 0 to 1: the share of the way back over the way out (0 if there is no way back)
    retracedNear*: float
      ## the same for the first third of the way back (the part nearest the turning point)
    turn*: int ## index of the turning point in `points`
    points*: seq[XY]
      ## the route every `stepM` metres, in metres east and north of the start

func shapeOf*(lons, lats: openArray[float]): Shape =
  ## The shape of the route (positions in order).  A route of fewer than two positions is local.
  if lons.len < 2 or lats.len < lons.len:
    return Shape(kind: skLocal)
  let pr = projection(lons[0], lats[0])
  var raw = newSeq[XY](lons.len)
  for i in 0 ..< lons.len:
    raw[i] = pr.project(lons[i], lats[i])
  result.points = raw.along(stepM)
  let pts = result.points
  result.lengthM = raw.length
  let start = pts[0]
  for i, p in pts:
    let d = dist(start, p)
    if d > result.farM:
      result.farM = d
      result.turn = i
  result.endM = dist(start, pts[^1])
  if result.farM < localFarM:
    result.kind = skLocal
    return
  if result.endM > closedFraction * result.farM:
    result.kind = skOneWay
    return
  # closed: how much of the way back is over the way out (a grid of cells the size of the tolerance)
  var cells = initTable[(int, int), seq[XY]]()
  for i in 0 .. result.turn:
    cells.mgetOrPut((int(floor(pts[i].x / nearM)), int(floor(pts[i].y / nearM))), @[]).add pts[
      i
    ]
  var back, over = 0
  var nearBack, nearOver = 0
  let nearCount = max(1, (pts.high - result.turn) div 3)
    # the points of the first third of the way back
  for i in result.turn + 1 .. pts.high:
    inc back
    let cx = int(floor(pts[i].x / nearM))
    let cy = int(floor(pts[i].y / nearM))
    var found = false
    block search:
      for dx in -1 .. 1:
        for dy in -1 .. 1:
          if (cx + dx, cy + dy) in cells:
            for q in cells.getOrDefault((cx + dx, cy + dy)):
              if dist(q, pts[i]) <= nearM:
                found = true
                break search
    if found:
      inc over
    if back <= nearCount:
      inc nearBack
      if found:
        inc nearOver
  result.retraced =
    if back > 0:
      over / back
    else:
      0.0
  result.retracedNear =
    if nearBack > 0:
      nearOver / nearBack
    else:
      0.0
  result.kind =
    if result.retracedNear >= outAndBackFrom or result.retraced >= outAndBackFrom:
      skOutAndBack
    elif result.retraced < loopBelow:
      skLoop
    else:
      skMixed
