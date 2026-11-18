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
  if c.near.isSome:
    let n = c.near.get
    var (lat, lon) = (0.0, 0.0)
    var said = ""
    case n.kind
    of nrPoint:
      (lat, lon) = (n.lat, n.lon)
    of nrPlace:
      let places = placesNamed(st, n.place)
      if places.len == 0:
        raiseStore(
          fmt"no place is called '{n.place}' among your landmarks (`nch landmarks`) and the places the names were loaded for (the countries of your rides): give LAT,LON instead"
        )
      let p = places[0]
      (lat, lon) = (p.lat, p.lon)
      let others =
        case places.len
        of 1:
          ""
        of 2:
          "; 1 other has the name"
        else:
          fmt"; {places.len - 1} others have the name"
      said = fmt" ({p.name}, {p.what}{others})"
    result.notes.add fmt"near {positionText((lon: lon, lat: lat))}{said}, within {n.radiusKm:g}km"
    # (the distance on the ellipsoid, in metres, from where the climb starts)
    conditions.add sqlOf(
      """ST_Distance(MakePoint(ST_X(StartPoint(s.route)), ST_Y(StartPoint(s.route)), 4326),
                       MakePoint(:lon, :lat, 4326), 1) <= :metres"""
    )
      .with("lon", lon)
      .with("lat", lat)
      .with("metres", n.radiusKm * 1000.0)
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
