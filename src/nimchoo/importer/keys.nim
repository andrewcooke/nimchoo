## The key of the routes of activities, for a cached file that is made from them (see `cache.inputsKey`).

import ../core/errors
import ../packages/util/hashing/hashing
import ../packages/db/statement
import ../packages/db/store

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
  for row in st.db.query(
    tuple[id: int64, bytes, points: int],
    "select activity_id, length(geom), NumPoints(geom) from route where activity_id in " &
      "(select value from json_each(:ids)) order by activity_id",
    ids = jsonList(ids),
  ):
    text.add $row.id & ":" & $row.bytes & ":" & $row.points & "\n"
    inc result.count
  result.key = sha256Hex(text)[0 ..< 16]
