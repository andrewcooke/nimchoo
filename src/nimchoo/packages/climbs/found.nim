## The climbs that criteria find (`nch climbs CRITERIA`, `--all`): one query, each criterion a condition on `sector` (the names
## are matched as they are shown, with their numbers, so those are found first: `attempts.namedClimbs`).  Retired climbs are
## never found, as they are in no list.

import std/[json, strformat]
import ../../core/errors
import ../db/[sqltext, statement]
import ../geo/position
import ../names/places
import ../near/[distance, near]
import ../user/session
import ../subject/subjects
import ./[attempts, params]

{.push raises: [].}

type Found* = object
  ids*: seq[int64] ## the biggest first
  notes*: seq[string]
    ## what was taken for what was asked ("near -33.4200,-70.6100 (Providencia, ...), within 10km")

func placeCondition(passes: bool, lat, lon, km: float): Sql =
  ## The climbs whose line passes within `km` of the point (`passes`), or that start within it: the distance on the
  ## ellipsoid, in metres.
  if passes:
    withinSql("CastToXY(s.route)", "pass", lat, km * 1000.0)
      .with("passLon", lon)
      .with("passLat", lat)
      .with("passM", km * 1000.0)
  else:
    sqlOf(
      """ST_Distance(MakePoint(ST_X(StartPoint(s.route)), ST_Y(StartPoint(s.route)), 4326),
                     MakePoint(:startLon, :startLat, 4326), 1) <= :startM"""
    )
      .with("startLon", lon)
      .with("startLat", lat)
      .with("startM", km * 1000.0)

func searchOf(st: Session, conditions: seq[Sql], among: Among, invert: bool): Sql =
  ## The climbs (not retired) among those `among` says that meet every condition (or, `invert`, do not).
  result = sqlOf("select s.id from sector s where s.retired = 0")
  case among
  of amEvery:
    discard
  of amSelection:
    result =
      result &
      sqlOf(
        " and s.id in (select sector_id from climb_selection where user_id = :among)"
      )
      .with("among", st.userId)
  if conditions.len > 0:
    var joined = conditions[0]
    for k in 1 .. conditions.high:
      joined = joined & " and " & conditions[k]
    result =
      if invert:
        result & " and not coalesce((" & joined & "), 0)"
      else:
        result & " and (" & joined & ")"

proc foundClimbs*(
    st: Session, c: ClimbCriteria, among = amEvery, also = false
): Found {.raises: [StoreError].} =
  ## The climbs (not retired) that the criteria find, the biggest first; with none given, every climb.  `among`: every
  ## climb, or only the climbs selection (`--within`; `--invert` then means those of the selection the others do not find).
  ## A place's name is the first of the places it may mean for which the other criteria find a climb (the usage's steps;
  ## names/places.nim): `--from` is chosen first, without `--near`, then `--near`.
  var conditions: seq[Sql]
  if c.names.len > 0:
    conditions.add sqlOf("s.id in (select value from json_each(:named))").with(
      "named", jsonList(namedClimbs(st, c.names))
    )
  if c.ridden:
    conditions.add sqlOf(
      """exists (select 1 from effort e join activity_selection x on x.activity_id = e.activity_id
                    where e.sector_id = s.id and x.user_id = :owner)"""
    )
      .with("owner", st.userId)
  if c.categories.len > 0:
    conditions.add sqlOf("s.category in (select value from json_each(:categories))")
      .with("categories", $(%c.categories))
  for (near, passes) in [(c.start, false), (c.passes, true)]:
    if near.kind == nkNone:
      continue
    let n = near
    let km = if passes: c.passKm else: c.startKm
    var (lat, lon) = (0.0, 0.0)
    var said = ""
    case n.kind
    of nkPoint:
      (lat, lon) = (n.lat, n.lon)
    of nkPlace:
      let before = conditions
      let passing = passes # (a copy: the loop's own cannot be captured)
      let finds = proc(lat, lon: float): bool {.closure, raises: [StoreError].} =
        st.db.scalar(
          int,
          sqlOf("select exists (") &
            searchOf(
              st, before & @[placeCondition(passing, lat, lon, km)], among, false
            ) & ")",
        ) == 1
      let p = placeNamed(st, n.place, finds)
      (lat, lon) = (p.lat, p.lon)
      said = fmt" ({p.said})"
    of nkNone, nkLatest, nkPrevious:
      raiseAssert "climbs read no latest or previous"
    let what = if passes: "passing near" else: "starting near"
    result.notes.add fmt"{what} {positionText((lon: lon, lat: lat))}{said}, within {km:g}km"
    conditions.add placeCondition(passes, lat, lon, km)
  var query = searchOf(st, conditions, among, c.invert)
  if also:
    # (--also: the climbs selection is added, after the criteria)
    query =
      sqlOf("select s.id from sector s where s.retired = 0 and (s.id in (") & query &
      sqlOf(
        ") or s.id in (select sector_id from climb_selection where user_id = :alsoOwner))"
      )
      .with("alsoOwner", st.userId)
  result.ids = st.db.query(int64, query & " order by s.gain_m desc, s.id")
