## `nch plot` with the real frames (the models' and the activities'), on a ride with heart rate.

import std/[options, os, sequtils, strutils, times, unittest]
import nimchoo/core/globals
import nimchoo/packages/cache/cache
import nimchoo/packages/db/access
import nimchoo/packages/plot/[command as plotCommand, frames]
import nimchoo/packages/user/session
import nimchoo/packages/web/request
import nimchoo/packages/plot/params
import nimchoo/packages/subject/subjects
import nimchoo/packages/channels/kinds
import nimchoo/core/[access, extension, ids]
import nimchoo/packages/db/statement
import ../support/[env, rideworld]
from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

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
    let w = world("plot-ff")
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
    let w = world("plot-activities")
    check run(w.db, "--file") == exitOk
    let impulse = rows(w.cache / "plot-activities-impulse.csv")
    check impulse.len == 2 and impulse[1].startsWith("2018-08-27T00:00:00")
    check abs(impulse[1].split(',')[2].parseFloat - 72.44) < 0.1
  test "the page lists every frame; the worker makes one frame for it; no FTHR is a failure":
    let w = world("plot-page")
    check run(w.db, "ff", "--worker") == exitOk
    let page = readFile(w.cache / "plot-ff.html")
    check "\"name\":\"fitness\"" in page and "\"name\":\"form\"" in page and
      "plot.umd.min.js" in page
    check run(w.db, "ff", "--worker", "--frame", "form") == exitOk
    check fileExists(w.cache / "plot-ff-form.csv")
    check run(w.db, "ff", "--worker", "--frame", "nope") == exitUsage
    check run(w.db, "nope", "--file") == exitUsage
    let v = world("plot-nofthr", fthr = false)
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
    let w = world("plot-tables")
    let s = openSession(w.db, allFragments, access = newAllAccess(amEnforce))
    defer:
      s.close()
    let period = periodOf(parseArgs(@[]).params, 1600000000, utc())
    let activity = ActivityId(s.db.scalar(int64, "select id from activity"))
    for f in extensions.get(plotFramePoint):
      startRecording()
      case f.axis
      of axDays:
        discard f.make(s, period)
      of axActivity:
        discard f.makeActivity(s, activity)
      let read = stopRecording()
      check read.len > 0
      for t in read:
        if t notin f.tables:
          checkpoint f.name & " reads " & t
        check t in f.tables

  test "the inside of an activity: the page lists the selected ones; the worker makes a frame for one; --file one each":
    let w = world("plot-activity")
    let s = openSession(w.db, allFragments, access = allAccess)
    let id = s.db.scalar(int64, "select id from activity")
    s.close()
    check run(w.db, "activity", "--worker") == exitOk
    let page = readFile(w.cache / "plot-activity.html")
    check "const axis = 'activity'" in page
    check "\"id\":" & $id in page and "\"label\":\"2018-08-27" in page
    check "\"name\":\"heartrate\"" in page and "\"name\":\"altitude\"" in page
    check run(w.db, "activity", "--worker", "--frame", "heartrate", "--activity", $id) ==
      exitOk
    let hr = rows(w.cache / ("plot-activity-heartrate-" & $id & ".csv"))
    check hr[0] == "time,series,value"
    check hr.len > 2000 and hr[1].split(',')[1] == "\"default\""
      # (for the page, the frame's own name: the page knows which activity it asked for)
    check run(w.db, "activity", "--worker", "--frame", "breaks", "--activity", $id) ==
      exitOk
    let breaks = rows(w.cache / ("plot-activity-breaks-" & $id & ".csv"))
    check breaks.len > 1 and breaks[1].split(',')[1] == "\"pause\""
    check run(w.db, "activity", "--file", "--frames", "breaks") == exitOk
    check rows(w.cache / "plot-activity-breaks.csv")[1].split(',')[1].endsWith(
      ": pause\""
    ) # (for --file, the activity and the kind)
    check run(
      w.db, "activity", "--worker", "--frame", "heartrate", "--activity", "999999"
    ) == exitFailure # (not in the selection)
    check run(w.db, "activity", "--file") == exitOk
    check rows(w.cache / "plot-activity-altitude.csv") ==
      @["time,series,value"] # (this ride's device records no altitude)
    check run(w.db, "activity", "--file", "--frames", "speed") == exitOk
    let speed = rows(w.cache / "plot-activity-speed.csv")
    check speed.len > 2000 and speed[1].split(',')[^1].parseFloat < 80 # (km/h)
    check "\"name\":\"distance\",\"summary\"" in page and "\"along\":true" in page
    # the speed in km/h, the distance in km: the device's, else along the positions
    check run(w.db, "activity", "--file", "--frames", "distance") == exitOk
    let device =
      rows(w.cache / "plot-activity-distance.csv")[^1].split(',')[^1].parseFloat
    check abs(device - 11.978) < 0.01
    block:
      let t = openSession(w.db, allFragments, access = allAccess)
      t.db.execute("delete from channel_series where channel = 'distance'")
      t.close()
    check run(w.db, "activity", "--file", "--frames", "distance") == exitOk
    let along =
      rows(w.cache / "plot-activity-distance.csv")[^1].split(',')[^1].parseFloat
    check abs(along - device) / device < 0.05
      # (the positions agree with the device to within 5%)
    check run(w.db, "activity", "--after", "2018-01-01", "--file") == exitUsage
    check run(w.db, "activity", "--worker", "--activity", $id) == exitUsage
      # (no --frame)

  test "an address with a frame of one activity is one the server accepts":
    let r = route(
      parseTarget("/plot/activity?frame=heartrate&activity=12").get,
      @[pageOf("plot", plotSpec(), isWord)],
    )
    check r.isSome and
      r.get.args == @["activity", "--frame", "heartrate", "--activity", "12"]
    check route(
      parseTarget("/plot/activity?frame=heartrate&activity=x1").get,
      @[pageOf("plot", plotSpec(), isWord)],
    ).isNone

  test "the frames of a subject share an axis; the activity has the altitude and a frame for each channel":
    var axes: seq[(string, Axis)]
    for f in extensions.get(plotFramePoint):
      check isWord(f.name)
      for (subject, axis) in axes:
        if subject == f.subject:
          checkpoint f.subject & " " & f.name
          check axis == f.axis
      axes.add (f.subject, f.axis)
    let mine = framesOf(extensions.get(plotFramePoint), "activity")
    check mine.len == 1 + ChannelKind.high.ord + 1 + 1 + 1
      # altitude, the channels, a run's steps, the breaks
    check mine.filterIt(it.mark == mkRule).mapIt(it.name) == @["breaks"]
    check mine.allIt(it.axis == axActivity)
    check mine.filterIt(it.along).mapIt(it.name) == @["distance"]
    for s in extensions.get(subjectPoint):
      if s.name == "activity":
        check s.pick.isSome
