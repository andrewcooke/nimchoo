## The calendar frames of the real registry (what no one package can check about the others): every frame is of a subject that
## exists, and a subject has at most one.

import std/[sequtils, unittest]
import nimchoo/core/extension
import nimchoo/packages/calendar/frames
import nimchoo/packages/subject/subjects
from nimchoo/registry import extensions

suite "calendar: the registry of frames":
  test "every frame is of a subject that is registered":
    let names = extensions.get(subjectPoint).mapIt(it.name)
    check names.len > 0
    for f in extensions.get(calendarFramePoint):
      check f.subject in names

  test "a subject has at most one frame, and the default subject has one":
    let all = extensions.get(calendarFramePoint)
    for f in all:
      check framesOf(all, f.subject).len == 1
    check framesOf(all, defaultSubject(extensions.get(subjectPoint)).name).len == 1
