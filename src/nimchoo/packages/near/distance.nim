## Whether a geometry comes within a distance of a point, on the ground, quickly.  The exact distance (on the ellipsoid,
## SpatiaLite's `ST_Distance(a, b, 1)`) is slow for a long line: it took 3.5 s for the author's 1,100 routes, against
## 0.18 s for the distance in degrees (planar).  So the distance in degrees decides first, in the same query, with bounds
## that hold anywhere within the radius: a metre is at most 1/111,700 of a degree in any direction, and at least
## 1/(111,320 cos(latitude)) of a degree of longitude at the highest latitude a point within the radius can have; a line
## surely in or surely out is decided by those, and only one between them (near the edge of the circle) by the exact
## distance (SQLite does not evaluate the rest of an `or` or an `and` once it is decided).  The answer is the exact
## distance's.

import std/[math, strformat]
import ../db/sqltext

{.push raises: [].}

const
  mostMetresPerDegree = 111_700.0 * 1.01
    ## (a degree of latitude near a pole is 111.69 km; of longitude, at most 111.32: with a margin for the ellipsoid)
  leastFactor = 0.99 ## the margin the other way

func bounds*(lat, metres: float): tuple[sure, maybe: float] =
  ## The distances in degrees within which a geometry is surely within `metres` of a point at latitude `lat`, and beyond
  ## which it surely is not.
  let highest = min(89.9, abs(lat) + metres / 110_000.0 * 1.01)
  (
    metres / mostMetresPerDegree,
    metres / (111_320.0 * cos(degToRad(highest)) * leastFactor),
  )

func withinSql*(geometry, name: string, lat, metres: float): Sql =
  ## The condition that `geometry` (an expression of the query, in degrees, SRID 4326) comes within `metres` of the point
  ## bound as `:{name}Lon` and `:{name}Lat`, `:{name}M` being the metres (the caller binds those three, as the test of
  ## the box does); this binds `:{name}Sure` and `:{name}Maybe`, the `bounds` for the point's latitude `lat`.
  let (sure, maybe) = bounds(lat, metres)
  let point = fmt"MakePoint(:{name}Lon, :{name}Lat, 4326)"
  sqlOf(
    fmt"(ST_Distance({geometry}, {point}) <= :{name}Sure or (ST_Distance({geometry}, {point}) <= :{name}Maybe and ST_Distance({geometry}, {point}, 1) <= :{name}M))"
  )
    .with(name & "Sure", sure)
    .with(name & "Maybe", maybe)
