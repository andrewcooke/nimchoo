import std/[options, unittest]
import nimchoo/packages/db/statement
import nimchoo/packages/user/session
import nimchoo/packages/climbs/[found, params, work]
import nimchoo/packages/near/near
import nimchoo/packages/ui/units
import ../support/climbdata

proc world(name: string): Session =
  ## A climb on the road of the test rides (on the equator, starting about 1 km east of 0,0), ridden twice, once selected.
  let s = fresh(name)
  addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
  addRide(s, "default", "two", 2_000_000, 6.0, eastbound(6.0))
  discard ensureClimbs(s)
  s

proc point(lat, lon: float): Spot =
  Spot(kind: nkPoint, lat: lat, lon: lon)

suite "climbs: the climbs that criteria find":
  test "with none, every climb; a retired one never":
    let s = world("found-all")
    defer:
      s.close()
    let all = foundClimbs(s, ClimbCriteria()).ids
    check all.len == 1
    s.db.execute("update sector set retired = 1")
    check foundClimbs(s, ClimbCriteria()).ids.len == 0

  test "--ridden: those the selected activities went up":
    let s = world("found-ridden")
    defer:
      s.close()
    check foundClimbs(s, ClimbCriteria(ridden: true)).ids.len == 0
    s.db.execute(
      "insert into selection(user_id, activity_id) select :userId, min(id) from activity",
      userId = s.userId,
    )
    check foundClimbs(s, ClimbCriteria(ridden: true)).ids.len == 1

  test "--from: those that start within the radius, measured on the ground":
    let s = world("found-from")
    defer:
      s.close()
    check foundClimbs(
      s, ClimbCriteria(start: point(0.0, 0.0), radius: some(Distance(2000.0)))
    ).ids.len == 1
    check foundClimbs(
      s, ClimbCriteria(start: point(0.0, 0.0), radius: some(Distance(500.0)))
    ).ids.len == 0 # (it starts about 1 km east)
    let far = foundClimbs(s, ClimbCriteria(start: point(1.0, 1.0)))
    check far.ids.len == 0 and far.notes == @[
      "starting near 1.0000,1.0000, within 10km"
    ]

  test "--near: those whose line passes within the radius":
    let s = world("found-near")
    defer:
      s.close()
    # (the climb runs east along the equator from about 1 km to 4 km: a point 2.5 km east is on it, not near its start)
    let onIt = point(0.0, 2500.0 * metre)
    check foundClimbs(s, ClimbCriteria(passes: onIt)).ids.len == 1
    check foundClimbs(s, ClimbCriteria(start: onIt, radius: some(Distance(1000.0)))).ids.len ==
      0
    let aside = point(0.02, 2500.0 * metre) # (about 2.2 km north of it)
    check foundClimbs(s, ClimbCriteria(passes: aside)).ids.len == 0
    check foundClimbs(s, ClimbCriteria(passes: aside, radius: some(Distance(3000.0)))).ids.len ==
      1

  test "--categories, --names, and --invert of them all together":
    let s = world("found-other")
    defer:
      s.close()
    let category = s.db.scalar(string, "select coalesce(category, '') from sector")
    check category.len > 0
    check foundClimbs(s, ClimbCriteria(categories: @[category])).ids.len == 1
    check foundClimbs(s, ClimbCriteria(categories: @["HC"])).ids.len ==
      (if category == "HC": 1 else: 0)
    check foundClimbs(s, ClimbCriteria(names: @["unnamed"])).ids.len == 1
    check foundClimbs(s, ClimbCriteria(names: @["nonesuch"])).ids.len == 0
    check foundClimbs(s, ClimbCriteria(names: @["nonesuch"], invert: true)).ids.len == 1
    check foundClimbs(
      s, ClimbCriteria(names: @["unnamed"], categories: @["HC", category], invert: true)
    ).ids.len == 0
