import nimchoo/db/statement
import std/[os, options, unittest]
import ../support/shims
import nimchoo/core/globals
import nimchoo/db/store
import nimchoo/core/errors
import nimchoo/packages/util/bytes/bytes
import nimchoo/importer/importer
import nimchoo/model/[calc, command, impulses, models]
import nimchoo/modules
import nimchoo/packages/fit/load
import nimchoo/user/command as userCommand
import nimchoo/packages/util/warnings/warnings

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"

let p = loadProfile(profilePath)
let dir = getTempDir() / "nch-test-model"

proc fresh(name: string): string =
  createDir(dir)
  result = dir / name & ".db"
  removeFile(result)

proc open(path: string, user = ""): Store =
  store.openStore(path, allFragments, user)

proc importRide(s: Store, name = "ride.fit"): ImportResult =
  var ws: seq[Warning]
  s.importFile(p, name, readBytes(ride), ws, allImportSteps)

proc q(s: Store, sqlText: string, T: typedesc): T =
  s.db.scalar(T, sqlText)

proc setFthr(s: Store, fthr: int) =
  s.db.execute(
    """insert into user_profile(user_id, fthr) values (:userId, :fthr)
    on conflict(user_id) do update set fthr = excluded.fthr""",
    userId = s.userId,
    fthr = fthr,
  )

proc globals(db: string, user = ""): Globals =
  Globals(dbPath: db, user: user, fragments: allFragments)

suite "model: the models in the database":
  test "a new database has the default model, as the program defines it":
    let s = open(fresh("default"))
    defer:
      s.close()
    let ms = loadModels(s.db)
    check ms.len == 1
    var d = defaultModel()
    d.id = ms[0].id
    check ms[0] == d
    check findModel(s.db, "default").isSome and findModel(s.db, "nope").isNone
  test "a model is added; a name is used once; bad values are refused":
    let s = open(fresh("add"))
    defer:
      s.close()
    var m = defaultModel()
    m.name = "flat"
    m.gamma = 1
    insertModel(s.db, m)
    check findModel(s.db, "flat").get.gamma == 1
    expect StoreError:
      insertModel(s.db, m)
    m.name = "bad"
    m.zero = 6
    expect StoreError:
      insertModel(s.db, m)
    m = defaultModel()
    m.name = "bad2"
    m.zones = [68.0, 80, 70, 105, 121]
    expect StoreError:
      insertModel(s.db, m)
    check loadModels(s.db).len == 2

proc defaultM(s: Store): Model =
  findModel(s.db, "default").get

suite "model: impulses, worked out when wanted":
  test "importing makes no impulse, with or without an FTHR; the heart rate is stored":
    let s = open(fresh("import"))
    defer:
      s.close()
    s.setFthr(154)
    let r = s.importRide()
    check r.extras.len == 1 and r.extras[0].n == 2099
    check s.q("select count(*) from impulse", int) == 0
  test "when wanted they are worked out, close to the original's algorithm; asking again does nothing":
    let s = open(fresh("wanted"))
    defer:
      s.close()
    s.setFthr(154)
    discard s.importRide()
    check calculateMissing(s.db, s.userId, s.defaultM) ==
      Calculated(activities: 1, hours: 2)
    check s.q("select count(*) from impulse", int) == 2
    # the same ride on the original's 10-second grid gives 72.53 (this is exact: within 1%)
    let total = s.q("select sum(value) from impulse", float)
    check abs(total - 72.53) / 72.53 < 0.01
    check calculateMissing(s.db, s.userId, s.defaultM) == Calculated()
  test "no FTHR, no impulse; with one given later, the existing activities get theirs":
    let s = open(fresh("later"))
    defer:
      s.close()
    discard s.importRide()
    check calculateMissing(s.db, s.userId, s.defaultM) == Calculated()
    s.setFthr(154)
    check calculateMissing(s.db, s.userId, s.defaultM) ==
      Calculated(activities: 1, hours: 2)
  test "an activity with no heart rate has no impulse":
    let s = open(fresh("nohr"))
    defer:
      s.close()
    s.setFthr(154)
    discard s.importRide()
    s.db.execute("delete from heartrate")
    check calculateMissing(s.db, s.userId, s.defaultM) == Calculated()
  test "a changed FTHR deletes that user's impulses (only theirs), an unchanged one does not":
    let path = fresh("trigger")
    let a = open(path)
    a.db.execute("insert into user(name) values ('bob')")
    a.setFthr(154)
    discard a.importRide()
    discard calculateMissing(a.db, a.userId, a.defaultM)
    a.close()
    let b = open(path, "bob")
    defer:
      b.close()
    b.setFthr(150)
    discard b.importRide("bobs.fit")
    discard calculateMissing(b.db, b.userId, b.defaultM)
    check b.q("select count(*) from impulse", int) == 4
    b.setFthr(150)
    check b.q("select count(*) from impulse", int) == 4 # (unchanged)
    b.setFthr(160)
    check b.q("select count(*) from impulse", int) == 2
    check b.q(
      "select count(*) from impulse i join activity a on a.id = i.activity_id join file f on f.id = a.file_id join user u on u.id = f.user_id where u.name = 'default'",
      int,
    ) == 2
    b.db.execute(
      "update user_profile set fthr = null where user_id = :userId", userId = b.userId
    )
    check b.q("select count(*) from impulse", int) == 2
  test "a higher FTHR means less impulse":
    let s = open(fresh("higher"))
    defer:
      s.close()
    discard s.importRide()
    s.setFthr(150)
    discard calculateMissing(s.db, s.userId, s.defaultM)
    let low = s.q("select sum(value) from impulse", float)
    s.setFthr(170)
    discard calculateMissing(s.db, s.userId, s.defaultM)
    check s.q("select sum(value) from impulse", float) < low
  test "each model has its own, and they go with their activity and their model":
    let s = open(fresh("cascade"))
    defer:
      s.close()
    s.setFthr(154)
    discard s.importRide()
    var m = defaultModel()
    m.name = "other"
    insertModel(s.db, m)
    check s.q("select count(*) from impulse", int) == 0
    discard calculateMissing(s.db, s.userId, s.defaultM)
    check calculateMissing(s.db, s.userId, findModel(s.db, "other").get) ==
      Calculated(activities: 1, hours: 2)
    check s.q("select count(*) from impulse", int) == 4
    s.db.execute("delete from ff_model where name = 'other'")
    check s.q("select count(*) from impulse", int) == 2
    s.db.execute("delete from activity")
    check s.q("select count(*) from impulse", int) == 0

