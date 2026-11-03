import std/[algorithm, os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/modules
import nimchoo/selection/command as listCommand

let dir = getTempDir() / "nch-test-select"

const
  july1 = 1530446400      # 2018-07-01T12:00Z
  aug15 = 1534334400      # 2018-08-15T12:00Z
  aug27 = 1535371200      # 2018-08-27T12:00Z

proc addActivity(s: Store, userId: int64, tag: string, startT: int, wkt: string,
                 sport = "", subSport = "") =
  s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
            userId, tag, tag)
  let f = s.db.getValue(sql"select max(id) from file")
  s.db.exec(sql"""insert into activity(file_id, session, start_t, end_t, sport, sub_sport)
                  values (?, 0, ?, ?, nullif(?, ''), nullif(?, ''))""",
            f, startT, startT + 100, sport, subSport)
  let a = s.db.getValue(sql"select max(id) from activity")
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
              "cycling", "road")
  addActivity(s, s.userId, "paris", aug27, "MULTILINESTRING((2.35 48.85, 2.40 48.90))",
              "running", "trail")
  s.db.exec(sql"insert into coords(activity_id, t, lon, lat) values (2, 1, 2.35, 48.85)")
  s.db.exec(sql"insert into coords(activity_id, t, lon, lat) values (2, 2, 2.40, 48.90)")
  addActivity(s, bob, "lisbon2", aug15, "MULTILINESTRING((-9.20 38.70, -9.15 38.74))",
              "cycling")

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
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--radius", "5")
    check chosen(db) == @["lisbon1", "lisbon2"]
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--radius", "0.3")
    check chosen(db) == @["lisbon1"]          # (206 m away; the other is further)
    discard save(db, "--users", "default", "bob", "--near", "38.73,-9.13", "--radius", "5000")
    check chosen(db) == @["lisbon1", "lisbon2", "paris"]

  test "a radius on its own is around the latest activity":
    let db = world("radius")
    discard save(db, "--users", "default", "bob", "--radius", "50")
    check chosen(db) == @["paris"]

  test "near the latest activity":
    let db = world("latest")
    discard save(db, "--users", "default", "bob", "--near", "latest", "--radius", "50")
    check chosen(db) == @["paris"]            # (the latest is in Paris)
    check save(db, "--users", "bob", "--near", "latest") == exitFailure   # (no coordinates
    check chosen(db) == @["paris"]                                          # to find a centre;
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
