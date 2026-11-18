## The frame of the climbs on a calendar (climbs/calendarframe.nim): the days you went up a selected climb.

import std/[os, unittest]
import nimchoo/core/extension
import nimchoo/packages/calendar/frames
import nimchoo/packages/db/statement
import nimchoo/packages/fit/time
import nimchoo/packages/ui/style
import nimchoo/packages/user/session
import ../support/mapworld
from nimchoo/registry import allFragments, allAccess, extensions

let dir = getTempDir() / "nch-test-climbs-calendar"

proc climbsFrame(): CalendarFrame =
  for f in extensions.get(calendarFramePoint):
    if f.subject == "climbs":
      return f
  raiseAssert "no calendar frame of the climbs"

suite "climbs on the calendar":
  test "a day is marked for each attempt on a selected climb, and the line sums them up":
    let w = world(dir, "marks")
    withClimb(w.db) # (ridden once, by activity 1, at t = 1)
    let s = openSession(w.db, allFragments, access = allAccess)
    defer:
      s.close()
    check climbsFrame().make(s).marks.len == 0 # (nothing selected)
    s.db.execute(
      "insert into climb_selection(user_id, sector_id) select :userId, id from sector",
      userId = s.userId,
    )
    let made = climbsFrame().make(s)
    check made.marks == @[UnixTime(1)]
    check made.summary.text == "done: 1 attempt on the 1 selected climb"
