import std/[options, strutils, times, unittest]
import nimchoo/fit/time
import nimchoo/ids
import nimchoo/selection/criteria

let utcZone = utc()

suite "list criteria: --calendar":
  test "--calendar is a display option: it is not a criterion, and it goes with --show":
    let p = parseArgs(@["--calendar"], utc())
    check p.problem == "" and p.criteria.calendar
    let q = parseArgs(@["--show", "--calendar", "-v"], utc())
    check q.problem == "" and q.criteria.show and q.criteria.calendar and q.criteria.verbose
    check parseArgs(@["--sport", "cycling", "--calendar"], utc()).criteria.calendar
    check not parseArgs(@[], utc()).criteria.calendar

suite "list: times":
  test "a date is a day in the given zone; as an end it is the day after":
    check parseWhen("2018-08-27", utcZone, false) == some(UnixTime(1535328000))
    check parseWhen("2018-08-27", utcZone, true) == some(UnixTime(1535414400))
  test "minutes and seconds, with T or a space":
    check parseWhen("2018-08-27T10:30", utcZone, false) == some(UnixTime(1535365800))
    check parseWhen("2018-08-27 10:30", utcZone, false) == some(UnixTime(1535365800))
    check parseWhen("2018-08-27T10:30", utcZone, true) == some(UnixTime(1535365860))     # the minute
    check parseWhen("2018-08-27T10:30:15", utcZone, true) == some(UnixTime(1535365816))  # the second
  test "the zone matters":
    let plus2 = newTimezone("+2", proc(t: Time): ZonedTime = ZonedTime(time: t, utcOffset: -7200, isDst: false),
                            proc(t: Time): ZonedTime = ZonedTime(time: t - initDuration(seconds = 7200), utcOffset: -7200, isDst: false))
    check parseWhen("2018-08-27", plus2, false) == some(UnixTime(1535328000 - 7200))
  test "rubbish":
    for bad in ["", "yesterday", "2018-13-45", "27/08/2018", "2018-08"]:
      check parseWhen(bad, utcZone, false).isNone

suite "list: positions":
  test "latitude, longitude":
    check parseLatLon("38.72,-9.14") == some((38.72, -9.14))
    check parseLatLon(" 38.72 , -9.14 ") == some((38.72, -9.14))
  test "out of range or not a pair":
    for bad in ["", "1", "1,2,3", "91,0", "0,181", "a,b"]:
      check parseLatLon(bad).isNone

