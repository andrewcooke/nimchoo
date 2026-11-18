## The climbs that criteria find (`nch climbs CRITERIA`, `--all`): one query, each criterion a condition on `sector` (the names
## are matched as they are shown, with their numbers, so those are found first: `attempts.namedClimbs`).  Retired climbs are
## never found, as they are in no list.

import std/[json, options, strformat]
import ../../core/errors
import ../db/[sqltext, statement]
import ../geo/position
import ../names/places
import ../user/session
import ./[attempts, params]

{.push raises: [].}

type Found* = object
  ids*: seq[int64] ## the biggest first
  notes*: seq[string]
    ## what was taken for what was asked ("near -33.4200,-70.6100 (Providencia, ...), within 10km")

proc foundClimbs*(st: Session, c: ClimbCriteria): Found {.raises: [StoreError].} =
  ## The climbs (not retired) that the criteria find, the biggest first; with none given, every climb.
  var conditions: seq[Sql]
  if c.names.len > 0:
    conditions.add sqlOf("s.id in (select value from json_each(:named))").with(
      "named", jsonList(namedClimbs(st, c.names))
    )
  if c.ridden:
    conditions.add sqlOf(
      """exists (select 1 from effort e join selection x on x.activity_id = e.activity_id
                    where e.sector_id = s.id and x.user_id = :owner)"""
    )
      .with("owner", st.userId)
  for (near, passes) in [(c.start, false), (c.passes, true)]:
    if near.isNone:
      continue
    let n = near.get
    var (lat, lon) = (0.0, 0.0)
    var said = ""
    case n.kind
    of nrPoint:
      (lat, lon) = (n.lat, n.lon)
    of nrPlace:
      let p = placeNamed(st, n.place)
      (lat, lon) = (p.lat, p.lon)
      said = fmt" ({p.said})"
    let km = if passes: c.passKm else: c.startKm
    let what = if passes: "passing near" else: "starting near"
    result.notes.add fmt"{what} {positionText((lon: lon, lat: lat))}{said}, within {km:g}km"
    # (the distance on the ellipsoid, in metres: from any point of the climb's line, or from where it starts)
    conditions.add(
      if passes:
        sqlOf(
          "ST_Distance(CastToXY(s.route), MakePoint(:passLon, :passLat, 4326), 1) <= :passM"
        )
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
    )
  if c.categories.len > 0:
    conditions.add sqlOf("s.category in (select value from json_each(:categories))")
      .with("categories", $(%c.categories))
  var query = sqlOf("select s.id from sector s where s.retired = 0")
  if conditions.len > 0:
    var joined = conditions[0]
    for k in 1 .. conditions.high:
      joined = joined & " and " & conditions[k]
    query =
      if c.invert:
        query & " and not coalesce((" & joined & "), 0)"
      else:
        query & " and (" & joined & ")"
  result.ids = st.db.query(int64, query & " order by s.gain_m desc, s.id")
