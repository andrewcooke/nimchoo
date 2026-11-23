## `nch plot` with the real frames (the models' and the activities'), on a ride with heart rate.

import std/[options, os, strutils, times, unittest]
import nimchoo/core/globals
import nimchoo/packages/cache/cache
import nimchoo/packages/db/[access, statement]
import nimchoo/packages/fit/load
import nimchoo/packages/heartrate/step
import nimchoo/packages/plot/[command as plotCommand, frames]
import nimchoo/packages/user/session
import nimchoo/packages/util/bytes/bytes
import nimchoo/packages/util/warnings/warnings
import nimchoo/packages/web/request
import nimchoo/packages/plot/params
import nimchoo/packages/subject/subjects
import nimchoo/core/[access, extension]
import ../support/[env, shims]
from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

let dir = getTempDir() / "nch-test-plot"

proc world(name: string, fthr = true): tuple[db, cache: string] =
  ## One ride with heart rate, selected, and (if `fthr`) an FTHR.
  removeDir(dir / name)
  createDir(dir / name)
  result = (dir / name / "x.db", dir / name / "cache" / "user")
  putEnv("NCH_CACHE", dir / name / "cache")
  let s = openSession(result.db, allFragments, access = allAccess)
  defer:
    s.close()
  var ws: seq[Warning]
  discard s.importFile(
    loadProfile("../choochoo/data/sdk/Profile.xlsx"),
    "r.fit",
    readBytes("../choochoo/data/test/source/personal/2018-08-27-rec.fit"),
    ws,
    @[heartrateStep],
  )
  s.db.execute(
    "insert into activity_selection(user_id, activity_id) select :userId, id from activity",
    userId = s.userId,
  )
  if fthr:
    s.db.execute(
      "insert into user_profile(user_id, fthr) values (:userId, 154)", userId = s.userId
    )

proc globals(db: string): Globals =
  Globals(
    dbPath: some(db), fragments: allFragments, access: allAccess, extensions: extensions
  )

proc run(db: string, args: varargs[string]): int =
  plotCommand.run(globals(db), @args)

proc rows(path: string): seq[string] =
  readFile(path).strip.splitLines

suite "nch plot":
  teardown:
    useTestCache() # (each world points NCH_CACHE at its own)
  test "ff: a CSV for each frame, a series for each selected model, the jump of the ride drawn where it is":
    let w = world("ff")
    check run(w.db, "ff", "--before", "2018-09-01", "--file") == exitOk
    for frame in ["fitness", "fatigue", "form"]:
      check fileExists(w.cache / "plot-ff-" & frame & "-to-2018-08-31.csv")
      check isCacheFileName("plot-ff-" & frame & "-to-2018-08-31.csv")
    let fitness = rows(w.cache / "plot-ff-fitness-to-2018-08-31.csv")
    check fitness[0] == "time,series,value"
    check fitness.len == 1 + 2 + 5
      # (before and at the ride, then the ends of five days: the 27th to the 31st)
    check fitness[1].endsWith("\"default\",0.0000")
    check not fitness[2].endsWith(",0.0000")
    let fatigue = rows(w.cache / "plot-ff-fatigue-to-2018-08-31.csv")
    let form = rows(w.cache / "plot-ff-form-to-2018-08-31.csv")
    # form is scaled fitness minus scaled fatigue (the default model: 1 and 5)
    let (fit, fat, frm) = (
      fitness[^1].split(',')[2].parseFloat,
      fatigue[^1].split(',')[2].parseFloat,
      form[^1].split(',')[2].parseFloat,
    )
    check abs(frm - (fit - fat)) < 1e-3
  test "the activities: the impulse of each day, a bar a day":
    let w = world("activities")
    check run(w.db, "--file") == exitOk
    let impulse = rows(w.cache / "plot-activities-impulse.csv")
    check impulse.len == 2 and impulse[1].startsWith("2018-08-27T00:00:00")
    check abs(impulse[1].split(',')[2].parseFloat - 72.44) < 0.1
  test "the page lists every frame; the worker makes one frame for it; no FTHR is a failure":
    let w = world("page")
    check run(w.db, "ff", "--worker") == exitOk
    let page = readFile(w.cache / "plot-ff.html")
    check "\"name\":\"fitness\"" in page and "\"name\":\"form\"" in page and
      "plot.umd.min.js" in page
    check run(w.db, "ff", "--worker", "--frame", "form") == exitOk
    check fileExists(w.cache / "plot-ff-form.csv")
    check run(w.db, "ff", "--worker", "--frame", "nope") == exitUsage
    check run(w.db, "nope", "--file") == exitUsage
    let v = world("nofthr", fthr = false)
    check run(v.db, "ff", "--file") == exitFailure
  test "an address with the period and a frame is one the server accepts, and the worker parses it the same":
    let r = route(
      parseTarget("/plot/ff?after=2018-08-01&before=2018-09-01&frame=form").get,
      @[pageOf("plot", plotSpec(), isWord)],
    )
    check r.isSome and
      r.get.args ==
      @["ff", "--after", "2018-08-01", "--before", "2018-09-01", "--frame", "form"]
    check webQuery(parseArgs(r.get.args & @["--worker"]).params) ==
      "after=2018-08-01&before=2018-09-01"
  test "each frame reads only the tables it declares":
    let w = world("tables")
    let s = openSession(w.db, allFragments, access = newAllAccess(amEnforce))
    defer:
      s.close()
    let period = periodOf(parseArgs(@[]).params, 1600000000, utc())
    for f in extensions.get(plotFramePoint):
      startRecording()
      discard f.make(s, period)
      let read = stopRecording()
      check read.len > 0
      for t in read:
        if t notin f.tables:
          checkpoint f.name & " reads " & t
        check t in f.tables