suite "list: the command line":
  proc cmdline(args: varargs[string]): Parsed = parseArgs(@args, utcZone)

  test "--show and --save":
    check not cmdline().criteria.show and not cmdline().criteria.save
    check cmdline("--show").criteria.show
    check cmdline("--save").criteria.save
    check cmdline("--show").problem == ""
  test "users up to the next option, with commas too":
    check cmdline("--users", "a", "b,c", "--save").criteria.users == @["a", "b", "c"]
    check cmdline("--users").problem.contains("at least one")
    check cmdline("--users", "--save").problem.contains("at least one")
  test "the options":
    let c = cmdline("--save", "--newest", "3", "--from", "2018-08-01", "--to", "2018-08-31",
                  "--near", "38.7,-9.1", "--radius", "5").criteria
    check c.save and c.newest == 3 and c.oldest == 0
    check c.fromT.isSome and c.toT.isSome and c.fromT.get < c.toT.get
    check c.near == nkPoint and c.lat == 38.7 and c.lon == -9.1 and c.radiusKm == 5.0
    check cmdline("--near", "latest").criteria.near == nkLatest
  test "latest is the newest one; oldest; but not both":
    check cmdline("--latest").criteria.newest == 1
    check cmdline("--oldest", "2").criteria.oldest == 2
    check cmdline("--newest", "2", "--oldest", "2").problem.contains("together")
    for bad in ["0", "-1", "x", "1.5"]:
      check cmdline("--newest", bad).problem.contains("number of activities")
    check cmdline("--oldest").problem.contains("needs a value")
  test "--radius on its own means --near latest":
    let c = cmdline("--radius", "5").criteria
    check c.near == nkLatest and c.radiusKm == 5.0
    check cmdline("--radius", "5").problem == ""
  test "sports and sub-sports, lower-cased, several, repeated":
    let c = cmdline("--sport", "Cycling", "running,Swimming", "--sub-sport", "ROAD", "--sport", "walking").criteria
    check c.sports == @["cycling", "running", "swimming", "walking"]
    check c.subSports == @["road"]
    check cmdline("--sport").problem.contains("at least one name")
    check cmdline("--sub-sport", "--save").problem.contains("at least one name")
    check cmdline("--users", "Bob").criteria.users == @["Bob"]       # (names of users keep their case)
  test "-v is a display option, not a criterion; --file is gone":
    check cmdline("-v").criteria.verbose and cmdline("--verbose").criteria.verbose
    check cmdline("--show", "-v").problem == ""
    check cmdline("--show", "--verbose").criteria.show
    check cmdline("--file").problem.contains("unexpected")
  test "-n is --newest":
    check cmdline("-n", "3").criteria.newest == 3
    check cmdline("-n", "0").problem.contains("number of activities")
    check cmdline("-n").problem.contains("needs a value")
    check cmdline("-n", "2", "--oldest", "2").problem.contains("together")
  test "--distance and --active are ranges; a value that starts with a dash is a value":
    let c = cmdline("--distance", "-5", "--active", "1h30m-4h").criteria
    check c.distanceM == NumRange(hi: some 5000.0)
    check c.activeS == NumRange(lo: some 5400.0, hi: some 14400.0)
    check cmdline("--distance", "10-50").criteria.distanceM == NumRange(lo: some 10000.0, hi: some 50000.0)
    check cmdline("--distance", "0.5-").criteria.distanceM == NumRange(lo: some 500.0)
    check cmdline("--distance", "500m-").problem.contains("cannot read the distance range")   # (m is minutes)
    check cmdline("--show", "--distance", "5-").problem.contains("no criteria")
  test "--distance and --active around a value, or around latest":
    let c = cmdline("--distance", "42~2", "--active", "2h~15m").criteria
    check c.distanceM == NumRange(lo: some 40000.0, hi: some 44000.0)
    check c.activeS == NumRange(lo: some 6300.0, hi: some 8100.0)
    check not c.usesLatest
    let l = cmdline("--distance", "latest~10%", "--active", "latest~15m").criteria
    check l.distanceRel == some(Relative(refers: refLatest, tol: Tol(amount: 10.0, percent: true)))
    check l.activeRel == some(Relative(refers: refLatest, tol: Tol(amount: 900.0)))
    check l.distanceM.isOpen and l.activeS.isOpen        # (not known until latest is found)
    check l.usesLatest
  test "latest as a sport and a sub-sport":
    let c = cmdline("--sport", "latest", "--sub-sport", "Latest", "road").criteria
    check c.sportRef == refLatest and c.subSportRef == refLatest
    check c.sports.len == 0 and c.subSports == @["road"]
    check cmdline("--sport", "latest", "cycling").criteria.sports == @["cycling"]
  test "previous: in the same places, and kept apart from latest":
    let c = cmdline("--sport", "previous", "--sub-sport", "previous", "--distance", "previous~10%",
                    "--active", "Previous~15m", "--near", "previous").criteria
    check c.sportRef == refPrevious and c.subSportRef == refPrevious
    check c.distanceRel == some(Relative(refers: refPrevious, tol: Tol(amount: 10.0, percent: true)))
    check c.activeRel == some(Relative(refers: refPrevious, tol: Tol(amount: 900.0)))
    check c.near == nkPrevious
    check c.usesPrevious and not c.usesLatest
    let mixed = cmdline("--sport", "previous", "--distance", "latest~5").criteria
    check mixed.usesPrevious and mixed.usesLatest
    check cmdline("--sport", "latest", "previous").problem.contains("cannot be used together")
    check cmdline("--sub-sport", "previous", "latest").problem.contains("cannot be used together")
    check cmdline("--sport", "previous", "previous").problem == ""
    check cmdline("--near", "previous").criteria.near == nkPrevious
    check cmdline("--near", "nowhere").problem.contains("latest or previous")
    check cmdline("--radius", "5").criteria.near == nkLatest      # (alone: still latest)
  test "latest is found among the criteria that do not mention it, previous ones included":
    let c = cmdline("--sport", "previous", "--distance", "latest~5", "--near", "previous").criteria
    let base = c.withoutLatest
    check not base.usesLatest
    check base.usesPrevious                              # (resolved before, in the command)
    check base.near == nkPrevious and base.sportRef == refPrevious
  test "--near latest uses latest too, and the others that do not do not":
    check cmdline("--near", "latest").criteria.usesLatest
    check cmdline("--radius", "5").criteria.usesLatest
    check not cmdline("--near", "1,2").criteria.usesLatest
    check not cmdline("--sport", "cycling", "--distance", "5-", "-n", "1").criteria.usesLatest
  test "without latest: what latest is found among":
    let c = cmdline("--sport", "latest", "cycling", "--distance", "latest~5", "--active", "latest~5%",
                    "--near", "latest", "--sub-sport", "latest", "-n", "3", "--from", "2018-01-01",
                    "--distance", "latest~2").criteria
    let base = c.withoutLatest
    check not base.usesLatest
    check base.sports == @["cycling"]                 # (what was named stays)
    check base.fromT == c.fromT                        # (and the other criteria)
    check base.newest == 0 and base.oldest == 0       # (newest is applied afterwards)
  test "--distance and --active problems":
    check cmdline("--distance", "5").problem.contains("cannot read the distance range '5'")
    check cmdline("--distance", "1-2-3").problem.contains("cannot read")
    check cmdline("--distance", "50-10").problem.contains("backwards")
    check cmdline("--active", "90-").problem.contains("cannot read the active time range")
    check cmdline("--active", "2h-1h").problem.contains("backwards")
    check cmdline("--distance").problem.contains("needs a value")
    check cmdline("--distance", "latest~").problem.contains("cannot read the distance")
    check cmdline("--distance", "~5").problem.contains("cannot read the distance")
    check cmdline("--active", "latest~x").problem.contains("cannot read the active time")
    check cmdline("--active", "2h~15").problem.contains("cannot read the active time")
  test "the radius defaults to 100 km":
    check cmdline("--near", "1,2").criteria.radiusKm == 100.0
  test "--show takes no criteria, and cannot be saved":
    check cmdline("--show", "--newest", "1").problem.contains("no criteria")
    check cmdline("--show", "--users", "bob").problem.contains("no criteria")
    check cmdline("--newest", "1", "--show").problem.contains("no criteria")
    check cmdline("--show", "--save").problem.contains("cannot be combined")
    check cmdline("--show", "-h").problem == ""
  test "problems":
    check cmdline("--radius", "x", "--near", "1,2").problem.contains("radius")
    check cmdline("--radius", "0", "--near", "1,2").problem.contains("more than 0")
    check cmdline("--near", "nowhere").problem.contains("position")
    check cmdline("--from", "soon").problem.contains("cannot read the time")
    check cmdline("--from", "2018-09-01", "--to", "2018-08-01").problem.contains("not before")
    check cmdline("--from").problem.contains("needs a value")
    check cmdline("--bogus").problem.contains("unexpected")
    check cmdline("-h").help

