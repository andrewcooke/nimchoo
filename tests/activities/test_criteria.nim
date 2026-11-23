import nimchoo/packages/ui/units
import nimchoo/packages/db/sqltext
import nimchoo/core/extension
from nimchoo/registry import extensions
import nimchoo/core/errors
import nimchoo/packages/user/session
import std/[options, sequtils, strutils, times, unittest]
from std/unicode import runeLen
import nimchoo/packages/fit/time
import nimchoo/core/ids
import nimchoo/packages/activities/criteria
import nimchoo/packages/activities/command as activitiesCommand
import nimchoo/packages/util/args/[args, usage]
import ../support/styles

let utcZone = utc()

func value(q: Sql, name: string): Arg =
  ## The value bound to `:name` (a test fails if there is none).
  for a in q.args:
    if a.name == name:
      return a.value
  raiseAssert "no value for :" & name

func has(q: Sql, name: string): bool =
  for a in q.args:
    if a.name == name:
      return true

func find(fs: seq[Filter], kind: FilterKind): Filter =
  ## The filter of that kind (a test that asks for one that is not there is wrong).
  for f in fs:
    if f.kind == kind:
      return f
  raiseAssert "no filter of kind " & $kind

func hasKind(fs: seq[Filter], kind: FilterKind): bool =
  fs.anyIt(it.kind == kind)

func withoutLatest(fs: seq[Filter]): seq[Filter] =
  for f in fs:
    let rest = f.withoutLatest
    if rest.isSome:
      result.add rest.get

func startKm(fs: seq[Filter]): float =
  near.startKm(fs.find(ftFrom).radius)

func passKm(fs: seq[Filter]): float =
  near.passKm(fs.find(ftNear).radius)

suite "list: times":
  test "a date is the start of its day in the given zone, as if written with T00:00:00":
    check parseWhen("2018-08-27", utcZone) == some(UnixTime(1535328000))
    check parseWhen("2018-08-27T00:00:00", utcZone) == parseWhen("2018-08-27", utcZone)
  test "minutes and seconds, with T or a space, exactly as written":
    check parseWhen("2018-08-27T10:30", utcZone) == some(UnixTime(1535365800))
    check parseWhen("2018-08-27 10:30", utcZone) == some(UnixTime(1535365800))
    check parseWhen("2018-08-27T10:30:15", utcZone) == some(UnixTime(1535365815))
  test "--on: a date (not a time), the day from its start to the next":
    check parseOnDay("2018-08-27", utcZone) ==
      some((start: UnixTime(1535328000), next: UnixTime(1535414400)))
    check parseOnDay("2018-08-27T10:30", utcZone).isNone
  test "the zone matters":
    let plus2 = newTimezone(
      "+2",
      proc(t: Time): ZonedTime =
        ZonedTime(time: t, utcOffset: -7200, isDst: false),
      proc(t: Time): ZonedTime =
        ZonedTime(
          time: t - initDuration(seconds = 7200), utcOffset: -7200, isDst: false
        ),
    )
    check parseWhen("2018-08-27", plus2) == some(UnixTime(1535328000 - 7200))
  test "rubbish":
    for bad in ["", "yesterday", "2018-13-45", "27/08/2018", "2018-08"]:
      check parseWhen(bad, utcZone).isNone