suite "model: the key of what impulses are made from":
  test "none without an FTHR or heart rate; the same for the same data; different when anything changes":
    let path = fresh("key")
    let s = open(path)
    defer:
      s.close()
    check inputKey(s.db, s.userId, s.defaultM) == ""
    discard s.importRide()
    check inputKey(s.db, s.userId, s.defaultM) == "" # (no FTHR)
    s.setFthr(154)
    let k = inputKey(s.db, s.userId, s.defaultM)
    check k.len == 12
    check inputKey(s.db, s.userId, s.defaultM) == k
    s.setFthr(155)
    check inputKey(s.db, s.userId, s.defaultM) != k # another FTHR
    s.setFthr(154)
    check inputKey(s.db, s.userId, s.defaultM) == k
    var m = defaultModel()
    m.name = "other"
    insertModel(s.db, m)
    check inputKey(s.db, s.userId, findModel(s.db, "other").get) != k # another model
    discard s.importRide("copy.fit") # the same content: nothing new
    check inputKey(s.db, s.userId, s.defaultM) == k
    s.db.execute("delete from heartrate")
    check inputKey(s.db, s.userId, s.defaultM) == ""
  test "it does not depend on database ids: the same ride in another database has the same key":
    let a = open(fresh("keya"))
    let b = open(fresh("keyb"))
    defer:
      a.close()
      b.close()
    b.db.execute("insert into user(name) values ('pad')") # (other ids)
    for s in [a, b]:
      s.setFthr(154)
      discard s.importRide()
    check inputKey(a.db, a.userId, a.defaultM) == inputKey(b.db, b.userId, b.defaultM)

suite "nch models":
  test "the list":
    let db = fresh("list")
    let s = open(db)
    defer:
      s.close()
    check modelLines(loadModels(s.db)) ==
      @[
        "model    gamma  zero  one  max_secs  zones_%           fitness_d  fatigue_d",
        "default      2     1    6        60  68/83/94/105/121         42          7",
      ]
  test "add a model: it is listed, and nothing is worked out yet":
    let db = fresh("addcmd")
    let s = open(db)
    s.setFthr(154)
    discard s.importRide()
    s.close()
    check command.run(
      globals(db), @["--add", "flat", "--gamma", "1", "--zones", "60,70,80,90,100"]
    ) == exitOk
    let t = open(db)
    defer:
      t.close()
    check loadModels(t.db).len == 2
    check t.q("select count(*) from impulse", int) == 0
    check command.run(globals(db), @["--add", "flat"]) == exitFailure # the name is taken
    check command.run(globals(db), @["--add", "bad", "--zero", "9"]) == exitUsage
    check command.run(globals(db), @["--gamma", "9"]) == exitUsage
    check loadModels(t.db).len == 2
    check command.run(globals(db), @[]) == exitOk

suite "nch users: the FTHR and the impulses":
  test "setting it works nothing out; changing it deletes the impulses; clearing it deletes them":
    let db = fresh("usercmd")
    let s = open(db)
    discard s.importRide()
    s.close()
    check userCommand.run(globals(db), @["--edit", "default", "--fthr", "154"]) == exitOk
    let t = open(db)
    check t.q("select count(*) from impulse", int) == 0
    discard calculateMissing(t.db, t.userId, t.defaultM)
    check t.q("select count(*) from impulse", int) == 2
    t.close()
    check userCommand.run(globals(db), @["--edit", "default", "--fthr", "160"]) == exitOk
    let u = open(db)
    check u.q("select count(*) from impulse", int) == 0
    discard calculateMissing(u.db, u.userId, u.defaultM)
    u.close()
    check userCommand.run(globals(db), @["--edit", "default", "--clear-fthr"]) == exitOk
    let v = open(db)
    defer:
      v.close()
    check v.q("select count(*) from impulse", int) == 0
    check v.q("select count(*) from heartrate", int) == 2099 # (the heart rate stays)
  test "making a user with an FTHR":
    let db = fresh("usernew")
    check userCommand.run(globals(db), @["--add", "bob", "--fthr", "150"]) == exitOk
