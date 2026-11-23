import nimchoo/packages/db/statement
import std/[os, options, sequtils, unittest]
import ../support/shims
import nimchoo/core/globals
import nimchoo/core/line
import nimchoo/packages/db/store
import nimchoo/packages/user/session
import nimchoo/core/errors
import nimchoo/packages/util/bytes/bytes
import nimchoo/packages/importer/importer
import nimchoo/packages/model/command
import nimchoo/packages/model/calc
import nimchoo/packages/model/impulses
import nimchoo/packages/model/models
import nimchoo/packages/model/params
import nimchoo/packages/editable/editable
import nimchoo/packages/subject/subjects
import nimchoo/packages/tags/tag
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/heartrate/step
import nimchoo/packages/fit/load
import nimchoo/packages/user/command as userCommand
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

proc open(path: string, user = ""): Session =
  openSession(
    path,
    allFragments,
    (if user.len > 0: some(user) else: none(string)),
    access = allAccess,
  )

proc importRide(s: Session, name = "ride.fit"): ImportResult =
  var ws: seq[Warning]
  s.importFile(p, name, readBytes(ride), ws, @[heartrateStep])

proc q(s: Session, sqlText: string, T: typedesc): T =
  s.db.scalar(T, sqlText)

proc setFthr(s: Session, fthr: int) =
  s.db.execute(
    """insert into user_profile(user_id, fthr) values (:userId, :fthr)
    on conflict(user_id) do update set fthr = excluded.fthr""",
    userId = s.userId,
    fthr = fthr,
  )

proc globals(db: string, user = ""): Globals =
  Globals(
    dbPath: some(db),
    user: (if user.len > 0: some(user) else: none(string)),
    fragments: allFragments,
    access: allAccess,
  )

proc pattern(text: string): TagPattern =
  parsePattern(text).pattern.get

proc named(ms: seq[Model]): seq[string] =
  ms.mapIt(it.name)

suite "model: the models in the database":
  test "a new database has the default model, built in, as the program defines it, selected":
    let s = open(fresh("default"))
    defer:
      s.close()
    let ms = loadModels(s.db)
    check ms.len == 1
    var d = defaultModel()
    d.id = ms[0].id
    check ms[0] == d and ms[0].builtIn
    check findModel(s.db, "default").isSome and findModel(s.db, "nope").isNone
    check findModel(s.db, "DEFAULT").isSome # (case aside, as tags)
    check selectedModels(s.db, s.userId).named == @["default"]
    s.db.execute("insert into user(name) values ('bob')")
    let bob = UserId(s.db.scalar(int64, "select id from user where name = 'bob'"))
    check selectedModels(s.db, bob).named == @["default"] # (a new user has it too)
  test "a model is added, with its patterns; a name is used once, case and accents aside; bad values are refused":
    let s = open(fresh("add"))
    defer:
      s.close()
    var m = defaultModel()
    m.name = "flat"
    m.builtIn = false
    m.gamma = 1
    m.patterns = @[pattern("sport:cycling*"), pattern("bike:*")]
    discard insertModel(s.db, m)
    let got = findModel(s.db, "flat").get
    check got.gamma == 1 and not got.builtIn
    check got.patterns == @[pattern("bike:*"), pattern("sport:cycling*")]
    m.name = "FLÁT"
    expect StoreError:
      discard insertModel(s.db, m)
    m.name = "bad"
    m.zero = 6
    expect StoreError:
      discard insertModel(s.db, m)
    m = defaultModel()
    m.name = "bad2"
    m.zones = [68.0, 80, 70, 105, 121]
    expect StoreError:
      discard insertModel(s.db, m)
    check loadModels(s.db).len == 2
    check selectedModels(s.db, s.userId).named == @["default"] # (not selected)
  test "the steps: names, within the selection, the selection added":
    let s = open(fresh("search"))
    defer:
      s.close()
    for name in ["cycling:easy", "cycling:hard", "running"]:
      var m = defaultModel()
      m.name = name
      m.builtIn = false
      discard insertModel(s.db, m)
    check searchModels(s.db, s.userId, @[], amEvery, false).named ==
      @["cycling:easy", "cycling:hard", "default", "running"]
    check searchModels(s.db, s.userId, @[pattern("cycling:*")], amEvery, false).named ==
      @["cycling:easy", "cycling:hard"]
    check searchModels(
      s.db, s.userId, @[pattern("Cycling:H*"), pattern("run*")], amEvery, false
    ).named == @["cycling:hard", "running"]
    check searchModels(s.db, s.userId, @[pattern("cycling:*")], amEvery, true).named ==
      @["cycling:easy", "cycling:hard", "default"]
    check searchModels(s.db, s.userId, @[pattern("*")], amSelection, false).named ==
      @["default"]
    replaceModelSelection(
      s.db,
      s.userId,
      searchModels(s.db, s.userId, @[pattern("r*")], amEvery, false).mapIt(it.id),
    )
    check selectedModels(s.db, s.userId).named == @["running"]

