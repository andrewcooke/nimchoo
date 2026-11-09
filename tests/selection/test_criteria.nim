import nimchoo/db/sqltext
import std/[options, strutils, times, unittest]
import nimchoo/fit/time
import nimchoo/ids
import nimchoo/selection/criteria

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

suite "list criteria: --calendar":
  test "--calendar is a display option: it is not a criterion, and it goes with -v":
    let p = parseArgs(@["--calendar"], utc())
    check p.problem == "" and p.criteria.calendar
    let q = parseArgs(@["--calendar", "-v"], utc())
    check q.problem == "" and not q.criteria.given and q.criteria.calendar and
      q.criteria.verbose
    check parseArgs(@["--sport", "cycling", "--calendar"], utc()).criteria.calendar
    check not parseArgs(@[], utc()).criteria.calendar

suite "list: times":
  test "a date is a day in the given zone; as an end it is the day after":
    check parseWhen("2018-08-27", utcZone, false) == some(UnixTime(1535328000))
    check parseWhen("2018-08-27", utcZone, true) == some(UnixTime(1535414400))
  test "minutes and seconds, with T or a space":
    check parseWhen("2018-08-27T10:30", utcZone, false) == some(UnixTime(1535365800))
    check parseWhen("2018-08-27 10:30", utcZone, false) == some(UnixTime(1535365800))
    check parseWhen("2018-08-27T10:30", utcZone, true) == some(UnixTime(1535365860))
      # the minute
    check parseWhen("2018-08-27T10:30:15", utcZone, true) == some(UnixTime(1535365816))
      # the second
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
  proc cmdline(args: varargs[string]): Parsed =
    parseArgs(@args, utcZone)

  test "--select and --all":
    check not cmdline().criteria.select and not cmdline().criteria.all and
      not cmdline().criteria.given
    check cmdline("--all", "--select").criteria.select and cmdline("--all").criteria.all
    check cmdline("--sport", "cycling", "--select").criteria.select and
      cmdline("--sport", "cycling").criteria.given
    check cmdline("--select").problem.contains("needs criteria or --all")
    check cmdline("--newest", "1").criteria.given # (a limit searches all, too)

  test "the options":
    let c = cmdline(
      "--select", "--newest", "3", "--from", "2018-08-01", "--to", "2018-08-31",
      "--near", "38.7,-9.1", "--radius", "5",
    ).criteria
    check c.select and c.newest == 3 and c.oldest == 0
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
    let c = cmdline(
      "--sport", "Cycling", "running,Swimming", "--sub-sport", "ROAD", "--sport",
      "walking",
    ).criteria
    check c.sports == @["cycling", "running", "swimming", "walking"]
    check c.subSports == @["road"]
    check cmdline("--sport").problem.contains("at least one name")
    check cmdline("--sub-sport", "--select").problem.contains("at least one name")
  test "-v is a display option, not a criterion; --file is gone":
    check cmdline("-v").criteria.verbose and cmdline("--verbose").criteria.verbose
    check cmdline("-v").problem == ""
    check cmdline("--verbose").criteria.verbose
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
    check cmdline("--distance", "10-50").criteria.distanceM ==
      NumRange(lo: some 10000.0, hi: some 50000.0)
    check cmdline("--distance", "0.5-").criteria.distanceM == NumRange(lo: some 500.0)
    check cmdline("--distance", "500m-").problem.contains(
      "cannot read the distance range"
    ) # (m is minutes)
  test "--distance and --active around a value, or around latest":
    let c = cmdline("--distance", "42~2", "--active", "2h~15m").criteria
    check c.distanceM == NumRange(lo: some 40000.0, hi: some 44000.0)
    check c.activeS == NumRange(lo: some 6300.0, hi: some 8100.0)
    check not c.usesLatest
    let l = cmdline("--distance", "latest~10%", "--active", "latest~15m").criteria
    check l.distanceRel ==
      some(Relative(refers: refLatest, tol: Tol(amount: 10.0, percent: true)))
    check l.activeRel == some(Relative(refers: refLatest, tol: Tol(amount: 900.0)))
    check l.distanceM.isOpen and l.activeS.isOpen # (not known until latest is found)
    check l.usesLatest
  test "latest as a sport and a sub-sport":
    let c = cmdline("--sport", "latest", "--sub-sport", "Latest", "road").criteria
    check c.sportRef == refLatest and c.subSportRef == refLatest
    check c.sports.len == 0 and c.subSports == @["road"]
    check cmdline("--sport", "latest", "cycling").criteria.sports == @["cycling"]
  test "previous: in the same places, and kept apart from latest":
    let c = cmdline(
      "--sport", "previous", "--sub-sport", "previous", "--distance", "previous~10%",
      "--active", "Previous~15m", "--near", "previous",
    ).criteria
    check c.sportRef == refPrevious and c.subSportRef == refPrevious
    check c.distanceRel ==
      some(Relative(refers: refPrevious, tol: Tol(amount: 10.0, percent: true)))
    check c.activeRel == some(Relative(refers: refPrevious, tol: Tol(amount: 900.0)))
    check c.near == nkPrevious
    check c.usesPrevious and not c.usesLatest
    let mixed = cmdline("--sport", "previous", "--distance", "latest~5").criteria
    check mixed.usesPrevious and mixed.usesLatest
    check cmdline("--sport", "latest", "previous").problem.contains(
      "cannot be used together"
    )
    check cmdline("--sub-sport", "previous", "latest").problem.contains(
      "cannot be used together"
    )
    check cmdline("--sport", "previous", "previous").problem == ""
    check cmdline("--near", "previous").criteria.near == nkPrevious
    check cmdline("--near", "nowhere").problem.contains("latest or previous")
    check cmdline("--radius", "5").criteria.near == nkLatest # (alone: still latest)
  test "latest is found among the criteria that do not mention it, previous ones included":
    let c = cmdline(
      "--sport", "previous", "--distance", "latest~5", "--near", "previous"
    ).criteria
    let base = c.withoutLatest
    check not base.usesLatest
    check base.usesPrevious # (resolved before, in the command)
    check base.near == nkPrevious and base.sportRef == refPrevious
  test "--near latest uses latest too, and the others that do not do not":
    check cmdline("--near", "latest").criteria.usesLatest
    check cmdline("--radius", "5").criteria.usesLatest
    check not cmdline("--near", "1,2").criteria.usesLatest
    check not cmdline("--sport", "cycling", "--distance", "5-", "-n", "1").criteria.usesLatest
  test "without latest: what latest is found among":
    let c = cmdline(
      "--sport", "latest", "cycling", "--distance", "latest~5", "--active", "latest~5%",
      "--near", "latest", "--sub-sport", "latest", "-n", "3", "--from", "2018-01-01",
      "--distance", "latest~2",
    ).criteria
    let base = c.withoutLatest
    check not base.usesLatest
    check base.sports == @["cycling"] # (what was named stays)
    check base.fromT == c.fromT # (and the other criteria)
    check base.newest == 0 and base.oldest == 0 # (newest is applied afterwards)
  test "--distance and --active problems":
    check cmdline("--distance", "5").problem.contains(
      "cannot read the distance range '5'"
    )
    check cmdline("--distance", "1-2-3").problem.contains("cannot read")
    check cmdline("--distance", "50-10").problem.contains("backwards")
    check cmdline("--active", "90-").problem.contains(
      "cannot read the active time range"
    )
    check cmdline("--active", "2h-1h").problem.contains("backwards")
    check cmdline("--distance").problem.contains("needs a value")
    check cmdline("--distance", "latest~").problem.contains("cannot read the distance")
    check cmdline("--distance", "~5").problem.contains("cannot read the distance")
    check cmdline("--active", "latest~x").problem.contains(
      "cannot read the active time"
    )
    check cmdline("--active", "2h~15").problem.contains("cannot read the active time")
  test "the radius defaults to 100 km":
    check cmdline("--near", "1,2").criteria.radiusKm == 100.0
  test "--all is every activity: it does not go with criteria, but with the limits":
    check cmdline("--all", "--sport", "cycling").problem.contains(
      "does not go with criteria"
    )
    check cmdline("--all", "--newest", "1").problem == ""
    check cmdline("--all", "--select").problem == ""
    check cmdline("--all", "-h").problem == ""
    check cmdline("--all", "--invert").problem.contains("needs a criterion")

  test "problems":
    check cmdline("--radius", "x", "--near", "1,2").problem.contains("radius")
    check cmdline("--radius", "0", "--near", "1,2").problem.contains("more than 0")
    check cmdline("--near", "nowhere").problem.contains("position")
    check cmdline("--from", "soon").problem.contains("cannot read the time")
    check cmdline("--from", "2018-09-01", "--to", "2018-08-01").problem.contains(
      "not before"
    )
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
    let east = boxes(-17.0, 179.9, 50.0) # Fiji: the circle crosses +180
    check east.len == 2
    check east[0].maxX == 180.0 and east[1].minX == -180.0 and east[1].maxX < -179.0
    let west = boxes(-17.0, -179.9, 50.0) # ... and from the other side
    check west.len == 2
    check west[0].minX == -180.0 and west[1].maxX == 180.0 and west[1].minX > 179.0
    check boxes(89.5, 10.0, 100.0).len == 1 # (over a pole: all longitudes in one)
    check boxes(0.0, 179.0, 1.0).len == 1 # (a small circle that does not cross)
  test "near means starts near: the index of the start points, and the distance from the start":
    let q = matchSql(@[UserId(1)], Criteria(radiusKm: 5.0), some((38.7, -9.1)))
    let m = q.text
    check m.contains("f_table_name = 'activity'") and
      m.contains("f_geometry_column = 'start'")
    check m.contains(
      "ST_Distance(a.start, MakePoint(:nearLon, :nearLat, 4326), 1) <= :nearM"
    )
    check q.value("nearLon") == arg(-9.1) and q.value("nearLat") == arg(38.7) and
      q.value("nearM") == arg(5000.0)
    check not m.contains("route")
    let across = matchSql(@[UserId(1)], Criteria(radiusKm: 50.0), some((-17.0, 179.9)))
    check across.text.count("SpatialIndex") == 2 and across.text.contains(" or ")
    check across.has("box0West") and across.has("box1North")
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
    check parseArgs(@["--gps", "--no-gps"], utcZone).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--no-gps", "--gps"], utcZone).problem.contains(
      "cannot be used together"
    )
    let with = matchSql(@[UserId(1)], Criteria(gps: gfWith), none((float, float))).text
    check with.contains(
      " and exists (select 1 from coords k where k.activity_id = a.id)"
    )
    let without =
      matchSql(@[UserId(1)], Criteria(gps: gfWithout), none((float, float))).text
    check without.contains(
      " and not exists (select 1 from coords k where k.activity_id = a.id)"
    )
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).text.contains(
      "coords"
    )

  test "the sql has what was asked for, and nothing else":
    let q = matchSql(@[UserId(1), UserId(2)], Criteria(), none((float, float)))
    let plain = q.text
    check plain ==
      "select a.id from activity a join file f on f.id = a.file_id where f.user_id in (select value from json_each(:users))"
    check q.args.len == 1 and q.value("users") == arg("[1,2]")
    check not plain.contains("start_t") and not plain.contains("route") and
      not plain.contains("limit")
    let fullQ = matchSql(
      @[UserId(1)],
      Criteria(
        fromT: some(UnixTime(5)), toT: some(UnixTime(9)), newest: 2, radiusKm: 5.0
      ),
      some((38.7, -9.1)),
      sqlOf("a.id, a.start_t"),
    )
    let full = fullQ.text
    check full.startsWith("select a.id, a.start_t from activity a")
    check full.contains("a.start_t >= :fromT") and full.contains("a.start_t < :toT")
    check fullQ.value("fromT") == arg(5) and fullQ.value("toT") == arg(9)
    check full.contains("SpatialIndex") and
      full.contains("MakePoint(:nearLon, :nearLat, 4326)")
    check fullQ.value("nearM") == arg(5000.0)
    check full.endsWith("order by a.start_t desc limit :newest")
    check fullQ.value("newest") == arg(2)
    let oldest = matchSql(@[UserId(1)], Criteria(oldest: 4), none((float, float)))
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
      @[UserId(1)],
      Criteria(sports: @["cycling"], subSports: @["none"]),
      none((float, float)),
    )
    check m.text.contains("a.sport in (:sport0)") and
      m.text.contains("a.sub_sport is null")
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).text.contains(
      "sport"
    )
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
      @[UserId(1)],
      Criteria(distanceM: NumRange(lo: some 1000.0), activeS: NumRange(hi: some 60.0)),
      none((float, float)),
    )
    check m.text.contains("a.distance_m >= :distanceLo") and
      m.text.contains("a.timer_s <= :activeHi")
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).text.contains(
      "distance_m"
    )
  test "saving wraps the same query":
    let m = matchSql(
      @[UserId(3)], Criteria(newest: 1), none((float, float)), sqlOf("a.id as id")
    )
    let saved = saveSql(UserId(7), m)
    check saved.text ==
      "insert into selection(user_id, activity_id) select :owner, id from (" & m.text &
      ")"
    check saved.value("owner") == arg(7) and saved.value("users") == arg("[3]")

