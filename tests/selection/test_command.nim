import std/[algorithm, os, strutils, times, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/modules
import nimchoo/selection/command as listCommand
import nimchoo/selection/criteria
import nimchoo/ui/[logfile, style, vocabulary]

let dir = getTempDir() / "nch-test-select"

const
  july1 = 1530446400      # 2018-07-01T12:00Z
  aug15 = 1534334400      # 2018-08-15T12:00Z
  aug27 = 1535371200      # 2018-08-27T12:00Z

proc addActivity(s: Store, userId: int64, tag: string, startT: int, wkt: string,
                 sport = "", subSport = "", lon = 0.0, lat = 0.0) =
  s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
            userId, tag, tag)
  let f = s.db.getValue(sql"select max(id) from file")
  s.db.exec(sql"""insert into activity(file_id, session, start_t, end_t, sport, sub_sport,
                                       distance_m, timer_s)
                  values (?, 0, ?, ?, nullif(?, ''), nullif(?, ''), 12345.0, 3661.0)""",
            f, startT, startT + 100, sport, subSport)
  let a = s.db.getValue(sql"select max(id) from activity")
  s.db.exec(sql("update activity set start = MakePoint(" & $lon & ", " & $lat & ", 4326) where id = " & a))
  s.db.exec(sql"insert into route(activity_id, geom) values (?, GeomFromText(?, 4326))", a, wkt)

proc world(name: string): string =
  ## A database with users default and bob; the activities (by tag):
  ## lisbon1 (default, July, cycling/road), paris (default, 27 Aug, the latest,
  ## running/trail), lisbon2 (bob, 15 Aug, cycling with no sub-sport).
  removeDir(dir / name)
  result = dir / name / "x.db"
  let s = openStore(result, allFragments)
  defer: s.close()
  s.db.exec(sql"insert into user(name) values ('bob')")
  let bob = parseBiggestInt(s.db.getValue(sql"select id from user where name = 'bob'"))
  addActivity(s, s.userId, "lisbon1", july1, "MULTILINESTRING((-9.14 38.72, -9.10 38.75))",
              "cycling", "road", -9.14, 38.72)
  addActivity(s, s.userId, "paris", aug27, "MULTILINESTRING((2.35 48.85, 2.40 48.90))",
              "running", "trail", 2.35, 48.85)
  addActivity(s, bob, "lisbon2", aug15, "MULTILINESTRING((-9.20 38.70, -9.15 38.74))",
              "cycling", "", -9.20, 38.70)

func texts(ls: seq[Line]): seq[string] =
  for l in ls: result.add l.text

proc list(db: string, args: varargs[string]): int =
  listCommand.run(Globals(dbPath: db, fragments: allFragments), @args)

proc save(db: string, args: varargs[string]): int =
  ## list, and keep the result as the selection
  list(db, @args & "--save")

proc chosen(db: string): seq[string] =
  ## The tags of the selected activities of the default user.
  let s = openStore(db, allFragments)
  defer: s.close()
  for row in s.db.fastRows(sql"""select f.name from selection l join activity a
      on a.id = l.activity_id join file f on f.id = a.file_id where l.user_id = ?""", s.userId):
    result.add row[0]
  result.sort