proc defaultM(s: Session): Model =
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
      Calculated(activities: 1, stretches: 1)
    check s.q("select count(*) from impulse", int) == 1
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
      Calculated(activities: 1, stretches: 1)
  test "an activity with no heart rate has no impulse":
    let s = open(fresh("nohr"))
    defer:
      s.close()
    s.setFthr(154)
    discard s.importRide()
    s.db.execute("delete from heartrate_series")
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
    check b.q("select count(*) from impulse", int) == 2
    b.setFthr(150)
    check b.q("select count(*) from impulse", int) == 2 # (unchanged)
    b.setFthr(160)
    check b.q("select count(*) from impulse", int) == 1
    check b.q(
      "select count(*) from impulse i join activity a on a.id = i.activity_id join file f on f.id = a.file_id join user u on u.id = f.user_id where u.name = 'default'",
      int,
    ) == 1
    b.db.execute(
      "update user_profile set fthr = null where user_id = :userId", userId = b.userId
    )
    check b.q("select count(*) from impulse", int) == 1
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
    m.builtIn = false
    let other = insertModel(s.db, m)
    check s.q("select count(*) from impulse", int) == 0
    discard calculateMissing(s.db, s.userId, s.defaultM)
    check calculateMissing(s.db, s.userId, findModel(s.db, "other").get) ==
      Calculated(activities: 1, stretches: 1)
    check s.q("select count(*) from impulse", int) == 2
    deleteModels(s.db, @[other])
    check s.q("select count(*) from impulse", int) == 1
    s.db.execute("delete from activity")
    check s.q("select count(*) from impulse", int) == 0
  test "an edit that changes the impulse deletes the model's impulses; one that does not keeps them":
    let s = open(fresh("edit"))
    defer:
      s.close()
    s.setFthr(154)
    discard s.importRide()
    var m = defaultModel()
    m.name = "other"
    m.builtIn = false
    m.id = insertModel(s.db, m)
    discard calculateMissing(s.db, s.userId, m)
    var n = m
    n.fitnessDays = 20
    n.patterns = @[pattern("sport:*")]
    updateModel(s.db, m, n)
    check s.q("select count(*) from impulse", int) == 1
    var o = n
    o.gamma = 3
    updateModel(s.db, n, o)
    check s.q("select count(*) from impulse", int) == 0
    check findModel(s.db, "other").get == o
  test "the patterns choose which impulses count":
    let s = open(fresh("patterns"))
    defer:
      s.close()
    s.setFthr(154)
    discard s.importRide()
    var m = s.defaultM
    discard calculateMissing(s.db, s.userId, m)
    check userLumps(s.db, s.userId, m).len == 1
    m.patterns = @[pattern("sport:cycling*")]
    check userLumps(s.db, s.userId, m).len == 1 # (the ride's sport is cycling)
    s.db.execute(
      "insert into ff_model_pattern(model_id, pattern, folded) values (:id, 'x', 'x')",
      id = m.id,
    )
    check userLumps(s.db, s.userId, m).len == 0 # (no tag matches "x")

suite "model: heart rate":
  test "whether the user has an activity with heart rate":
    let s = open(fresh("hasheart"))
    defer:
      s.close()
    check not hasHeartRate(s.db, s.userId)
    discard s.importRide()
    check hasHeartRate(s.db, s.userId)
    s.db.execute("delete from heartrate_series")
    check not hasHeartRate(s.db, s.userId)
  test "only the user's own activities count":
    let s = open(fresh("hasheartowner"))
    defer:
      s.close()
    discard s.importRide()
    s.db.execute("insert into user(name) values ('bob')")
    check not hasHeartRate(
      s.db, UserId(s.db.scalar(int64, "select id from user where name = 'bob'"))
    )