suite "list: --name and --start":
  proc parsed(args: varargs[string]): Criteria =
    parseArgs(@args, utcZone).criteria

  test "the words are alternatives; commas too; a name with spaces is one":
    let c = parsed("--name", "toyo", "farellones", "--start", "providencia,ñuñoa")
    check c.names == @["toyo", "farellones"] and c.starts == @["providencia", "ñuñoa"]
    check parsed("--name", "el toyo").names == @["el toyo"]
  test "latest and previous are references, not text; they cannot be mixed":
    let c = parsed("--name", "latest", "--start", "previous")
    check c.nameRef == refLatest and c.startRef == refPrevious and c.names.len == 0 and
      c.starts.len == 0
    check c.usesLatest and c.usesPrevious
    check not c.withoutLatest.usesLatest
    check parseArgs(@["--name", "latest", "previous"], utcZone).problem.contains(
      "cannot be used together"
    )
  test "a name needs some text; it is a criterion ":
    check parseArgs(@["--name"], utcZone).problem.len > 0
  test "the sql: the folded text found in the column, none for nothing, an exact value for what latest came to":
    let c = parsed("--name", "toyo", "none", "--start", "o'higgins")
    let m = matchSql(@[UserId(1)], c, none((float, float)))
    let q = m.text
    check q.contains("instr(fold(a.name), :nameT0) > 0") and
      q.contains("(a.name is null or a.name = '')")
    check m.value("nameT0") == arg("toyo") # (folded)
    check q.contains("instr(fold(a.start_place), :startT0) > 0")
    check m.value("startT0") == arg("o'higgins") # (bound as it is: no quotes to double)
    var e = Criteria()
    e.namesExact = @["El Toyo and back", ""]
    e.startsExact = @["Providencia"]
    let rq = matchSql(@[UserId(1)], e, none((float, float)))
    let r = rq.text
    check r.contains("a.name = :nameE0") and
      r.contains("(a.name is null or a.name = '')")
    check rq.value("nameE0") == arg("El Toyo and back")
    check r.contains("a.start_place = :startE0") and
      rq.value("startE0") == arg("Providencia")
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).text.contains(
      "fold("
    )

