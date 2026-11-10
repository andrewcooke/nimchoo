import std/[options, strutils, unittest]
import nimchoo/packages/climbs/work
import nimchoo/packages/db/statement
import nimchoo/packages/db/store
import nimchoo/packages/user/session
import nimchoo/packages/fit/time
import nimchoo/core/ids
import nimchoo/packages/importer/importer
import nimchoo/packages/importer/track
import nimchoo/packages/names/suggest
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/names/countries
import nimchoo/packages/names/lookup
import nimchoo/packages/activities/criteria
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
  ## The lines of the plan that read a table through, which are not the spatial index or a list of ids.
  for line in plan:
    if line.startsWith("SCAN ") and "SpatialIndex" notin line and "json_each" notin line:
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
      ("the sectors near a ride", sectorsInBoxSql),
      ("the rides near a sector", ridesInBoxSql),
    ]:
      let p = plan(st.db, text)
      checkpoint what
      check usesSpatialIndex(p)
      check scans(p).len == 0
  test "what runs for each file or activity finds its rows by key":
    for (what, text) in [
      ("is the file known", knownFileSql),
      ("the track of an activity", trackSql),
      ("the selection of a user", "select activity_id from selection where user_id = ?"),
      (
        "the cells read",
        "select count(*) from coverage where country = ? and cell_lon = ? and cell_lat = ?",
      ),
      (
        "the heart rate of an activity",
        "select t, bpm from heartrate where activity_id = ? order by t",
      ),
      (
        "the efforts on a climb",
        "select e.elapsed_s from effort e where e.sector_id = ?",
      ),
      ("what was seen of a user", "select path from seen_file where user_id = ?"),
    ]:
      checkpoint what
      check scans(plan(st.db, text)).len == 0
  test "the criteria of a listing, each alone and all together":
    let none = none((float, float))
    let all = Criteria(
      sports: @["cycling"],
      subSports: @["road"],
      names: @["toyo"],
      namesExact: @["El Toyo"],
      starts: @["lisboa"],
      paths: @["bowman"],
      climbs: @["farellones"],
      climbIds: @[1'i64],
      distanceM: NumRange(lo: some 1.0, hi: some 2.0),
      activeS: NumRange(lo: some 1.0),
      fromT: some(UnixTime(1)),
      toT: some(UnixTime(2)),
      gps: gfWith,
      radiusKm: 5.0,
    )
    var each: seq[(string, Criteria, Option[(float, float)])] = @[
      ("none", Criteria(), none),
      ("sports", Criteria(sports: @["cycling"]), none),
      ("names", Criteria(names: @["toyo"]), none),
      ("paths", Criteria(paths: @["bowman"]), none),
      ("climbs", Criteria(climbs: @["x"], climbIds: @[1'i64]), none),
      ("a range", Criteria(distanceM: NumRange(lo: some 1.0)), none),
      ("no gps", Criteria(gps: gfWithout), none),
      ("near", Criteria(radiusKm: 5.0), some((38.7, -9.1))),
      ("near across the date line", Criteria(radiusKm: 50.0), some((-17.0, 179.9))),
      ("newest", Criteria(newest: 3), none),
      ("all", all, some((38.7, -9.1))),
    ]
    var inverted = all
    inverted.invert = true
    each.add ("all, inverted", inverted, some((38.7, -9.1)))
    for (what, c, centre) in each:
      let p = plan(st.db, matchSql(@[UserId(1)], c, centre).text)
      checkpoint what
      check scans(p).len == 0
      if centre.isSome:
        check usesSpatialIndex(p)