suite "list: the command line":
  proc cmdline(args: varargs[string]): Parsed[Request] =
    parseArgs(@args, utcZone)

  proc fs(args: varargs[string]): seq[Filter] =
    cmdline(args).params.scope.filtersOf

  test "--select and --all":
    check cmdline().params.scope.kind == scSelection and
      cmdline().params.action.kind == akList and not cmdline().params.action.select
    check cmdline("--all", "--select").params.action.select and
      cmdline("--all").params.scope.kind == scAll
    check cmdline("--sports", "cycling", "--select").params.action.select and
      cmdline("--sports", "cycling").params.scope.kind == scMatching
    check cmdline("--select").problem.contains("needs criteria or `--all`")
    check cmdline("--newest", "1").params.scope.kind == scMatching
      # (a limit searches all, too)

  test "a request is an action on a scope: what means nothing cannot be written":
    let d = cmdline("--all", "--delete").params
    check d.action.kind == akDelete and d.scope.kind == scAll
    expect FieldDefect:
      discard d.action.verbose # (a delete shows nothing: there is no -v to ask)
    expect FieldDefect:
      discard cmdline("--rename").params.action.select
    check cmdline("--all", "-n", "3").params.scope.allLimit ==
      some(Limit(kind: lkNewest, count: 3))
    expect FieldDefect:
      discard
        cmdline("--all").params.scope.filters # (every activity: no filters to hold)
    expect FieldDefect:
      discard cmdline().params.scope.limit
    check cmdline("--sports", "cycling", "--invert", "-n", "2").params.scope.limitOf ==
      some(Limit(kind: lkNewest, count: 2))
    # what the options can say and the request cannot, is refused when it is made
    for bad in [
      @["--delete", "-v"],
      @["--delete", "--select", "--all"],
      @["--rename", "--delete"],
      @["--rename", "-v"],
      @["--all", "--sports", "cycling"],
      @["-n", "1", "--oldest", "1"],
    ]:
      check parseArgs(bad, utcZone).kind == pkProblem
  test "the options":
    let r = cmdline(
      "--select", "--newest", "3", "--after", "2018-08-01", "--before", "2018-09-01",
      "--from", "38.7,-9.1", "--radius", "5km",
    ).params
    check r.action.select and r.scope.limit == some(Limit(kind: lkNewest, count: 3))
    let c = r.scope.filters
    check c.find(ftAfter).at == UnixTime(1533081600) and
      c.find(ftBefore).at == UnixTime(1535760000) # (August, the dates their midnights)
    let on = fs("--on", "2018-08-27")
    check on.find(ftAfter).at == UnixTime(1535328000) and
      on.find(ftBefore).at == UnixTime(1535414400)
    let from1 = c.find(ftFrom)
    check from1.place.kind == plPoint and from1.place.lat == 38.7 and
      from1.place.lon == -9.1 and from1.radius == some(Distance(5000.0))
    check not c.hasKind(ftNear)
    check fs("--from", "latest").find(ftFrom).place.refers == rfLatest
    let named = fs("--from", "Lo Barnechea").find(ftFrom).place
    check named.kind == plPlace and named.name == "Lo Barnechea"
    check cmdline("--from", "38.7").problem.contains("cannot read the position")
    let passing = fs("--near", "Farellones")
    check passing.find(ftNear).place.kind == plPlace and
      passing.find(ftNear).place.name == "Farellones" and not passing.hasKind(ftFrom)
    check passing.find(ftNear).radius.isNone # (each its own default: see "the radius")
    check fs("--near", "latest").find(ftNear).place.refers == rfLatest
  test "newest; oldest; but not both; --latest is gone (latest is a special value)":
    check cmdline("--newest", "1").params.scope.limit ==
      some(Limit(kind: lkNewest, count: 1))
    check cmdline("--latest").problem.len > 0
    check cmdline("--oldest", "2").params.scope.limit ==
      some(Limit(kind: lkOldest, count: 2))
    check cmdline("--newest", "2", "--oldest", "2").problem.contains("together")
    for bad in ["0", "-1", "x", "1.5"]:
      check cmdline("--newest", bad).problem.contains("number of activities")
    check cmdline("--oldest").problem.contains("needs a value")
  test "--all does not go with --radius, as it does not with --from latest":
    check cmdline("--all", "--from", "latest").problem.contains(
      "does not go with criteria"
    )
    check cmdline("--all", "--radius", "3km").problem.contains(
      "does not go with criteria"
    )
    check cmdline("--all", "--near", "Farellones").problem.contains(
      "does not go with criteria"
    )
  test "--radius on its own means --from latest":
    let c = fs("--radius", "5km")
    check c.find(ftFrom).place.refers == rfLatest and c.startKm == 5.0 and
      not c.hasKind(ftNear)
    check cmdline("--radius", "5km").problem == ""
  test "a radius with its unit: km or m; with no unit it is a question, with the corrected arguments":
    check fs("--radius", "500m").find(ftFrom).radius == some(Distance(500.0))
    check fs("--radius", "1.5km").find(ftFrom).radius == some(Distance(1500.0))
    let u = cmdline("--from", "latest", "--radius", "3")
    check u.kind == pkUnit
    check u.fix.args == @["--from", "latest", "--radius", "3km"]
    check u.fix.missing.len == 1 and u.fix.missing[0].option == "--radius"
    check cmdline("--radius=3").fix.args == @["--radius=3km"]
    for bad in ["0", "-1", "0km", "-1km", "nan", "inf", "3mi", "x", "km"]:
      check cmdline("--radius", bad).problem.contains("radius")
  test "sports and sub-sports, lower-cased, several, repeated":
    let c = cmdline(
      "--sports", "Cycling", "running", "Swimming", "--sub-sports", "ROAD", "--sports",
      "walking",
    ).params.scope.filters
    check c.find(ftSports).listed.values ==
      @["cycling", "running", "swimming", "walking"]
    check c.find(ftSubSports).listed.values == @["road"]
    check cmdline("--sports").problem.contains("at least one name")
    check cmdline("--sub-sports", "--select").problem.contains("at least one name")
  test "-v is a display option, not a criterion; --file is gone":
    check cmdline("-v").params.action.verbose and
      cmdline("--verbose").params.action.verbose
    check cmdline("-v").problem == ""
    check cmdline("--verbose").params.action.verbose
    check cmdline("--file").problem.contains("unexpected")
  test "-n is --newest":
    check cmdline("-n", "3").params.scope.limit == some(Limit(kind: lkNewest, count: 3))
    check cmdline("-n", "0").problem.contains("number of activities")
    check cmdline("-n").problem.contains("needs a value")
    check cmdline("-n", "2", "--oldest", "2").problem.contains("together")
  test "--distance and --active are ranges; a value that starts with a dash is a value":
    let c = fs("--distance", "-5km", "--active", "1h30m-4h")
    check c.find(ftDistance).spread.range == NumRange(hi: some 5000.0)
    check c.find(ftActive).spread.range == NumRange(lo: some 5400.0, hi: some 14400.0)
    for same in ["10km-50km", "10km-50000m"]:
      check fs("--distance", same).find(ftDistance).spread.range ==
        NumRange(lo: some 10000.0, hi: some 50000.0)
    check fs("--distance", "0.5km-").find(ftDistance).spread.range ==
      NumRange(lo: some 500.0)
    check fs("--distance", "500m-").find(ftDistance).spread.range ==
      NumRange(lo: some 500.0)
    check fs("--active", "30m-90m").find(ftActive).spread.range ==
      NumRange(lo: some 1800.0, hi: some 5400.0)
  test "a unit left out is filled in and asked about, never taken as it is":
    for (given, asked) in [
      ("42~2km", "42km~2km"),
      ("42km~2", "42km~2km"),
      ("42km~2000", "42km~2000m"),
      ("10-50km", "10km-50km"),
      ("10km-50", "10km-50km"),
    ]:
      let r = cmdline("--distance", given)
      check r.kind == pkUnit and r.fix.args == @["--distance", asked]
    check fs("--distance", "42km~2000m").find(ftDistance).spread.range ==
      NumRange(lo: some 40000.0, hi: some 44000.0)
  test "--distance and --active around a value, or around latest":
    let c = fs("--distance", "42km~2km", "--active", "2h~15m")
    check c.find(ftDistance).spread.range == NumRange(
      lo: some 40000.0, hi: some 44000.0
    )
    check c.find(ftActive).spread.range == NumRange(lo: some 6300.0, hi: some 8100.0)
    check not c.usesLatest
    let l = fs("--distance", "latest~10%", "--active", "latest~15m")
    check l.find(ftDistance).spread.byReference and
      l.find(ftDistance).spread.refers == rfLatest and
      l.find(ftDistance).spread.tol == Tol(amount: 10.0, percent: true)
    check l.find(ftActive).spread.tol == Tol(amount: 900.0)
    check l.usesLatest # (the range is not known until latest is found)
  test "latest as a sport and a sub-sport":
    let c = fs("--sports", "latest", "--sub-sports", "Latest", "road")
    check c.find(ftSports).listed.refers == some(rfLatest) and
      c.find(ftSubSports).listed.refers == some(rfLatest)
    check c.find(ftSports).listed.values.len == 0 and
      c.find(ftSubSports).listed.values == @["road"]
    check fs("--sports", "latest", "cycling").find(ftSports).listed.values ==
      @["cycling"]
  test "previous: in the same places, and kept apart from latest":
    let c = fs(
      "--sports", "previous", "--sub-sports", "previous", "--distance", "previous~10%",
      "--active", "Previous~15m", "--from", "previous",
    )
    check c.find(ftSports).listed.refers == some(rfPrevious) and
      c.find(ftSubSports).listed.refers == some(rfPrevious)
    check c.find(ftDistance).spread.refers == rfPrevious and
      c.find(ftDistance).spread.tol == Tol(amount: 10.0, percent: true)
    check c.find(ftActive).spread.refers == rfPrevious and
      c.find(ftActive).spread.tol == Tol(amount: 900.0)
    check c.find(ftFrom).place.refers == rfPrevious
    check c.usesPrevious and not c.usesLatest
    let mixed = fs("--sports", "previous", "--distance", "latest~5km")
    check mixed.usesPrevious and mixed.usesLatest
    check cmdline("--sports", "latest", "previous").problem.contains(
      "cannot be used together"
    )
    check cmdline("--sub-sports", "previous", "latest").problem.contains(
      "cannot be used together"
    )
    check cmdline("--sports", "previous", "previous").problem == ""
    check fs("--near", "previous").find(ftNear).place.refers == rfPrevious
    check fs("--near", "previous").usesPrevious
    check cmdline("--near", "38.7").problem.contains("latest or previous")
    check fs("--radius", "5km").find(ftFrom).place.refers == rfLatest
      # (alone: still latest)
  test "latest is found among the criteria that do not mention it, previous ones included":
    let c = fs("--sports", "previous", "--distance", "latest~5km", "--near", "previous")
    let base = c.withoutLatest
    check not base.usesLatest
    check base.usesPrevious # (resolved before, in the command)
    check base.find(ftNear).place.refers == rfPrevious and
      base.find(ftSports).listed.refers == some(rfPrevious)
    check not base.hasKind(ftDistance) # (all of it referred to latest)
  test "--from and --near latest use latest too, and the others that do not do not":
    check fs("--near", "latest").usesLatest
    check fs("--from", "latest").usesLatest
    check fs("--radius", "5km").usesLatest
    check not fs("--near", "1,2").usesLatest
    check not fs("--sports", "cycling", "--distance", "5km-", "-n", "1").usesLatest
  test "without latest: what latest is found among":
    let c = fs(
      "--sports", "latest", "cycling", "--distance", "latest~5km", "--active",
      "latest~5%", "--near", "latest", "--sub-sports", "latest", "-n", "3", "--after",
      "2018-01-01", "--distance", "latest~2km",
    )
    let base = c.withoutLatest
    check not base.usesLatest
    check base.find(ftSports).listed.values == @["cycling"] # (what was named stays)
    check base.find(ftAfter).at == c.find(ftAfter).at # (and the other criteria)
    check not base.hasKind(ftSubSports) and not base.hasKind(ftNear)
  test "--distance and --active problems":
    check cmdline("--distance", "5").problem.contains(
      "cannot read the distance range '5'"
    )
    check cmdline("--distance", "1-2-3").problem.contains("cannot read")
    check cmdline("--distance", "50-10km").problem.contains("backwards")
    check cmdline("--distance", "0km-").problem.contains("cannot read")
    check cmdline("--distance", "5mi-").problem.contains("cannot read")
    check cmdline("--distance", "latest~5mi").problem.contains("cannot read")
    check cmdline("--active", "2h30m-3").problem.contains(
      "cannot read the active time range"
    ) # (which of the units of 2h30m is meant for the 3?)
    check cmdline("--active", "2h-1h").problem.contains("backwards")
    check cmdline("--distance").problem.contains("needs a value")
    check cmdline("--distance", "latest~").problem.contains("cannot read the distance")
    check cmdline("--distance", "~5").problem.contains("cannot read the distance")
    check cmdline("--active", "latest~x").problem.contains(
      "cannot read the active time"
    )
    check cmdline("--active", "2h~15").fix.args == @["--active", "2h~15m"]
  test "--distance and --active with no unit anywhere are the question, the unit added to the first number":
    for (args, fixed) in [
      (@["--distance", "40-"], @["--distance", "40km-"]),
      (@["--distance", "10-50"], @["--distance", "10km-50km"]),
      (@["--distance", "42~2"], @["--distance", "42km~2km"]),
      (@["--distance", "latest~5"], @["--distance", "latest~5km"]),
      (@["--active", "90-"], @["--active", "90h-"]),
      (@["--active", "1~2"], @["--active", "1h~2h"]),
      (
        @["--sports", "cycling", "--distance=40-"],
        @["--sports", "cycling", "--distance=40km-"],
      ),
    ]:
      let r = parseArgs(args, utcZone)
      check r.kind == pkUnit
      check r.fix.args == fixed
    check cmdline("--distance", "40-", "--active", "1-").fix.missing.len == 2
    check cmdline("--distance", "40km-").kind == pkOk
    check cmdline("--distance", "-5").kind == pkUnit
  test "the radius: 10 km from a start, 1 km from a route, unless --radius says":
    check fs("--from", "1,2").startKm == 10.0
    check fs("--near", "1,2").passKm == 1.0
    check fs("--near", "1,2", "--radius", "3km").passKm == 3.0
  test "--all is every activity: it does not go with criteria, but with the limits":
    check cmdline("--all", "--sports", "cycling").problem.contains(
      "does not go with criteria"
    )
    check cmdline("--all", "--newest", "1").problem == ""
    check cmdline("--all", "--select").problem == ""
    check cmdline("--all", "-h").problem == ""
    check cmdline("--all", "--invert").problem.contains("needs a criterion")

  test "problems":
    check cmdline("--radius", "x", "--near", "1,2").problem.contains("radius")
    check cmdline("--radius", "0km", "--near", "1,2").problem.contains("more than 0")
    check cmdline("--near", "38.7").problem.contains("position")
    check cmdline("--after", "soon").problem.contains("cannot read the time")
    check cmdline("--after", "2018-09-01", "--before", "2018-08-01").problem.contains(
      "not before"
    )
    check cmdline("--after", "2018-08-01", "--before", "2018-08-01").problem.contains(
      "not before"
    ) # (an empty range: nothing could be found)
    check cmdline("--after").problem.contains("needs a value")
    check cmdline("--on", "2018-08-27T09:00").problem.contains("takes a date")
    check cmdline("--on", "2018-08-27", "--before", "2018-09-01").problem.contains(
      "does not go with `--after` or `--before`"
    )
    check cmdline("--bogus").problem.contains("unexpected")
    check cmdline("-h").help