suite "list: --path":
  test "the words are alternatives; the sql looks in the file's name and in every path it was seen at":
    let c = parseArgs(@["--path", "bowman,run", "2026-10"], utcZone).criteria
    check c.paths == @["bowman", "run", "2026-10"]
    let m = matchSql(@[UserId(1)], c, none((float, float)))
    let q = m.text
    check q.contains("instr(fold(f.name), :path0) > 0") and
      q.contains(
        "from seen_file s where s.file_id = f.id and instr(fold(s.path), :path0) > 0"
      )
    check m.value("path0") == arg("bowman") and m.has("path2")
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).text.contains(
      "seen_file"
    )
  test "latest is just text here; a path needs some text and is a criterion":
    check parseArgs(@["--path", "latest"], utcZone).criteria.paths == @["latest"]
    check parseArgs(@["--path"], utcZone).problem.len > 0

suite "list: --invert":
  test "it is a criterion on its own, and needs something to invert":
    check parseArgs(@["--sport", "cycling", "--invert"], utcZone).criteria.invert
    check parseArgs(@["--invert"], utcZone).problem.contains("needs a criterion")
    check parseArgs(@["--invert", "--newest", "2"], utcZone).problem.contains(
      "needs a criterion"
    ) # (limits are not criteria)
    check parseArgs(@["--invert", "--gps"], utcZone).problem == ""
    check parseArgs(@["--invert", "--distance", "40-"], utcZone).problem == ""
    check parseArgs(@["--invert", "--name", "latest"], utcZone).problem == ""
  test "the sql negates all of the criteria together, treating an unknown as no match":
    let c =
      parseArgs(@["--sport", "cycling", "--name", "toyo", "--invert"], utcZone).criteria
    let q = matchSql(@[UserId(1)], c, none((float, float))).text
    check q.contains(
      " and not coalesce((1 and (a.sport in (:sport0)) and (instr(fold(a.name), :nameT0) > 0"
    )
    check q.endsWith("), 0)")
    let plain = matchSql(
      @[UserId(1)],
      parseArgs(@["--sport", "cycling"], utcZone).criteria,
      none((float, float)),
    )
    check not plain.text.contains("coalesce")
  test "the limits come after the inverting, and latest is found before it":
    let c =
      parseArgs(@["--sport", "cycling", "--invert", "--newest", "2"], utcZone).criteria
    check matchSql(@[UserId(1)], c, none((float, float))).text.endsWith(
      " order by a.start_t desc limit :newest"
    )
    let r = parseArgs(@["--distance", "latest~10%", "--invert"], utcZone).criteria
    check r.usesLatest and not r.withoutLatest.invert and not r.withoutLatest.usesLatest

