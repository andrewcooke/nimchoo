## The frame of the activities on a calendar (activities/calendarframe.nim): the start of each selected activity, the line
## that sums them up, and the tables it reads, as its declaration says.

import std/[os, strutils, unittest]
import nimchoo/core/[access, extension]
import nimchoo/packages/calendar/frames
import nimchoo/packages/db/[access, statement]
import nimchoo/packages/fit/time
import nimchoo/packages/ui/style
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

let dir = getTempDir() / "nch-test-activities-calendar"

proc world(name: string): string =
  ## A database with two activities, the first of them selected; its path.
  removeDir(dir / name)
  result = dir / name / "x.db"
  let s = openSession(result, allFragments, access = allAccess)
  defer:
    s.close()
  for (tag, t) in [("ride", 1530446400), ("run", 1535371200)]:
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :name, 0)",
      userId = s.userId,
      name = tag,
    )
    s.db.execute(
      "insert into activity(file_id, session, start_t, end_t, sport, distance_m, timer_s) select max(id), 0, :t, :t + 100, 'cycling', 1000.0, 600.0 from file",
      t = t,
    )
  s.db.execute(
    "insert into activity_selection(user_id, activity_id) select :userId, min(id) from activity",
    userId = s.userId,
  )

proc frame(): CalendarFrame =
  let all = framesOf(extensions.get(calendarFramePoint), "activities")
  doAssert all.len == 1
  all[0]

suite "activities frame on a calendar":
  test "a mark at the start of each selected activity, and the line that sums them up":
    let s = openSession(world("marks"), allFragments, access = allAccess)
    defer:
      s.close()
    let made = frame().make(s)
    check made.marks == @[UnixTime(1530446400)]
    check made.summary.text.startsWith("done: 1 of 2 activities,") and
      "match selected" notin made.summary.text

  test "every table the frame reads is in its declaration":
    let s =
      openSession(world("declared"), allFragments, access = newAllAccess(amEnforce))
    defer:
      s.close()
    startRecording()
    discard frame().make(s)
    let read = stopRecording()
    check read.len > 0
    for t in read:
      check t in frame().tables

suite "activities: the days under every calendar":
  proc background(): CalendarDays =
    let all = extensions.get(calendarDaysPoint)
    doAssert all.len == 1
    all[0]

  test "the start of every activity of the user, selected or not":
    let s = openSession(world("background"), allFragments, access = allAccess)
    defer:
      s.close()
    check background().make(s) == @[UnixTime(1530446400), UnixTime(1535371200)]

  test "every table the background reads is in its declaration":
    let s = openSession(
      world("background-declared"), allFragments, access = newAllAccess(amEnforce)
    )
    defer:
      s.close()
    startRecording()
    discard background().make(s)
    let read = stopRecording()
    check read.len > 0
    for t in read:
      check t in background().tables
