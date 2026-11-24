import std/[options, sequtils, strutils, unittest]
import nimchoo/packages/climbs/work
import nimchoo/packages/db/statement
import nimchoo/packages/db/store
import nimchoo/packages/user/session
import nimchoo/packages/fit/time
import nimchoo/core/ids
import nimchoo/packages/importer/importer
import nimchoo/packages/importer/track
import nimchoo/packages/heartrate/stored
import nimchoo/packages/names/suggest
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/names/countries
import nimchoo/packages/names/lookup
import nimchoo/packages/activities/criteria
import nimchoo/packages/tags/tag
import nimchoo/packages/climbs/criterion as climbsCriterion
import nimchoo/packages/activities/ranges

## The queries that run for every file, every ride or every cell must find their rows through an index (a primary key,
## a unique key, or the spatial index), never by reading a whole table: one that does is correct on a test database and
## takes minutes on a real one.  SQLite says how it will run a query (`explain query plan`); a line that starts with
## SCAN, other than the spatial index and the lists of ids, is a table read from start to end.

proc plan(db: DbConn, text: string): seq[string] =
  let s = prepareStmt(db, "explain query plan " & text)
  for r in fetchAll[tuple[id, parent, unused: int, detail: string]](s):
    result.add r.detail

func scans(plan: seq[string]): seq[string] =
  ## The lines of the plan that read a table through, which are not the spatial index, a list of ids, or the rows of a subquery
  ## that the plan has made (a `CO-ROUTINE` or `MATERIALIZE` of the same name).
  var made: seq[string]
  for line in plan:
    for head in ["CO-ROUTINE ", "MATERIALIZE "]:
      if line.startsWith(head):
        made.add line[head.len .. ^1]
  for line in plan:
    if line.startsWith("SCAN ") and "SpatialIndex" notin line and "json_each" notin line and
        line[5 .. ^1] notin made:
      result.add line

func usesSpatialIndex(plan: seq[string]): bool =
  for line in plan:
    if "SpatialIndex" in line:
      return true

let st = openSession(":memory:", allFragments, access = allAccess)

suite "query plans: no query reads a whole table":
  test "the check can fail: a column with no index is a scan":
    check scans(plan(st.db, "select id from activity where sport = 'x'")).len == 1
  test "a spatial query asks the spatial index, and reads no table through":
    for (what, text) in [
      ("features in a box", featuresInBoxSql),
      ("features around a point", featuresAroundSql),
      ("the countries of a cell", countriesInCellSql),
    ]:
      let p = plan(st.db, text)
      checkpoint what
      check usesSpatialIndex(p)
      check scans(p).len == 0
  test "the climbs a ride may have gone over, and the rides over a climb, are found through the cell index":
    for (what, text) in [
      ("the sectors a ride may have gone over", sectorsThroughSql),
      ("the rides that may have gone over a sector", ridesThroughSql),
    ]:
      let p = plan(st.db, text)
      checkpoint what
      check scans(p).len == 0
      check p.anyIt(
        "USING COVERING INDEX sector_gate_cell_cell" in it or
          "USING INDEX route_cell_cell" in it or
          "USING COVERING INDEX route_cell_cell" in it
      )
  test "what runs for each file or activity finds its rows by key":
    for (what, text) in [
      ("is the file known", knownFileSql),
      ("the positions of an activity", track.headSql),
      ("the arrays of the positions", track.arraysSql),
      ("the stretches of an activity", segmentsSql),
      (
        "the selection of a user",
        "select activity_id from activity_selection where user_id = ?",
      ),
      (
        "the cells read",
        "select count(*) from coverage where country = ? and cell_lon = ? and cell_lat = ?",
      ),
      ("the heart rate of an activity", stored.headSql),
      ("the arrays of the heart rate", stored.arraysSql),
      (
        "the efforts on a climb",
        "select e.elapsed_s from effort e where e.sector_id = ?",
      ),
      ("what was seen of a user", "select path from seen_file where user_id = ?"),
    ]:
      checkpoint what
      check scans(plan(st.db, text)).len == 0
  test "the criteria of a listing, each alone and all together":
    let tags =
      Resolved(kind: rtTags, tags: @[parsePattern("sport:cycling*").pattern.get])
    let names = Resolved(kind: rtNames, typed: @["toyo"], exact: @[some("El Toyo")])
    let paths = Resolved(kind: rtPaths, paths: @["bowman"])
    let from1 = Resolved(kind: rtFrom, lat: 38.7, lon: -9.1, km: 5.0)
    let near1 = Resolved(kind: rtNear, lat: 38.7, lon: -9.1, km: 1.0)
    let all = @[
      tags,
      names,
      Resolved(kind: rtStarts, typed: @["lisboa"]),
      paths,
      Resolved(kind: rtDistance, range: NumRange(lo: some 1.0, hi: some 2.0)),
      Resolved(kind: rtActive, range: NumRange(lo: some 1.0)),
      Resolved(kind: rtAfter, at: UnixTime(1)),
      Resolved(kind: rtBefore, at: UnixTime(2)),
      Resolved(kind: rtGps, gps: gpsWith),
      from1,
      near1,
    ]
    let each: seq[(string, seq[Resolved], bool)] = @[
      ("none", @[], false),
      ("tags", @[tags], false),
      ("names", @[names], false),
      ("paths", @[paths], false),
      ("a range", @[Resolved(kind: rtDistance, range: NumRange(lo: some 1.0))], false),
      ("no gps", @[Resolved(kind: rtGps, gps: gpsWithout)], false),
      ("from", @[from1], true),
      (
        "from, across the date line",
        @[Resolved(kind: rtFrom, lat: -17.0, lon: 179.9, km: 50.0)],
        true,
      ),
      ("near (a route passing)", @[near1], true),
      (
        "near, across the date line",
        @[Resolved(kind: rtNear, lat: -17.0, lon: 179.9, km: 50.0)],
        true,
      ),
      ("all", all, true),
    ]
    # (inverted, and limited: the newest 3, the oldest 3)
    check scans(plan(st.db, matchSql(UserId(1), all, invert = true).text)).len == 0
    for kind in [lkNewest, lkOldest]:
      check scans(
        plan(
          st.db,
          matchSql(UserId(1), @[], limit = some(Limit(kind: kind, count: 3))).text,
        )
      ).len == 0
    # (a criterion that another package offers: the climbs; its condition is joined by `and`)
    let climbs = Resolved(kind: rtCondition, condition: onClimbs(@[1'i64]))
    check scans(plan(st.db, matchSql(UserId(1), all & climbs).text)).len == 0
    check scans(plan(st.db, matchSql(UserId(1), @[climbs]).text)).len == 0
    for (what, filters, spatial) in each:
      let p = plan(st.db, matchSql(UserId(1), filters).text)
      checkpoint what
      check scans(p).len == 0
      if spatial:
        check usesSpatialIndex(p)
