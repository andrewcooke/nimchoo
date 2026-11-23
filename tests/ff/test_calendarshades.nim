## The shades of the models and of the activities on a calendar, on a ride with heart rate.

import std/[sequtils, unittest]
import nimchoo/core/[access, extension]
import nimchoo/packages/calendar/frames
import nimchoo/packages/db/access
import nimchoo/packages/user/session
import ../support/[env, rideworld]
from nimchoo/registry import allFragments, newAllAccess, extensions

suite "calendar shades":
  teardown:
    useTestCache()
  test "a curve gives its value at the end of each interval; the impulse, the sum over each":
    let w = world("shades")
    let s = openSession(w.db, allFragments, access = newAllAccess(amEnforce))
    defer:
      s.close()
    let shades = extensions.get(calendarShadePoint)
    check shades.mapIt(it.name) == @["fitness", "fatigue", "form", "impulse"]
    # the ride is on 27 August 2018, 10:04 to 11:03 (-03:00): before it, after it, and the day it was in
    let ivs: seq[Interval] =
      @[(1535300000'i64, 1535370000'i64), (1535370000'i64, 1535400000'i64)]
    for sh in shades:
      startRecording()
      let got = sh.make(s, ivs)
      let read = stopRecording()
      check got.values.len == 2 and got.label.len > 0
      for t in read:
        check t in sh.tables
      if sh.name in ["fitness", "fatigue", "impulse"]:
        check got.values[0] == 0 and got.values[1] > 0