suite "list: the box and the sql":
  test "--from: the index of the start points, and the distance from the start":
    let q =
      matchSql(UserId(1), @[Resolved(kind: rtFrom, lat: 38.7, lon: -9.1, km: 5.0)])
    let m = q.text
    check m.contains("f_table_name = 'activity'") and
      m.contains("f_geometry_column = 'start'")
    check m.contains(
      "ST_Distance(a.start, MakePoint(:startLon, :startLat, 4326), 1) <= :startM"
    )
    check q.value("startLon") == arg(-9.1) and q.value("startLat") == arg(38.7) and
      q.value("startM") == arg(5000.0)
    check not m.contains("route")
    let across =
      matchSql(UserId(1), @[Resolved(kind: rtFrom, lat: -17.0, lon: 179.9, km: 50.0)])
    check across.text.count("SpatialIndex") == 2 and across.text.contains(" or ")
    check across.has("startBox0West") and across.has("startBox1North")
  test "--near: the index of the routes, and the distance from the route":
    let q =
      matchSql(UserId(1), @[Resolved(kind: rtNear, lat: 38.7, lon: -9.1, km: 1.0)])
    let m = q.text
    check m.contains("f_table_name = 'route'") and
      m.contains("f_geometry_column = 'geom'")
    check m.contains(
      "ST_Distance(r.geom, MakePoint(:passLon, :passLat, 4326), 1) <= :passM"
    )
    check q.value("passM") == arg(1000.0) # (the default)
    check not m.contains("a.start,")
  test "--gps and --no-gps":
    check parseArgs(@["--gps"], utcZone).params.scope.filters.find(ftGps).gps == gpsWith
    check parseArgs(@["--no-gps"], utcZone).params.scope.filters.find(ftGps).gps ==
      gpsWithout
    check parseArgs(@["--sports", "cycling"], utcZone).params.scope.filters
      .hasKind(ftGps).not
    check parseArgs(@["--gps", "--gps"], utcZone).problem == ""
    check parseArgs(@["--gps", "--no-gps"], utcZone).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--no-gps", "--gps"], utcZone).problem.contains(
      "cannot be used together"
    )
    let with = matchSql(UserId(1), @[Resolved(kind: rtGps, gps: gpsWith)]).text
    check with.contains(
      " and exists (select 1 from track k where k.activity_id = a.id)"
    )
    let without = matchSql(UserId(1), @[Resolved(kind: rtGps, gps: gpsWithout)]).text
    check without.contains(
      " and not exists (select 1 from track k where k.activity_id = a.id)"
    )
    check not matchSql(UserId(1), @[]).text.contains("coords")

  test "the sql has what was asked for, and nothing else":
    let q = matchSql(UserId(2), @[])
    let plain = q.text
    check plain ==
      "select a.id from activity a join file f on f.id = a.file_id where f.user_id = :user"
    check q.args.len == 1 and q.value("user") == arg(2'i64)
    check not plain.contains("start_t") and not plain.contains("route") and
      not plain.contains("limit")
    let fullQ = matchSql(
      UserId(1),
      @[
        Resolved(kind: rtAfter, at: UnixTime(5)),
        Resolved(kind: rtBefore, at: UnixTime(9)),
        Resolved(kind: rtFrom, lat: 38.7, lon: -9.1, km: 5.0),
      ],
      sqlOf("a.id, a.start_t"),
      limit = some(Limit(kind: lkNewest, count: 2)),
    )
    let full = fullQ.text
    check full.startsWith("select a.id, a.start_t from activity a")
    check full.contains("a.start_t >= :afterT") and full.contains(
      "a.start_t < :beforeT"
    )
    check fullQ.value("afterT") == arg(5) and fullQ.value("beforeT") == arg(9)
    check full.contains("SpatialIndex") and
      full.contains("MakePoint(:startLon, :startLat, 4326)")
    check fullQ.value("startM") == arg(5000.0)
    check full.endsWith("order by a.start_t desc limit :newest")
    check fullQ.value("newest") == arg(2)
    let oldest = matchSql(UserId(1), @[], limit = some(Limit(kind: lkOldest, count: 4)))
    check oldest.text.endsWith("order by a.start_t asc limit :oldest")
    check oldest.value("oldest") == arg(4)
  test "sports are bound values, none means NULL, nothing without values":
    check inValues("a.sport", "sport", @[]).text == ""
    let two = inValues("a.sport", "sport", @["cycling", "running"])
    check two.text == " and (a.sport in (:sport0, :sport1))"
    check two.value("sport0") == arg("cycling") and two.value("sport1") == arg(
      "running"
    )
    let none1 = inValues("a.sub_sport", "subSport", @["none"])
    check none1.text == " and (a.sub_sport is null)" and none1.args.len == 0
    let mixed = inValues("a.sub_sport", "subSport", @["road", "none"])
    check mixed.text == " and (a.sub_sport in (:subSport0) or a.sub_sport is null)"
    let hostile = inValues("a.sport", "sport", @["x'; drop table user; --"])
    check hostile.text == " and (a.sport in (:sport0))"
    check hostile.value("sport0") == arg("x'; drop table user; --")
    let m = matchSql(
      UserId(1),
      @[
        Resolved(kind: rtSports, values: @["cycling"]),
        Resolved(kind: rtSubSports, values: @["none"]),
      ],
    )
    check m.text.contains("a.sport in (:sport0)") and
      m.text.contains("a.sub_sport is null")
    check not matchSql(UserId(1), @[]).text.contains("sport")
  test "ranges become inclusive comparisons, only for the ends given":
    check rangeSql("a.distance_m", "distance", NumRange()).text == ""
    let lo = rangeSql("a.distance_m", "distance", NumRange(lo: some 40000.0))
    check lo.text == " and a.distance_m >= :distanceLo" and
      lo.value("distanceLo") == arg(40000.0)
    let hi = rangeSql("a.timer_s", "active", NumRange(hi: some 3600.0))
    check hi.text == " and a.timer_s <= :activeHi" and
      hi.value("activeHi") == arg(3600.0)
    let both = rangeSql("a.timer_s", "active", NumRange(lo: some 60.0, hi: some 120.5))
    check both.text == " and a.timer_s >= :activeLo and a.timer_s <= :activeHi"
    check both.value("activeHi") == arg(120.5) # (exact: not rounded to 3 decimals)
    let m = matchSql(
      UserId(1),
      @[
        Resolved(kind: rtDistance, range: NumRange(lo: some 1000.0)),
        Resolved(kind: rtActive, range: NumRange(hi: some 60.0)),
      ],
    )
    check m.text.contains("a.distance_m >= :distanceLo") and
      m.text.contains("a.timer_s <= :activeHi")
    check not matchSql(UserId(1), @[]).text.contains("distance_m")

suite "list: the two stages of a filter":
  test "a reference cannot reach the sql: matchSql takes only resolved filters":
    check not compiles(
      matchSql(
        UserId(1), @[Filter(kind: ftSports, listed: Listed(refers: some(rfLatest)))]
      )
    )
    check compiles(matchSql(UserId(1), @[Resolved(kind: rtSports, values: @["x"])]))
  test "every kind of filter says whether it refers to an activity, and what is left of it without latest":
    let latest = some(rfLatest)
    let spread = Spread(byReference: true, refers: rfLatest, tol: Tol(amount: 5.0))
    let refers = @[
      Filter(kind: ftSports, listed: Listed(values: @["cycling"], refers: latest)),
      Filter(kind: ftSubSports, listed: Listed(refers: latest)),
      Filter(kind: ftNames, listed: Listed(refers: latest)),
      Filter(kind: ftStarts, listed: Listed(values: @["x"], refers: latest)),
      Filter(kind: ftDistance, spread: spread),
      Filter(kind: ftActive, spread: spread),
      Filter(kind: ftFrom, place: Place(kind: plReferent, refers: rfLatest)),
      Filter(kind: ftNear, place: Place(kind: plReferent, refers: rfLatest)),
    ]
    for f in refers:
      check f.refersTo(rfLatest) and not f.refersTo(rfPrevious)
      let rest = f.withoutLatest
      # (what is named stays; what was only the reference goes)
      check rest.isNone or not rest.get.refersTo(rfLatest)
      check (rest.isSome) == (f.kind in {ftSports, ftStarts})
    let plain = @[
      Filter(kind: ftSports, listed: Listed(values: @["cycling"])),
      Filter(kind: ftPaths, paths: @["x"]),
      Filter(kind: ftAfter, at: UnixTime(1)),
      Filter(kind: ftBefore, at: UnixTime(2)),
      Filter(kind: ftGps, gps: gpsWith),
      Filter(kind: ftDistance, spread: Spread(byReference: false)),
      Filter(kind: ftFrom, place: Place(kind: plPoint, lat: 1.0, lon: 2.0)),
    ]
    for f in plain:
      check not f.refersTo(rfLatest) and not f.refersTo(rfPrevious)
      check f.withoutLatest.isSome

suite "list: --names and --starts":
  proc parsed(args: varargs[string]): seq[Filter] =
    parseArgs(@args, utcZone).params.scope.filtersOf

  test "the words are alternatives; a name with spaces is one; a comma is part of a word":
    let c =
      parsed("--names", "toyo", "farellones", "--starts", "providencia", "ñuñoa")
    check parsed("--names", "a,b").find(ftNames).listed.values == @["a,b"]
    check c.find(ftNames).listed.values == @["toyo", "farellones"] and
      c.find(ftStarts).listed.values == @["providencia", "ñuñoa"]
    check parsed("--names", "el toyo").find(ftNames).listed.values == @["el toyo"]
  test "latest and previous are references, not text; they cannot be mixed":
    let c = parsed("--names", "latest", "--starts", "previous")
    check c.find(ftNames).listed.refers == some(rfLatest) and
      c.find(ftStarts).listed.refers == some(rfPrevious)
    check c.find(ftNames).listed.values.len == 0 and
      c.find(ftStarts).listed.values.len == 0
    check c.usesLatest and c.usesPrevious
    check not c.withoutLatest.usesLatest
    check parseArgs(@["--names", "latest", "previous"], utcZone).problem.contains(
      "cannot be used together"
    )
  test "a name needs some text; it is a criterion ":
    check parseArgs(@["--names"], utcZone).problem.len > 0
  test "the sql: the folded text found in the column, none for nothing, an exact value for what latest came to":
    let m = matchSql(
      UserId(1),
      @[
        Resolved(kind: rtNames, typed: @["toyo", "none"]),
        Resolved(kind: rtStarts, typed: @["o'higgins"]),
      ],
    )
    let q = m.text
    check q.contains("instr(fold(a.name), :nameT0) > 0") and
      q.contains("(a.name is null or a.name = '')")
    check m.value("nameT0") == arg("toyo") # (folded)
    check q.contains("instr(fold(a.start_place), :startT0) > 0")
    check m.value("startT0") == arg("o'higgins") # (bound as it is: no quotes to double)
    let rq = matchSql(
      UserId(1),
      @[
        Resolved(kind: rtNames, exact: @["El Toyo and back", ""]),
        Resolved(kind: rtStarts, exact: @["Providencia"]),
      ],
    )
    let r = rq.text
    check r.contains("a.name = :nameE0") and
      r.contains("(a.name is null or a.name = '')")
    check rq.value("nameE0") == arg("El Toyo and back")
    check r.contains("a.start_place = :startE0") and
      rq.value("startE0") == arg("Providencia")
    check not matchSql(UserId(1), @[]).text.contains("fold(")

suite "list: --paths":
  test "the words are alternatives; the sql looks in the file's name and in every path it was seen at":
    let c =
      parseArgs(@["--paths", "bowman", "run", "2026-10"], utcZone).params.scope.filters
    check c.find(ftPaths).paths == @["bowman", "run", "2026-10"]
    let m =
      matchSql(UserId(1), @[Resolved(kind: rtPaths, paths: c.find(ftPaths).paths)])
    let q = m.text
    check q.contains("instr(fold(f.name), :path0) > 0") and
      q.contains(
        "from seen_file s where s.file_id = f.id and instr(fold(s.path), :path0) > 0"
      )
    check m.value("path0") == arg("bowman") and m.has("path2")
    check not matchSql(UserId(1), @[]).text.contains("seen_file")
  test "latest is just text here; a path needs some text and is a criterion":
    check parseArgs(@["--paths", "latest"], utcZone).params.scope.filters
      .find(ftPaths).paths == @["latest"]
    check parseArgs(@["--paths"], utcZone).problem.len > 0

suite "list: --invert":
  test "it is a criterion on its own, and needs something to invert":
    check parseArgs(@["--sports", "cycling", "--invert"], utcZone).params.scope.invert
    check parseArgs(@["--invert"], utcZone).problem.contains("needs a criterion")
    check parseArgs(@["--invert", "--newest", "2"], utcZone).problem.contains(
      "needs a criterion"
    ) # (limits are not criteria)
    check parseArgs(@["--invert", "--gps"], utcZone).problem == ""
    check parseArgs(@["--invert", "--distance", "40km-"], utcZone).problem == ""
    check parseArgs(@["--invert", "--names", "latest"], utcZone).problem == ""
  test "the sql negates all of the criteria together, treating an unknown as no match":
    let filters = @[
      Resolved(kind: rtSports, values: @["cycling"]),
      Resolved(kind: rtNames, typed: @["toyo"]),
    ]
    let q = matchSql(UserId(1), filters, invert = true).text
    check q.contains(
      " and not coalesce((1 and (a.sport in (:sport0)) and (instr(fold(a.name), :nameT0) > 0"
    )
    check q.endsWith("), 0)")
    check not matchSql(UserId(1), filters).text.contains("coalesce")
  test "the limits come after the inverting, and latest is found before it":
    let filters = @[Resolved(kind: rtSports, values: @["cycling"])]
    check matchSql(
      UserId(1), filters, invert = true, limit = some(Limit(kind: lkNewest, count: 2))
    ).text
      .endsWith(" order by a.start_t desc limit :newest")
    let r = parseArgs(@["--distance", "latest~10%", "--invert"], utcZone).params.scope
    check r.filters.usesLatest and r.invert and not r.filters.withoutLatest.usesLatest

suite "list: criteria that other packages offer":
  func pick(st: Session, values: seq[string]): Resolution {.raises: [StoreError].} =
    Resolution(condition: sqlOf("a.id = 7"))

  let offered = Criterion(
    doc: OptDoc(
      names: @["--odd", "-o"],
      metavar: some("WORD..."),
      help: ~"an offered option",
      arity: aList,
    ),
    resolve: pick,
  )

  test "an offered option is parsed with the others, and kept as given for its package to resolve":
    let c = parseArgs(
      @["--odd", "a", "b", "-o", "c", "--sports", "cycling"], utcZone, @[offered]
    ).params.scope.filters
    check c.find(ftContributed).contributed.option == "--odd"
    check c.find(ftContributed).contributed.values == @["a", "b", "c"]
    check c.find(ftSports).listed.values == @["cycling"]
  test "it is a criterion: it needs words, and it can be inverted":
    check parseArgs(@["--odd"], utcZone, @[offered]).problem.len > 0
    check parseArgs(@["--invert", "--odd", "x"], utcZone, @[offered]).problem == ""
    check parseArgs(@["--all", "--odd", "x"], utcZone, @[offered]).problem.len > 0
  test "without the package that offers it the option is unknown":
    check parseArgs(@["--odd", "x"], utcZone).problem.contains("unexpected option")
  test "it is in the usage":
    check "--odd, -o WORD..." in
      optionLines(criteriaSpec(@[offered]).docs, 100).plainText
  test "the conditions are joined by the command, with and":
    let q =
      matchSql(UserId(1), @[Resolved(kind: rtCondition, condition: sqlOf("a.id = 7"))])
    check q.text.contains(" and (a.id = 7)")
  test "the conditions come in a fixed order, whatever the order of the filters":
    let a = Resolved(kind: rtActive, range: NumRange(lo: some 1.0))
    let s = Resolved(kind: rtSports, values: @["cycling"])
    check matchSql(UserId(1), @[a, s]).text == matchSql(UserId(1), @[s, a]).text

suite "list: --delete":
  test "--delete is an action, not a criterion; -y answers its question":
    let r = parseArgs(@["--delete", "-y"], utcZone)
    check r.params.action.kind == akDelete and r.yes and
      r.params.scope.kind == scSelection
    check not parseArgs(@["--delete"], utcZone).yes
    check parseArgs(@["--sports", "cycling", "--delete"], utcZone).params.scope.kind ==
      scMatching
    check parseArgs(@["--all", "--delete", "-y"], utcZone).problem == ""
    check parseArgs(@["--delete", "--select"], utcZone).problem.contains(
      "shows nothing"
    )
    check parseArgs(@["--delete", "-v"], utcZone).problem.contains("shows nothing")

suite "list: the usage":
  test "every option has a description (the compiler asks for it)":
    for d in criteriaSpec().docs:
      check d.help.len > 0
  test "the usage lists every option, at any width":
    for width in [60, 80, 120]:
      let text = activitiesCommand.usageText(width).plainText
      for d in criteriaSpec().docs:
        for n in d.names:
          check n in text
  test "the whole usage fits the width, except the synopsis lines":
    for width in [60, 80, 120]:
      for l in activitiesCommand.usageText(width).plainText.splitLines:
        if not (l.startsWith("usage: ") or l.startsWith("       nch ")):
          check l.runeLen <= width
  test "an option of another package would be listed and parsed from its description":
    let extra = OptDoc(
      names: @["--extra"],
      metavar: some("WORDS..."),
      help: ~"something offered by another package",
      arity: aList,
    )
    check "--extra WORDS..." in optionLines(criteriaSpec().docs & extra, 100).plainText

suite "list: the criteria of the packages":
  test "no two offered criteria share a name, and none takes the name of an option of the command":
    var names: seq[string]
    for o in extensions.get(activityCriterion):
      for n in o.doc.names:
        check n notin names
        names.add n
    for d in criteriaSpec().docs:
      for n in d.names:
        check n notin names
  test "the climbs offer --climbs, and it shows in the usage":
    check "--climbs" in
      activitiesCommand.usageText(100, extensions.get(activityCriterion)).plainText

suite "list: --select":
  test "--select keeps what is listed; --save, its other name, is gone":
    check parseArgs(@["--all", "--save"], utcZone).problem.len > 0
    check parseArgs(@["--all", "--select"], utcZone).params.action.select