suite "list: --climb":
  test "the words are alternatives; the sql asks for an effort on the climbs found":
    let c =
      parseArgs(@["--climb", "farellones,corral quemado", "(2/9)"], utcZone).criteria
    check c.climbs == @["farellones", "corral quemado", "(2/9)"]
    var r = c
    r.climbIds = @[3'i64, 7'i64]
    let q = matchSql(@[UserId(1)], r, none((float, float)))
    check q.text.contains(
      "exists (select 1 from effort e where e.activity_id = a.id and e.sector_id in (select value from json_each(:climbs)))"
    )
    check q.value("climbs") == arg("[3,7]")
    r.climbIds = @[]
    check matchSql(@[UserId(1)], r, none((float, float))).text.contains(" and 0")
      # no climb found: no activity
    check not matchSql(@[UserId(1)], Criteria(), none((float, float))).text.contains(
      "effort"
    )
  test "it is a criterion; it needs some text":
    check parseArgs(@["--climb"], utcZone).problem.len > 0
    check parseArgs(@["--invert", "--climb", "x"], utcZone).problem == ""

suite "list: --delete":
  test "--delete is an action, not a criterion; -f goes with it":
    let c = parseArgs(@["--delete", "-f"], utcZone).criteria
    check c.delete and c.force and not c.given and not c.all
    check parseArgs(@["--sport", "cycling", "--delete"], utcZone).criteria.given
    check parseArgs(@["--all", "--delete", "-f"], utcZone).problem == ""
    check parseArgs(@["-f"], utcZone).problem.contains("goes with --delete")
    check parseArgs(@["--delete", "--select"], utcZone).problem.contains(
      "shows nothing"
    )
    check parseArgs(@["--delete", "--calendar"], utcZone).problem.contains(
      "shows nothing"
    )
    check parseArgs(@["--delete", "-v"], utcZone).problem.contains("shows nothing")

suite "list: --import":
  test "several paths, and the options that go with it":
    let c =
      parseArgs(@["--import", "a", "b", "-q", "--slow", "-j", "3"], utcZone).criteria
    check c.importPaths == @["a", "b"] and c.quiet and c.slow and c.jobs == 3
  test "it needs a path":
    check parseArgs(@["--import"], utcZone).problem.contains("at least one path")
  test "it excludes the criteria, the other actions and the display options":
    for extra in [
      @["--sport", "cycling"],
      @["--all"],
      @["--select"],
      @["--delete"],
      @["-v"],
      @["--calendar"],
      @["--invert"],
    ]:
      check parseArgs(@["--import", "a"] & extra, utcZone).problem.len > 0
  test "-q, --slow and -j need --import":
    for o in [@["-q"], @["--slow"], @["-j", "2"]]:
      check parseArgs(o, utcZone).problem.len > 0
