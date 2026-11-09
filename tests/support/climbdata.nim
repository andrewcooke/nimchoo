## Made-up rides for tests of the climbs: along one road on the equator (1 km flat, 3 km up at 4 %,
## then flat), a point a second, put into a database as an import would.

import nimchoo/packages/db/statement
import std/[math, os, strutils]
import nimchoo/packages/db/store
import nimchoo/modules

const metre* = 360.0 / (2.0 * PI * 6_371_008.8)
  # degrees of longitude per metre at the equator

let dir* = getTempDir() / "nch-test-climbs-work"

func altitude*(x: float): float =
  ## The road: 1 km flat, 3 km up at 4 % (120 m), then flat.
  if x < 1000.0:
    100.0
  elif x < 4000.0:
    100.0 + (x - 1000.0) * 0.04
  else:
    220.0

proc fresh*(name: string): Store =
  removeDir(dir / name)
  openStore(dir / name / "x.db", allFragments, access = allAccess)

proc addRide*(
    s: Store,
    user: string,
    tag: string,
    startT: int,
    speed: float,
    xs: seq[float],
    withAltitude = true,
    northM = 0.0,
    breaksAfter: seq[int] = @[],
) =
  ## A ride along the road: the places it passes in turn (metres east), a point a second, in one
  ## stretch of riding.  After the points whose index is in `breaksAfter` the timer is stopped
  ## for a minute (the rider is carried on to the next place): a new stretch.
  let u = s.db.scalar(int64, "select id from user where name = :name", name = user)
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, 0)",
    userId = u,
    name = tag,
    sha256 = tag,
  )
  let f = s.db.scalar(int64, "select max(id) from file")
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t) values (:fileId, 0, :startT, :endT)",
    fileId = f,
    startT = startT,
    endT = startT + 10000,
  )
  let a = s.db.scalar(int64, "select max(id) from activity")
  var wkt: seq[string]
  var t = startT
  var stretches: seq[(int, int)] # (start, end) times of each stretch
  var since = startT
  for i, x in xs:
    let alt =
      if withAltitude:
        $altitude(x)
      else:
        ""
    s.db.execute(
      "insert into coords(activity_id, t, lon, lat, alt) values (:activityId, :t, :lon, :lat, nullif(:alt, ''))",
      activityId = a,
      t = t,
      lon = x * metre,
      lat = northM * metre,
      alt = alt,
    )
    wkt.add formatFloat(x * metre, ffDecimal, 9) & " " &
      formatFloat(northM * metre, ffDecimal, 9)
    if i in breaksAfter:
      stretches.add (since, t)
      t += 60
      since = t
    else:
      inc t
  stretches.add (since, t - 1)
  for n, (g0, g1) in stretches:
    s.db.execute(
      "insert into segment(activity_id, n, start_t, end_t) values (:activityId, :n, :startT, :endT)",
      activityId = a,
      n = n,
      startT = g0,
      endT = g1,
    )
  s.db.execute(
    "insert into route(activity_id, geom) values (:activityId, GeomFromText(:wkt, 4326))",
    activityId = a,
    wkt = "MULTILINESTRING((" & wkt.join(", ") & "))",
  )

func eastbound*(speed: float, from0 = -500.0, to0 = 6500.0): seq[float] =
  var x = from0
  while x <= to0:
    result.add x
    x += speed