suite "list: the command":
  test "--show shows and changes nothing":
    let db = world("show")
    check list(db, "--show") == exitOk
    check chosen(db).len == 0
    discard save(db)
    check list(db, "--show") == exitOk
    check chosen(db) == @["lisbon1", "paris"]

  test "without --save nothing is stored":
    let db = world("nosave")
    check list(db) == exitOk                        # (everything of the user's, listed)
    check list(db, "--newest", "1") == exitOk
    check chosen(db).len == 0
    discard save(db, "--newest", "1")
    check chosen(db) == @["paris"]
    check list(db, "--oldest", "1") == exitOk       # listing again does not change it
    check chosen(db) == @["paris"]

  test "--show takes no criteria, and not --save":
    let db = world("showonly")
    discard save(db)
    check list(db, "--show", "--newest", "1") == exitUsage
    check list(db, "--show", "--from", "2018-01-01") == exitUsage
    check list(db, "--show", "--save") == exitUsage
    check chosen(db) == @["lisbon1", "paris"]

  test "saving a list with nothing in it empties the selection":
    let db = world("saveempty")
    discard save(db)
    check save(db, "--from", "2030-01-01") == exitOk
    check chosen(db).len == 0

  test "only the current user's activities, unless --users":
    let db = world("users")
    check save(db) == exitOk
    check chosen(db) == @["lisbon1", "paris"]
    check save(db, "--users", "default", "bob") == exitOk
    check chosen(db) == @["lisbon1", "lisbon2", "paris"]
    check save(db, "--users", "bob") == exitOk
    check chosen(db) == @["lisbon2"]

  test "each run replaces the selection":
    let db = world("replace")
    discard save(db)
    check chosen(db).len == 2
    discard save(db, "--latest")
    check chosen(db) == @["paris"]
    discard save(db, "--to", "2018-07-31")
    check chosen(db) == @["lisbon1"]

  test "the newest or oldest few, of those that meet the other criteria":
    let db = world("few")
    discard save(db, "--users", "default", "bob", "--newest", "2")
    check chosen(db) == @["lisbon2", "paris"]       # (of all three, by start time)
    discard save(db, "--users", "default", "bob", "--oldest", "1")
    check chosen(db) == @["lisbon1"]
    discard save(db, "--users", "default", "bob", "--from", "2018-08-01", "--oldest", "1")
    check chosen(db) == @["lisbon2"]                # (of bob's and paris: only after 1 Aug)
    discard save(db, "--users", "default", "bob", "--from", "2018-08-01", "--newest", "5")
    check chosen(db) == @["lisbon2", "paris"]

  test "by sport; several mean any of them; case does not matter":
    let db = world("sport")
    discard save(db, "--users", "default", "bob", "--sport", "cycling")
    check chosen(db) == @["lisbon1", "lisbon2"]
    discard save(db, "--users", "default", "bob", "--sport", "running")
    check chosen(db) == @["paris"]
    discard save(db, "--users", "default", "bob", "--sport", "Running,CYCLING")
    check chosen(db) == @["lisbon1", "lisbon2", "paris"]
    discard save(db, "--sport", "cycling")                    # (the current user only)
    check chosen(db) == @["lisbon1"]

  test "by sub-sport; none means not recorded":
    let db = world("subsport")
    discard save(db, "--users", "default", "bob", "--sub-sport", "road")
    check chosen(db) == @["lisbon1"]
    discard save(db, "--users", "default", "bob", "--sub-sport", "none")
    check chosen(db) == @["lisbon2"]
    discard save(db, "--users", "default", "bob", "--sub-sport", "none", "trail")
    check chosen(db) == @["lisbon2", "paris"]

  test "sport combined with the other criteria, and before --newest":
    let db = world("sportand")
    discard save(db, "--users", "default", "bob", "--sport", "cycling", "--newest", "1")
    check chosen(db) == @["lisbon2"]                  # (the newest cycling, not the newest)
    discard save(db, "--users", "default", "bob", "--sport", "cycling", "--sub-sport", "road")
    check chosen(db) == @["lisbon1"]
    discard save(db, "--users", "default", "bob", "--sport", "cycling", "--near", "38.73,-9.13", "--to", "2018-08-01")
    check chosen(db) == @["lisbon1"]

  test "a sport nobody has is refused, naming those there are":
    let db = world("nosport")
    discard save(db, "--sport", "cycling")
    check save(db, "--sport", "swimming") == exitFailure
    check save(db, "--sub-sport", "trail", "--users", "bob") == exitFailure
    check chosen(db) == @["lisbon1"]                 # (nothing changed)
    check list(db, "--sport", "cycling", "swimming") == exitFailure

  proc setNumbers(db, tag: string, distanceM, timerS: string) =
    ## Give the activity of the file `tag` its distance and timer time (NULL: "null").
    let st = openStore(db, allFragments)
    defer: st.close()
    st.db.exec(sql("update activity set distance_m = " & distanceM & ", timer_s = " & timerS &
      " where file_id = (select id from file where name = '" & tag & "')"))

  test "by distance, inclusive, and not recorded is never in":
    let db = world("distance")
    setNumbers(db, "lisbon1", "10000", "3600")
    setNumbers(db, "paris", "30000", "7200")
    setNumbers(db, "lisbon2", "null", "null")
    discard save(db, "--users", "default", "bob", "--distance", "20-")
    check chosen(db) == @["paris"]
    discard save(db, "--users", "default", "bob", "--distance", "-10")
    check chosen(db) == @["lisbon1"]                  # (10 km counts; the unrecorded does not)
    discard save(db, "--users", "default", "bob", "--distance", "10-30")
    check chosen(db) == @["lisbon1", "paris"]
    discard save(db, "--users", "default", "bob", "--distance", "10.001-29.999")
    check chosen(db).len == 0
    discard save(db, "--users", "default", "bob", "--distance", "0-")
    check chosen(db) == @["lisbon1", "paris"]         # (bob's has no distance at all)

  test "by active time":
    let db = world("active")
    setNumbers(db, "lisbon1", "10000", "3600")
    setNumbers(db, "paris", "30000", "7200")
    setNumbers(db, "lisbon2", "50000", "10800")
    discard save(db, "--users", "default", "bob", "--active", "2h-")
    check chosen(db) == @["lisbon2", "paris"]
    discard save(db, "--users", "default", "bob", "--active", "-1h")
    check chosen(db) == @["lisbon1"]
    discard save(db, "--users", "default", "bob", "--active", "1h01m-2h59m")
    check chosen(db) == @["paris"]

  test "ranges come before --newest, and combine with the other criteria":
    let db = world("rangeand")
    setNumbers(db, "lisbon1", "10000", "3600")
    setNumbers(db, "paris", "30000", "7200")
    setNumbers(db, "lisbon2", "50000", "10800")
    discard save(db, "--users", "default", "bob", "--distance", "40-", "-n", "1")
    check chosen(db) == @["lisbon2"]
    discard save(db, "--users", "default", "bob", "--distance", "5-", "--sport", "cycling", "--active", "-1h30m")
    check chosen(db) == @["lisbon1"]
    discard save(db, "--users", "default", "bob", "--distance", "5-", "-n", "2")
    check chosen(db) == @["lisbon2", "paris"]

  proc numbered(name: string): string =
    ## the world, with lisbon1 10 km / 1 h, paris 30 km / 2 h, lisbon2 50 km / 3 h
    result = world(name)
    setNumbers(result, "lisbon1", "10000", "3600")
    setNumbers(result, "paris", "30000", "7200")
    setNumbers(result, "lisbon2", "50000", "10800")

  test "latest is the newest of those that meet the other criteria":
    let db = numbered("latest1")
    # overall the newest is paris (running); among the cycling ones it is lisbon2 (bob's)
    discard save(db, "--users", "default", "bob", "--sport", "latest")
    check chosen(db) == @["paris"]
    discard save(db, "--users", "default", "bob", "--sport", "cycling", "--sub-sport", "latest")
    check chosen(db) == @["lisbon2"]                  # (no sub-sport recorded: "none")
    discard save(db, "--users", "default", "bob", "--sport", "cycling", "--distance", "latest~20%")
    check chosen(db) == @["lisbon2"]                  # 40-60 km
    discard save(db, "--users", "default", "bob", "--sport", "cycling", "--distance", "latest~90%")
    check chosen(db) == @["lisbon1", "lisbon2"]       # 5-95 km
    discard save(db, "--users", "default", "bob", "--distance", "latest~5")
    check chosen(db) == @["paris"]                    # the latest is paris: 25-35 km
    discard save(db, "--users", "default", "bob", "--active", "latest~1h30m")
    check chosen(db) == @["lisbon1", "lisbon2", "paris"]       # 30m-3h30m

  test "rides like the latest: sport, distance and time together":
    let db = numbered("latest2")
    discard save(db, "--users", "default", "bob", "--sport", "latest", "--distance", "latest~10%",
                 "--active", "latest~10%")
    check chosen(db) == @["paris"]
    discard save(db, "--users", "default", "bob", "--from", "2018-08-01", "--to", "2018-08-20",
                 "--sport", "latest", "--distance", "latest~10%")
    check chosen(db) == @["lisbon2"]                  # the latest in that month is bob's

  test "--near latest respects the other criteria":
    let db = numbered("latest3")
    discard save(db, "--sport", "cycling", "--near", "latest", "--radius", "5")
    check chosen(db) == @["lisbon1"]                  # (the latest cycling ride, not the latest ride)
    discard save(db, "--radius", "5")                 # alone: --near latest, of everything: paris
    check chosen(db) == @["paris"]

  test "previous is the one activity that was selected before":
    let db = numbered("previous1")
    discard save(db, "--users", "bob")                          # the one ride: lisbon2 (bob's)
    check chosen(db) == @["lisbon2"]
    discard save(db, "--users", "default", "bob", "--sport", "previous")
    check chosen(db) == @["lisbon1", "lisbon2"]                 # its sport: cycling
    discard save(db, "--users", "bob")
    discard save(db, "--users", "default", "bob", "--distance", "previous~20%")
    check chosen(db) == @["lisbon2"]                            # 40-60 km: itself
    discard save(db, "--users", "bob")
    discard save(db, "--users", "default", "bob", "--distance", "previous~90%", "--active", "previous~1h")
    check chosen(db) == @["lisbon2", "paris"]                   # 5-95 km, and 3h +- 1h = 2h-4h, inclusive: paris at 2h is in, lisbon1 at 1h is out

  test "previous is read before the selection is replaced":
    let db = numbered("previous2")
    discard save(db, "--users", "bob")
    check save(db, "--users", "default", "bob", "--sport", "previous", "--distance", "previous~90%") == exitOk
    check chosen(db) == @["lisbon1", "lisbon2"]                 # now two are selected
    check save(db, "--sport", "previous") == exitFailure        # so it cannot be run again
    check chosen(db) == @["lisbon1", "lisbon2"]                 # and nothing changed

  test "previous needs exactly one selected":
    let db = numbered("previous3")
    check list(db, "--sport", "previous") == exitFailure        # none
    discard save(db)
    check list(db, "--distance", "previous~10%") == exitFailure # two
    check list(db, "--near", "previous") == exitFailure
    check chosen(db) == @["lisbon1", "paris"]

  test "--near previous":
    let db = numbered("previous4")
    discard save(db, "--sport", "cycling")                      # the one ride: lisbon1
    discard save(db, "--users", "default", "bob", "--near", "previous", "--radius", "5")
    check chosen(db) == @["lisbon1"]                            # (bob's started 6.9 km away)
    discard save(db, "--sport", "cycling")
    discard save(db, "--users", "default", "bob", "--near", "previous", "--radius", "10")
    check chosen(db) == @["lisbon1", "lisbon2"]
    discard save(db, "--sport", "running")                      # paris
    check chosen(db) == @["paris"]
    let st = openStore(db, allFragments)
    st.db.exec(sql"update activity set start = null where file_id = (select id from file where name = 'lisbon2')")
    st.close()
    discard save(db, "--users", "bob")                          # lisbon2 has no start    check save(db, "--near", "previous") == exitFailure
    check chosen(db) == @["lisbon2"]

  test "previous with latest: previous first, then latest among what is left":
    let db = numbered("previous5")
    discard save(db, "--sport", "cycling")                      # the one ride: lisbon1 (cycling)
    # cycling rides of both users: the newest is lisbon2 (50 km); within 20% of that: 40-60
    discard save(db, "--users", "default", "bob", "--sport", "previous", "--distance", "latest~20%")
    check chosen(db) == @["lisbon2"]

  test "a reference that is another user's, or has no recorded numbers":
    let db = numbered("previous6")
    setNumbers(db, "lisbon2", "null", "null")
    discard save(db, "--users", "bob")
    check save(db, "--users", "default", "bob", "--distance", "previous~10%") == exitFailure
    check save(db, "--users", "default", "bob", "--active", "previous~10m") == exitFailure
    check save(db, "--users", "default", "bob", "--sport", "previous") == exitOk    # its sport is known
    check chosen(db) == @["lisbon1", "lisbon2"]

  test "the line says which one it used":
    let db = numbered("previous7")
    discard save(db, "--newest", "1")
    let st = openStore(db, allFragments)
    defer: st.close()
    let r = listActivities(st, parseArgs(@["--sport", "previous"], utc()).criteria, utc())
    check r.lines.texts[0].startsWith("previous: 2018-08-27 12:00 running")
  test "newest is not part of finding latest":
    let db = numbered("latest4")
    discard save(db, "--users", "default", "bob", "-n", "1", "--distance", "latest~10%")
    check chosen(db) == @["paris"]                    # latest is paris, whatever -n picks

  test "when latest cannot be found, it says so and changes nothing":
    let db = numbered("latest5")
    discard save(db)
    check save(db, "--sport", "cycling", "--from", "2030-01-01", "--distance", "latest~5") == exitFailure
    check chosen(db) == @["lisbon1", "paris"]
    setNumbers(db, "paris", "null", "null")
    check save(db, "--distance", "latest~5") == exitFailure     # paris is the latest and has no distance
    check save(db, "--active", "latest~5m") == exitFailure
    check chosen(db) == @["lisbon1", "paris"]
    check save(db, "--sport", "swimming", "--sport", "latest") == exitFailure   # nobody has it

  test "bad ranges are a usage error and change nothing":
    let db = world("badrange")
    discard save(db)
    check list(db, "--distance", "5") == exitUsage
    check list(db, "--active", "90-") == exitUsage
    check save(db, "--distance", "50-10") == exitUsage
    check chosen(db) == @["lisbon1", "paris"]

  test "dates":
    let db = world("dates")
    discard save(db, "--users", "default", "bob", "--from", "2018-08-01")
    check chosen(db) == @["lisbon2", "paris"]
    discard save(db, "--users", "default", "bob", "--from", "2018-08-01", "--to", "2018-08-20")
    check chosen(db) == @["lisbon2"]
    discard save(db, "--from", "2030-01-01")
    check chosen(db).len == 0

  test "near a point, 100 km unless told":
    let db = world("near")
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13")
    check chosen(db) == @["lisbon1", "lisbon2"]
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--radius", "10")
    check chosen(db) == @["lisbon1", "lisbon2"]
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--radius", "5")
    check chosen(db) == @["lisbon1"]          # (it started 1.4 km away; the other 6.9 km)
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--radius", "0.3")
    check chosen(db).len == 0                 # (nothing started within 300 m)
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--radius", "5000")
    check chosen(db) == @["lisbon1", "lisbon2", "paris"]

  test "near across the date line":
    let db = world("dateline")
    let st = openStore(db, allFragments)
    addActivity(st, st.userId, "fiji", aug27 + 100, "MULTILINESTRING((179.95 -17.0, 179.96 -17.0))", "cycling", "road", 179.95, -17.0)
    addActivity(st, st.userId, "samoa", aug27 + 200, "MULTILINESTRING((-172.0 -13.8, -171.9 -13.8))", "cycling", "road", -172.0, -13.8)
    st.close()
    discard save(db, "--near", "-17.0,-179.9", "--radius", "50")     # from the west side of the line
    check chosen(db) == @["fiji"]
    discard save(db, "--near", "-17.0,179.99", "--radius", "50")     # and from the east side
    check chosen(db) == @["fiji"]
    discard save(db, "--near", "-13.8,-172.0", "--radius", "5")
    check chosen(db) == @["samoa"]
    discard save(db, "--near", "-17.0,179.9", "--radius", "1")       # not near enough
    check chosen(db).len == 0

  test "a radius on its own is around the latest activity":
    let db = world("radius")
    discard save(db, "--users", "default", "bob", "--radius", "50")
    check chosen(db) == @["paris"]

  test "near the latest activity":
    let db = world("latest")
    discard save(db, "--users", "default", "bob", "--near", "latest", "--radius", "50")
    check chosen(db) == @["paris"]            # (the latest is in Paris)
    let st = openStore(db, allFragments)
    st.db.exec(sql"update activity set start = null where file_id = (select id from file where name = 'lisbon2')")
    st.close()
    check save(db, "--users", "bob", "--near", "latest") == exitFailure   # (bob's has no start
    check chosen(db) == @["paris"]                                          # to measure from;
                                                                            # nothing changed)

  test "criteria are combined":
    let db = world("and")
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--latest")
    check chosen(db) == @["lisbon2"]          # (the newest of those near Lisbon, not of all)
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--to", "2018-08-01")
    check chosen(db) == @["lisbon1"]

  test "a bad request changes nothing":
    let db = world("bad")
    discard save(db)
    check save(db, "--users", "nobody") == exitFailure
    check save(db, "--newest", "0") == exitUsage
    check save(db, "--from", "soon") == exitUsage
    check chosen(db) == @["lisbon1", "paris"]

  test "deleting an activity's owner takes it out of everyone's selection":
    let db = world("cascade")
    discard save(db, "--users", "default", "bob")
    check chosen(db).len == 3
    let s = openStore(db, allFragments)
    s.db.exec(sql"delete from user where name = 'bob'")
    s.close()
    check chosen(db) == @["lisbon1", "paris"]

