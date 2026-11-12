import nimchoo/packages/db/sqltext
import nimchoo/core/extension
from nimchoo/registry import extensions
import nimchoo/core/errors
import nimchoo/packages/user/session
import std/[options, strutils, times, unittest]
import nimchoo/packages/fit/time
import nimchoo/core/ids
import nimchoo/packages/activities/criteria
import nimchoo/packages/confirm/confirm
import nimchoo/packages/activities/command as activitiesCommand
import nimchoo/packages/util/args/[args, usage]

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
  proc cmdline(args: varargs[string]): Parsed[Criteria] =
    parseArgs(@args, utcZone)

  test "--select and --all":
    check not cmdline().params.select and not cmdline().params.all and
      not cmdline().params.given
    check cmdline("--all", "--select").params.select and cmdline("--all").params.all
    check cmdline("--sports", "cycling", "--select").params.select and
      cmdline("--sports", "cycling").params.given
    check cmdline("--select").problem.contains("needs criteria or --all")
    check cmdline("--newest", "1").params.given # (a limit searches all, too)

  test "the options":
    let c = cmdline(
      "--select", "--newest", "3", "--from", "2018-08-01", "--to", "2018-08-31",
      "--near", "38.7,-9.1", "--radius", "5",
    ).params
    check c.select and c.newest == 3 and c.oldest == 0
    check c.fromT.isSome and c.toT.isSome and c.fromT.get < c.toT.get
    check c.near == nkPoint and c.lat == 38.7 and c.lon == -9.1 and c.radiusKm == 5.0
    check cmdline("--near", "latest").params.near == nkLatest
  test "latest is the newest one; oldest; but not both":
    check cmdline("--latest").params.newest == 1
    check cmdline("--oldest", "2").params.oldest == 2
    check cmdline("--newest", "2", "--oldest", "2").problem.contains("together")
    for bad in ["0", "-1", "x", "1.5"]:
      check cmdline("--newest", bad).problem.contains("number of activities")
    check cmdline("--oldest").problem.contains("needs a value")
  test "--radius on its own means --near latest":
    let c = cmdline("--radius", "5").params
    check c.near == nkLatest and c.radiusKm == 5.0
    check cmdline("--radius", "5").problem == ""
  test "sports and sub-sports, lower-cased, several, repeated":
    let c = cmdline(
      "--sports", "Cycling", "running", "Swimming", "--sub-sports", "ROAD", "--sports",
      "walking",
    ).params
    check c.sports == @["cycling", "running", "swimming", "walking"]
    check c.subSports == @["road"]
    check cmdline("--sports").problem.contains("at least one name")
    check cmdline("--sub-sports", "--select").problem.contains("at least one name")
  test "-v is a display option, not a criterion; --file is gone":
    check cmdline("-v").params.verbose and cmdline("--verbose").params.verbose
    check cmdline("-v").problem == ""
    check cmdline("--verbose").params.verbose
    check cmdline("--file").problem.contains("unexpected")
  test "-n is --newest":
    check cmdline("-n", "3").params.newest == 3
    check cmdline("-n", "0").problem.contains("number of activities")
    check cmdline("-n").problem.contains("needs a value")
    check cmdline("-n", "2", "--oldest", "2").problem.contains("together")
  test "--distance and --active are ranges; a value that starts with a dash is a value":
    let c = cmdline("--distance", "-5", "--active", "1h30m-4h").params
    check c.distanceM == NumRange(hi: some 5000.0)
    check c.activeS == NumRange(lo: some 5400.0, hi: some 14400.0)
    check cmdline("--distance", "10-50").params.distanceM ==
      NumRange(lo: some 10000.0, hi: some 50000.0)
    check cmdline("--distance", "0.5-").params.distanceM == NumRange(lo: some 500.0)
    check cmdline("--distance", "500m-").problem.contains(
      "cannot read the distance range"
    ) # (m is minutes)
  test "--distance and --active around a value, or around latest":
    let c = cmdline("--distance", "42~2", "--active", "2h~15m").params
    check c.distanceM == NumRange(lo: some 40000.0, hi: some 44000.0)
    check c.activeS == NumRange(lo: some 6300.0, hi: some 8100.0)
    check not c.usesLatest
    let l = cmdline("--distance", "latest~10%", "--active", "latest~15m").params
    check l.distanceRel ==
      some(Relative(refers: refLatest, tol: Tol(amount: 10.0, percent: true)))
    check l.activeRel == some(Relative(refers: refLatest, tol: Tol(amount: 900.0)))
    check l.distanceM.isOpen and l.activeS.isOpen # (not known until latest is found)
    check l.usesLatest
  test "latest as a sport and a sub-sport":
    let c = cmdline("--sports", "latest", "--sub-sports", "Latest", "road").params
    check c.sportRef == refLatest and c.subSportRef == refLatest
    check c.sports.len == 0 and c.subSports == @["road"]
    check cmdline("--sports", "latest", "cycling").params.sports == @["cycling"]
  test "previous: in the same places, and kept apart from latest":
    let c = cmdline(
      "--sports", "previous", "--sub-sports", "previous", "--distance", "previous~10%",
      "--active", "Previous~15m", "--near", "previous",
    ).params
    check c.sportRef == refPrevious and c.subSportRef == refPrevious
    check c.distanceRel ==
      some(Relative(refers: refPrevious, tol: Tol(amount: 10.0, percent: true)))
    check c.activeRel == some(Relative(refers: refPrevious, tol: Tol(amount: 900.0)))
    check c.near == nkPrevious
    check c.usesPrevious and not c.usesLatest
    let mixed = cmdline("--sports", "previous", "--distance", "latest~5").params
    check mixed.usesPrevious and mixed.usesLatest
    check cmdline("--sports", "latest", "previous").problem.contains(
      "cannot be used together"
    )
    check cmdline("--sub-sports", "previous", "latest").problem.contains(
      "cannot be used together"
    )
    check cmdline("--sports", "previous", "previous").problem == ""
    check cmdline("--near", "previous").params.near == nkPrevious
    check cmdline("--near", "nowhere").problem.contains("latest or previous")
    check cmdline("--radius", "5").params.near == nkLatest # (alone: still latest)
  test "latest is found among the criteria that do not mention it, previous ones included":
    let c = cmdline(
      "--sports", "previous", "--distance", "latest~5", "--near", "previous"
    ).params
    let base = c.withoutLatest
    check not base.usesLatest
    check base.usesPrevious # (resolved before, in the command)
    check base.near == nkPrevious and base.sportRef == refPrevious
  test "--near latest uses latest too, and the others that do not do not":
    check cmdline("--near", "latest").params.usesLatest
    check cmdline("--radius", "5").params.usesLatest
    check not cmdline("--near", "1,2").params.usesLatest
    check not cmdline("--sports", "cycling", "--distance", "5-", "-n", "1").params.usesLatest
  test "without latest: what latest is found among":
    let c = cmdline(
      "--sports", "latest", "cycling", "--distance", "latest~5", "--active",
      "latest~5%", "--near", "latest", "--sub-sports", "latest", "-n", "3", "--from",
      "2018-01-01", "--distance", "latest~2",
    ).params
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
    check cmdline("--near", "1,2").params.radiusKm == 100.0
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
    check parseArgs(@["--gps"], utcZone).params.gps == gfWith
    check parseArgs(@["--no-gps"], utcZone).params.gps == gfWithout
    check parseArgs(@[], utcZone).params.gps == gfAny
    check parseArgs(@["--gps", "--gps"], utcZone).problem == ""
    check parseArgs(@["--gps", "--no-gps"], utcZone).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--no-gps", "--gps"], utcZone).problem.contains(
      "cannot be used together"
    )
    let with = matchSql(@[UserId(1)], Criteria(gps: gfWith), none((float, float))).text
    check with.contains(
      " and exists (select 1 from track k where k.activity_id = a.id)"
    )
    let without =
      matchSql(@[UserId(1)], Criteria(gps: gfWithout), none((float, float))).text
    check without.contains(
      " and not exists (select 1 from track k where k.activity_id = a.id)"
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

suite "list: --names and --starts":
  proc parsed(args: varargs[string]): Criteria =
    parseArgs(@args, utcZone).params

  test "the words are alternatives; a name with spaces is one; a comma is part of a word":
    let c =
      parsed("--names", "toyo", "farellones", "--starts", "providencia", "ñuñoa")
    check parsed("--names", "a,b").names == @["a,b"]
    check c.names == @["toyo", "farellones"] and c.starts == @["providencia", "ñuñoa"]
    check parsed("--names", "el toyo").names == @["el toyo"]
  test "latest and previous are references, not text; they cannot be mixed":
    let c = parsed("--names", "latest", "--starts", "previous")
    check c.nameRef == refLatest and c.startRef == refPrevious and c.names.len == 0 and
      c.starts.len == 0
    check c.usesLatest and c.usesPrevious
    check not c.withoutLatest.usesLatest
    check parseArgs(@["--names", "latest", "previous"], utcZone).problem.contains(
      "cannot be used together"
    )
  test "a name needs some text; it is a criterion ":
    check parseArgs(@["--names"], utcZone).problem.len > 0
  test "the sql: the folded text found in the column, none for nothing, an exact value for what latest came to":
    let c = parsed("--names", "toyo", "none", "--starts", "o'higgins")
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

suite "list: --paths":
  test "the words are alternatives; the sql looks in the file's name and in every path it was seen at":
    let c = parseArgs(@["--paths", "bowman", "run", "2026-10"], utcZone).params
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
    check parseArgs(@["--paths", "latest"], utcZone).params.paths == @["latest"]
    check parseArgs(@["--paths"], utcZone).problem.len > 0

suite "list: --invert":
  test "it is a criterion on its own, and needs something to invert":
    check parseArgs(@["--sports", "cycling", "--invert"], utcZone).params.invert
    check parseArgs(@["--invert"], utcZone).problem.contains("needs a criterion")
    check parseArgs(@["--invert", "--newest", "2"], utcZone).problem.contains(
      "needs a criterion"
    ) # (limits are not criteria)
    check parseArgs(@["--invert", "--gps"], utcZone).problem == ""
    check parseArgs(@["--invert", "--distance", "40-"], utcZone).problem == ""
    check parseArgs(@["--invert", "--names", "latest"], utcZone).problem == ""
  test "the sql negates all of the criteria together, treating an unknown as no match":
    let c =
      parseArgs(@["--sports", "cycling", "--names", "toyo", "--invert"], utcZone).params
    let q = matchSql(@[UserId(1)], c, none((float, float))).text
    check q.contains(
      " and not coalesce((1 and (a.sport in (:sport0)) and (instr(fold(a.name), :nameT0) > 0"
    )
    check q.endsWith("), 0)")
    let plain = matchSql(
      @[UserId(1)],
      parseArgs(@["--sports", "cycling"], utcZone).params,
      none((float, float)),
    )
    check not plain.text.contains("coalesce")
  test "the limits come after the inverting, and latest is found before it":
    let c =
      parseArgs(@["--sports", "cycling", "--invert", "--newest", "2"], utcZone).params
    check matchSql(@[UserId(1)], c, none((float, float))).text.endsWith(
      " order by a.start_t desc limit :newest"
    )
    let r = parseArgs(@["--distance", "latest~10%", "--invert"], utcZone).params
    check r.usesLatest and not r.withoutLatest.invert and not r.withoutLatest.usesLatest

suite "list: criteria that other packages offer":
  func pick(st: Session, values: seq[string]): Resolution {.raises: [StoreError].} =
    Resolution(condition: sqlOf("a.id = 7"))

  let offered = Criterion(
    doc: OptDoc(
      names: @["--odd", "-o"],
      metavar: "WORD...",
      help: "an offered option",
      arity: aList,
    ),
    resolve: pick,
  )

  test "an offered option is parsed with the others, and kept as given for its package to resolve":
    let c = parseArgs(
      @["--odd", "a", "b", "-o", "c", "--sports", "cycling"], utcZone, @[offered]
    ).params
    check c.contributed.len == 1 and c.contributed[0].option == "--odd"
    check c.contributed[0].values == @["a", "b", "c"]
    check c.sports == @["cycling"]
  test "it is a criterion: it needs words, and it can be inverted":
    check parseArgs(@["--odd"], utcZone, @[offered]).problem.len > 0
    check parseArgs(@["--invert", "--odd", "x"], utcZone, @[offered]).problem == ""
    check parseArgs(@["--all", "--odd", "x"], utcZone, @[offered]).problem.len > 0
  test "without the package that offers it the option is unknown":
    check parseArgs(@["--odd", "x"], utcZone).problem.contains("unexpected option")
  test "it is in the usage":
    check "--odd, -o WORD..." in
      optionLines(criteriaSpec(@[offered]).docs, 100).join("\n")
  test "the conditions are joined by the command, with and":
    let c = Criteria()
    let q =
      matchSql(@[UserId(1)], c, none((float, float)), extra = sqlOf(" and (a.id = 7)"))
    check q.text.contains(" and (a.id = 7)")

suite "list: --delete":
  test "--delete is an action, not a criterion; -f goes with it":
    let c = parseArgs(@["--delete", "-f"], utcZone).params
    check c.delete and c.force == fYes and not c.given and not c.all
    check parseArgs(@["--delete", "-f", "-f"], utcZone).params.force == fNow
    check parseArgs(@["--sports", "cycling", "--delete"], utcZone).params.given
    check parseArgs(@["--all", "--delete", "-f"], utcZone).problem == ""
    check parseArgs(@["-f"], utcZone).problem.contains("goes with --delete")
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
      let text = activitiesCommand.usageText(width)
      for d in criteriaSpec().docs:
        for n in d.names:
          check n in text
  test "the whole usage fits the width, except the synopsis lines":
    for width in [60, 80, 120]:
      for l in activitiesCommand.usageText(width).splitLines:
        if not (l.startsWith("usage: ") or l.startsWith("       nch ")):
          check l.len <= width
  test "an option of another package would be listed and parsed from its description":
    let extra = OptDoc(
      names: @["--extra"],
      metavar: "WORDS...",
      help: "something offered by another package",
      arity: aList,
    )
    check "--extra WORDS..." in optionLines(criteriaSpec().docs & extra, 100).join("\n")

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
      activitiesCommand.usageText(100, extensions.get(activityCriterion))