suite "list: the box and the sql":
  test "a box holds the circle":
    let b = box(0.0, 10.0, 111.0)
    check b.minY < -0.9 and b.maxY > 0.9
    check b.minX < 9.0 and b.maxX > 11.0
  test "boxes: one, unless the circle goes over the date line":
    check boxes(38.7, -9.1, 50.0).len == 1
    let east = boxes(-17.0, 179.9, 50.0)               # Fiji: the circle crosses +180
    check east.len == 2
    check east[0].maxX == 180.0 and east[1].minX == -180.0 and east[1].maxX < -179.0
    let west = boxes(-17.0, -179.9, 50.0)              # ... and from the other side
    check west.len == 2
    check west[0].minX == -180.0 and west[1].maxX == 180.0 and west[1].minX > 179.0
    check boxes(89.5, 10.0, 100.0).len == 1            # (over a pole: all longitudes in one)
    check boxes(0.0, 179.0, 1.0).len == 1              # (a small circle that does not cross)
  test "near means starts near: the index of the start points, and the distance from the start":
    let m = matchSql(@[UserId(1)], Criteria(radiusKm: 5.0), some((38.7, -9.1)))
    check m.contains("f_table_name = 'activity'") and m.contains("f_geometry_column = 'start'")
    check m.contains("ST_Distance(a.start, MakePoint(-9.1000000, 38.7000000, 4326), 1) <= 5000.0000000")
    check not m.contains("route")
    let across = matchSql(@[UserId(1)], Criteria(radiusKm: 50.0), some((-17.0, 179.9)))
    check across.count("SpatialIndex") == 2 and across.contains(" or ")
  test "longitude widens away from the equator":
    check box(60.0, 0.0, 100.0).maxX > 1.5 * box(0.0, 0.0, 100.0).maxX
  test "over a pole: all longitudes":
    let b = box(89.5, 10.0, 100.0)
    check b.minX == -180.0 and b.maxX == 180.0 and b.maxY == 90.0
  test "--gps and --no-gps":
    check parseArgs(@["--gps"], utcZone).criteria.gps == gfWith
    check parseArgs(@["--no-gps"], utcZone).criteria.gps == gfWithout
    check parseArgs(@[], utcZone).criteria.gps == gfAny
    check parseArgs(@["--gps", "--gps"], utcZone).problem == ""
    check parseArgs(@["--gps", "--no-gps"], utcZone).problem.contains("cannot be used together")
    check parseArgs(@["--no-gps", "--gps"], utcZone).problem.contains("cannot be used together")
    check parseArgs(@["--show", "--gps"], utcZone).problem.contains("takes no criteria")
    let with = matchSql(@[UserId(1)], Criteria(gps: gfWith), none((float, float)))
    check with.contains(" and exists (select 1 from coords k where k.activity_id = a.id)")
    let without = matchSql(@[UserId(1)], Criteria(gps: gfWithout), none((float, float)))
    check without.contains(" and not exists (select 1 from coords k where k.activity_id = a.id)")
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).contains("coords")

  test "the sql has what was asked for, and nothing else":
    let plain = matchSql(@[UserId(1), UserId(2)], Criteria(), none((float, float)))
    check plain == "select a.id from activity a join file f on f.id = a.file_id where f.user_id in (1, 2)"
    check not plain.contains("start_t") and not plain.contains("route") and
          not plain.contains("limit")
    let full = matchSql(@[UserId(1)], Criteria(fromT: some(UnixTime(5)), toT: some(UnixTime(9)),
                        newest: 2, radiusKm: 5.0), some((38.7, -9.1)), "a.id, a.start_t")
    check full.startsWith("select a.id, a.start_t from activity a")
    check full.contains("a.start_t >= 5") and full.contains("a.start_t < 9")
    check full.contains("SpatialIndex") and full.contains("MakePoint(-9.1000000, 38.7000000, 4326)")
    check full.contains("<= 5000.0000000")
    check full.endsWith("order by a.start_t desc limit 2")
    check matchSql(@[UserId(1)], Criteria(oldest: 4), none((float, float))).endsWith(
      "order by a.start_t asc limit 4")
  test "sports are quoted, none means NULL, nothing without values":
    check inValues("a.sport", @[]) == ""
    check inValues("a.sport", @["cycling", "running"]) == " and (a.sport in ('cycling', 'running'))"
    check inValues("a.sub_sport", @["none"]) == " and (a.sub_sport is null)"
    check inValues("a.sub_sport", @["road", "none"]) ==
      " and (a.sub_sport in ('road') or a.sub_sport is null)"
    check inValues("a.sport", @["x'; drop table user; --"]) ==
      " and (a.sport in ('x''; drop table user; --'))"
    let m = matchSql(@[UserId(1)], Criteria(sports: @["cycling"], subSports: @["none"]), none((float, float)))
    check m.contains("a.sport in ('cycling')") and m.contains("a.sub_sport is null")
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).contains("sport")
  test "ranges become inclusive comparisons, only for the ends given":
    check rangeSql("a.distance_m", NumRange()) == ""
    check rangeSql("a.distance_m", NumRange(lo: some 40000.0)) == " and a.distance_m >= 40000.000"
    check rangeSql("a.timer_s", NumRange(hi: some 3600.0)) == " and a.timer_s <= 3600.000"
    check rangeSql("a.timer_s", NumRange(lo: some 60.0, hi: some 120.5)) ==
      " and a.timer_s >= 60.000 and a.timer_s <= 120.500"
    let m = matchSql(@[UserId(1)], Criteria(distanceM: NumRange(lo: some 1000.0),
                     activeS: NumRange(hi: some 60.0)), none((float, float)))
    check m.contains("a.distance_m >= 1000.000") and m.contains("a.timer_s <= 60.000")
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).contains("distance_m")
  test "saving wraps the same query":
    let m = matchSql(@[UserId(3)], Criteria(newest: 1), none((float, float)), "a.id as id")
    check saveSql(UserId(7), m) == "insert into selection(user_id, activity_id) select 7, id from (" & m & ")"