suite "list: what is shown":
  proc shown(db: string, args: varargs[string]): tuple[lines: seq[Line], saved: int] =
    let st = openStore(db, allFragments)
    defer: st.close()
    let p = parseArgs(@args, utc())
    doAssert p.problem == "", p.problem
    listActivities(st, p.criteria, utc())


  test "a table of the activities, oldest first, with a last line":
    let db = world("shown")
    let r = shown(db)
    check r.saved == -1
    check r.lines.texts[0] == "date        start  sport            km  active"
    check r.lines.texts[1] == "2018-07-01  12:00  cycling/road   12.3   1h01m"
    check r.lines.texts[2] == "2018-08-27  12:00  running/trail  12.3   1h01m"
    check r.lines.texts[^1] == "2 of 2 activities, 24.7km, 2h02m (1 cycling, 1 running)"

  test "several users: a user column":
    let db = world("shownusers")
    let r = shown(db, "--users", "default", "bob")
    check r.lines.texts[0].startsWith("date        start  user")
    check r.lines.texts[^1].startsWith("3 of 3 activities")
    check r.lines.len == 5                           # header, three rows, the last line

  test "-v adds the path of the file, -n is --newest":
    let db = world("shownfile")
    let r = shown(db, "-v", "-n", "1")
    check r.lines.texts[0].endsWith("file")
    check r.lines.texts[1].endsWith("paris")

  test "saving says so, and --show shows what was saved":
    let db = world("shownsave")
    let r = shown(db, "--newest", "1", "--save")
    check r.saved == 1
    check r.lines.texts[^1] == "saved 1 activity as the selection"
    check r.lines[^1][0].look == look(leSaved)           # green, like the log event
    let st = openStore(db, allFragments)
    defer: st.close()
    let again = showSelection(st, Criteria(), utc())
    check again.texts[1].startsWith("2018-08-27  12:00  running/trail")
    check again.texts[^1].startsWith("1 activity,")        # (no "of": nothing was chosen from)

  test "an empty selection, and a list with nothing in it":
    let db = world("shownempty")
    let st = openStore(db, allFragments)
    defer: st.close()
    check showSelection(st, Criteria(), utc()).texts == @["selection: empty"]
    check shown(db, "--from", "2030-01-01").lines.texts == @["0 of 2 activities"]

  test "--near says where":
    let db = world("shownnear")
    let r = shown(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--radius", "10")
    check r.lines.texts[0] == "near 38.7300,-9.1300, within 10km"
    check r.lines.texts[^1].startsWith("2 of 3 activities")

  test "-v says where it started: the stored place, and how far if it is not close":
    let db = world("verbose-place")
    let st = openStore(db, allFragments)
    st.db.exec(sql"""update activity set place_id = (select id from place where name = 'Lisbon')
      where file_id in (select id from file where name in ('lisbon1', 'paris'))""")
    st.close()
    let rows = shown(db, "-v").lines.texts
    check rows[0].contains("place")
    check rows[1].contains("Lisbon, PT") and not rows[1].contains("Lisbon, PT (")     # lisbon1: 2 km away
    check rows[2].contains("Lisbon, PT (") and rows[2].contains("km)")                 # paris: a long way
    check not shown(db).lines.texts[0].contains("place")                               # (only with -v)

  test "no place known: its coordinates; no start: no GPS":
    let db = world("verbose-noplace")
    let st = openStore(db, allFragments)
    st.db.exec(sql"update activity set start = null where file_id in (select id from file where name = 'paris')")
    st.close()
    let rows = shown(db, "-v").lines.texts
    check rows[1].contains("38.7200,-9.1400")           # lisbon1: a start, but no place stored: where
    check rows[2].contains("no GPS")                     # paris: no start at all

  test "saving is logged":
    let db = world("shownlog")
    let path = dir / "shownlog" / "nch.log"
    let g = Globals(dbPath: db, fragments: allFragments, log: openLog(path))
    check listCommand.run(g, @["--newest", "1", "--save"]) == exitOk
    g.log.close()
    check readFile(path).contains("list      saved      1 activity")
