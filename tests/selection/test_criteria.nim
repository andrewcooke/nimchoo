import std/[options, strutils, times, unittest]
import nimchoo/selection/criteria

let utcZone = utc()

suite "list: times":
  test "a date is a day in the given zone; as an end it is the day after":
    check parseWhen("2018-08-27", utcZone, false) == some(1535328000'i64)
    check parseWhen("2018-08-27", utcZone, true) == some(1535414400'i64)
  test "minutes and seconds, with T or a space":
    check parseWhen("2018-08-27T10:30", utcZone, false) == some(1535365800'i64)
    check parseWhen("2018-08-27 10:30", utcZone, false) == some(1535365800'i64)
    check parseWhen("2018-08-27T10:30", utcZone, true) == some(1535365860'i64)     # the minute
    check parseWhen("2018-08-27T10:30:15", utcZone, true) == some(1535365816'i64)  # the second
  test "the zone matters":
    let plus2 = newTimezone("+2", proc(t: Time): ZonedTime = ZonedTime(time: t, utcOffset: -7200, isDst: false),
                            proc(t: Time): ZonedTime = ZonedTime(time: t - initDuration(seconds = 7200), utcOffset: -7200, isDst: false))
    check parseWhen("2018-08-27", plus2, false) == some(1535328000'i64 - 7200)
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
  test "--file is a display option, not a criterion":
    check cmdline("--file").criteria.files
    check cmdline("--show", "--file").problem == ""
    check cmdline("--show", "--file").criteria.show
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
  test "longitude widens away from the equator":
    check box(60.0, 0.0, 100.0).maxX > 1.5 * box(0.0, 0.0, 100.0).maxX
  test "over a pole: all longitudes":
    let b = box(89.5, 10.0, 100.0)
    check b.minX == -180.0 and b.maxX == 180.0 and b.maxY == 90.0
  test "the sql has what was asked for, and nothing else":
    let plain = matchSql(@[1'i64, 2], Criteria(), none((float, float)))
    check plain == "select a.id from activity a join file f on f.id = a.file_id where f.user_id in (1, 2)"
    check not plain.contains("start_t") and not plain.contains("route") and
          not plain.contains("limit")
    let full = matchSql(@[1'i64], Criteria(fromT: some(5'i64), toT: some(9'i64),
                        newest: 2, radiusKm: 5.0), some((38.7, -9.1)), "a.id, a.start_t")
    check full.startsWith("select a.id, a.start_t from activity a")
    check full.contains("a.start_t >= 5") and full.contains("a.start_t < 9")
    check full.contains("SpatialIndex") and full.contains("MakePoint(-9.1000000, 38.7000000, 4326)")
    check full.contains("<= 5000.0000000")
    check full.endsWith("order by a.start_t desc limit 2")
    check matchSql(@[1'i64], Criteria(oldest: 4), none((float, float))).endsWith(
      "order by a.start_t asc limit 4")
  test "sports are quoted, none means NULL, nothing without values":
    check inValues("a.sport", @[]) == ""
    check inValues("a.sport", @["cycling", "running"]) == " and (a.sport in ('cycling', 'running'))"
    check inValues("a.sub_sport", @["none"]) == " and (a.sub_sport is null)"
    check inValues("a.sub_sport", @["road", "none"]) ==
      " and (a.sub_sport in ('road') or a.sub_sport is null)"
    check inValues("a.sport", @["x'; drop table user; --"]) ==
      " and (a.sport in ('x''; drop table user; --'))"
    let m = matchSql(@[1'i64], Criteria(sports: @["cycling"], subSports: @["none"]), none((float, float)))
    check m.contains("a.sport in ('cycling')") and m.contains("a.sub_sport is null")
    check not matchSql(@[1'i64], Criteria(), none((float, float))).contains("sport")
  test "saving wraps the same query":
    let m = matchSql(@[3'i64], Criteria(newest: 1), none((float, float)), "a.id as id")
    check saveSql(7, m) == "insert into selection(user_id, activity_id) select 7, id from (" & m & ")"