suite "list: --name and --start":
  proc parsed(args: varargs[string]): Criteria = parseArgs(@args, utcZone).criteria
  test "the words are alternatives; commas too; a name with spaces is one":
    let c = parsed("--name", "toyo", "farellones", "--start", "providencia,ñuñoa")
    check c.names == @["toyo", "farellones"] and c.starts == @["providencia", "ñuñoa"]
    check parsed("--name", "el toyo").names == @["el toyo"]
  test "latest and previous are references, not text; they cannot be mixed":
    let c = parsed("--name", "latest", "--start", "previous")
    check c.nameRef == refLatest and c.startRef == refPrevious and c.names.len == 0 and c.starts.len == 0
    check c.usesLatest and c.usesPrevious
    check not c.withoutLatest.usesLatest
    check parseArgs(@["--name", "latest", "previous"], utcZone).problem.contains("cannot be used together")
  test "a name needs some text; it is a criterion (not allowed with --show)":
    check parseArgs(@["--name"], utcZone).problem.len > 0
    check parseArgs(@["--show", "--name", "toyo"], utcZone).problem.contains("takes no criteria")
  test "the sql: a glob of the folded text, none for nothing, an exact value for what latest came to":
    let c = parsed("--name", "toyo", "none", "--start", "o'higgins")
    let q = matchSql(@[UserId(1)], c, none((float, float)))
    check q.contains("a.name glob '*[tT") and q.contains("(a.name is null or a.name = '')")
    check q.contains("a.start_place glob '*") and q.contains("''")          # (the quote is doubled)
    var e = Criteria()
    e.namesExact = @["El Toyo and back", ""]
    e.startsExact = @["Providencia"]
    let r = matchSql(@[UserId(1)], e, none((float, float)))
    check r.contains("a.name = 'El Toyo and back'") and r.contains("(a.name is null or a.name = '')")
    check r.contains("a.start_place = 'Providencia'")
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).contains("glob")
