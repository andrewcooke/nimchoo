## Whether climbs lie on one another, asked of SpatiaLite: the share of a route that is within `gateRadius` of another
## (`ST_Buffer`, `ST_Intersection`, `ST_Length`).  Two questions use it, with different limits:
##
##  * `isRepeat`: a climb just found is one that is stored if less than `repeatLimit` of each lies outside the other
##    (only the stored ones the ride earned an effort on are asked);
##  * `nearCopies`: for the duplicates report, pairs of stored climbs of which less than `nearCopyLimit` of each lies
##    outside the other (a short climb inside a long one is not, and a chain of climbs that each overlap the next is not).
##
## The metres: a pair is projected to the UTM zone of the first (`ST_Transform`), where a buffer of 25 m is 25 m.  Routes
## are simplified to `simplifyM` first (the test is about 25 m, and a route has a point for every 5 m of climbing): that
## halves the time and changed no answer on 183 real climbs.  The buffer has round ends (SpatiaLite has no flat ones): the
## ground just beyond an end counts, which made no difference on the same climbs.  Measured and compared with the code
## these replace (HISTORY.md, 2026-11-11).

import ../db/[sqltext, statement, store]
import ../../core/errors
import ./match

{.push raises: [].}

const
  repeatLimit* = 0.5 ## a repeat if less than this fraction of each is outside the other
  nearCopyLimit* = 0.2
    ## a near copy (the duplicates report) if less than this fraction of each is outside the other
  simplifyM = 2.0 ## metres of tolerance in simplifying a route before the buffer
  bufferSegments = 8 ## per quarter circle of a buffer
  padDegrees = 0.001
    ## added to the box of a route to find the others near it (about 100 m, more than `gateRadius` up to latitude 77)

func zoneOf(geom: string): string =
  ## The SRID of the UTM zone of a geometry's first point (`geom` is a column or a name in the query).
  "case when ST_Y(StartPoint(" & geom & ")) < 0 then 32700 else 32600 end + " &
    "cast((ST_X(StartPoint(" & geom & ")) + 180) / 6 as integer) + 1"

func flat(geom, srid: string): string =
  ## The geometry in metres of that zone, in two dimensions, simplified.
  "ST_Simplify(CastToXY(ST_Transform(" & geom & ", " & srid & ")), :simplify)"

const
  insideShares =
    "ST_Length(ST_Intersection(pa, ST_Buffer(pb, :radius, :segments))) / ST_Length(pa) as sa, " &
    "ST_Length(ST_Intersection(pb, ST_Buffer(pa, :radius, :segments))) / ST_Length(pb) as sb"
    ## the share of each (a, b) that is within the radius of the other

  nearCopiesSql =
    "select aid, bid from (select aid, bid, " & insideShares &
    " from (select a.id aid, b.id bid, " & flat("a.route", "a.srid") & " pa, " &
    flat("b.route", "a.srid") & " pb from (select id, route, " & zoneOf("route") &
    " srid from sector) a join sector b on b.id > a.id and " &
    inBox(
      "b.id", "sector", "route",
      "MbrMinX(a.route) - :pad, MbrMinY(a.route) - :pad, MbrMaxX(a.route) + :pad, MbrMaxY(a.route) + :pad",
    ) & ")) where sa > :keep and sb > :keep order by aid, bid"

  repeatSql =
    "select count(*) from (select " & insideShares & " from (select " &
    flat("s.route", "q.srid") & " pa, " & flat("q.n", "q.srid") & " pb from (select n, " &
    zoneOf("n") &
    " srid from (select GeomFromText(:route, 4326) n)) q join sector s on s.id in (select value from json_each(:among)))) " &
    "where sa > :keep and sb > :keep"

proc nearCopies*(st: Store): seq[tuple[a, b: int64]] {.raises: [StoreError].} =
  ## The pairs of stored climbs (retired ones too) that are near copies of each other, the lower id first.  A climb whose
  ## route cannot be read is damaged data and an error: it must not be taken for one that overlaps nothing.
  let damaged = st.db.scalar(
    int,
    "select count(*) from sector where route is null or ST_NumPoints(route) is null",
  )
  if damaged > 0:
    raiseStore(
      "a climb has a route that cannot be read (damaged data): run `nch climbs --all --delete -f` and ask for the climbs again"
    )
  for r in st.db.query(
    tuple[a, b: int64],
    nearCopiesSql,
    simplify = simplifyM,
    radius = gateRadius,
    segments = bufferSegments,
    pad = padDegrees,
    keep = 1.0 - nearCopyLimit,
  ):
    result.add r

proc isRepeat*(
    st: Store, route: Path, among: openArray[int64]
): bool {.raises: [StoreError].} =
  ## Whether `route`, a climb just found, is one of the stored climbs `among` again.
  if route.len < 2 or among.len == 0:
    return false
  st.db.scalar(
    int,
    repeatSql,
    route = lineStringText(route),
    among = jsonList(among),
    simplify = simplifyM,
    radius = gateRadius,
    segments = bufferSegments,
    keep = 1.0 - repeatLimit,
  ) > 0
