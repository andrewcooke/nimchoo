## The key of the routes of activities, for a cached file that is made from them (see `cache.inputsKey`).

import std/[sequtils, strutils]
import db_connector/db_sqlite
import ../[errors, hashing]
import ../db/store

{.push raises: [].}

proc routesKey*(
    st: Store, ids: seq[int64]
): tuple[key: string, count: int] {.raises: [StoreError].} =
  ## The key of the routes of the activities `ids`, and how many of them have a route.  It is made from each route's
  ## activity, size in bytes and number of points, not from the lines: reading them all is the slow part (about 100 MB
  ## for 1,100 rides), and a route made by another rule would hardly keep both.
  if ids.len == 0:
    return (sha256Hex("")[0 ..< 16], 0)
  var text = ""
  guard:
    for row in st.db.fastRows(
      sql(
        "select activity_id, length(geom), NumPoints(geom) from route where activity_id in (" &
          ids.mapIt($it).join(",") & ") order by activity_id"
      )
    ):
      text.add row[0] & ":" & row[1] & ":" & row[2] & "\n"
      inc result.count
  result.key = sha256Hex(text)[0 ..< 16]