suite "nch models":
  test "the table":
    let s = open(fresh("list"))
    defer:
      s.close()
    var m = defaultModel()
    m.name = "flat"
    m.patterns = @[pattern("sport:cycling*")]
    check table(modelKind(), @[s.defaultM, m], @[true, false], 200, false).mapIt(
      it.text
    ) ==
      @[
        "model   │ gamma │ zero │ one │ max_gap_s │ zones_%          │ fitness_decay_d │ fatigue_decay_d │ fitness_scale │ fatigue_scale │ tags",
        "────────┼───────┼──────┼─────┼───────────┼──────────────────┼─────────────────┼─────────────────┼───────────────┼───────────────┼───────────────",
        "default │     2 │    1 │   6 │        60 │ 68/83/94/105/121 │              42 │               7 │             1 │             5",
        "flat    │     2 │    1 │   6 │        60 │ 68/83/94/105/121 │              42 │               7 │             1 │             5 │ sport:cycling*",
      ]
  test "add, from default or a base; nothing is worked out yet; a name is taken once":
    let db = fresh("addcmd")
    let s = open(db)
    s.setFthr(154)
    discard s.importRide()
    s.close()
    let g = globals(db)
    check command.run(
      g, @["--add", "flat", "--gamma", "1", "--zones", "60,70,80,90,100"]
    ) == exitOk
    check command.run(
      g, @["--add", "flatter", "--base", "flat", "--zero", "2", "--tags", "sport:*"]
    ) == exitOk
    let t = open(db)
    defer:
      t.close()
    let f = findModel(t.db, "flatter").get
    check f.gamma == 1 and f.zero == 2 and f.zones[0] == 60 and not f.builtIn and
      f.patterns == @[pattern("sport:*")]
    check t.q("select count(*) from impulse", int) == 0
    check command.run(g, @["--add", "Flat"]) == exitFailure # the name is taken
    check command.run(g, @["--add", "bad", "--zero", "9"]) == exitFailure
      # (zero is not below one)
    check command.run(g, @["--add", "x", "--base", "nope"]) == exitFailure
    check command.run(g, @["--add", "a b"]) == exitUsage # (not a name)
    check command.run(g, @["--gamma", "9"]) == exitUsage
      # (a value with no --add or --edit)
    check command.run(g, @["--add", "y", "--names", "x"]) == exitUsage
    check command.run(g, @["--add", "y", "--select"]) == exitUsage
    check loadModels(t.db).len == 3
    check command.run(g, @[]) == exitOk
  test "edit and rename; the built-in model never changes":
    let db = fresh("editcmd")
    let g = globals(db)
    check command.run(g, @["--add", "mine"]) == exitOk
    check command.run(g, @["--edit", "MINE", "--fatigue-decay", "10d", "--tags"]) ==
      exitOk
    check command.run(g, @["--edit", "mine", "--rename", "yours"]) == exitOk
    check command.run(g, @["--edit", "yours", "--rename", "default"]) == exitFailure
    check command.run(g, @["--edit", "default", "--gamma", "3"]) == exitFailure
    check command.run(g, @["--edit", "yours"]) == exitUsage # (nothing to change)
    check command.run(g, @["--edit", "nope", "--gamma", "3"]) == exitFailure
    let t = open(db)
    defer:
      t.close()
    check findModel(t.db, "yours").get.fatigueDays == 10
    check findModel(t.db, "mine").isNone
    check findModel(t.db, "default").get == t.defaultM
  test "the selection, and deleting what is listed (never the built-in model)":
    let db = fresh("deletecmd")
    let g = globals(db)
    for name in ["a:1", "a:2", "b"]:
      check command.run(g, @["--add", name]) == exitOk
    check command.run(g, @["--names", "a:*", "--also", "--select"]) == exitOk
    let t = open(db)
    defer:
      t.close()
    check selectedModels(t.db, t.userId).named == @["a:1", "a:2", "default"]
    check command.run(g, @["--names", "a:*", "--delete"]) == exitOk
      # (no -y, no terminal: nothing)
    check loadModels(t.db).len == 4
    check command.run(g, @["--within", "--names", "*", "--delete", "-y"]) == exitOk
    check loadModels(t.db).named == @["b", "default"]
    check command.run(g, @["--names", "a:*", "--delete", "--select"]) == exitUsage
    check command.run(g, @["--all", "--names", "b"]) == exitUsage

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
    check t.q("select count(*) from impulse", int) == 1
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
    check v.q("select n from heartrate_series", int) == 2099 # (the heart rate stays)
  test "making a user with an FTHR":
    let db = fresh("usernew")
    check userCommand.run(globals(db), @["--add", "bob", "--fthr", "150"]) == exitOk
