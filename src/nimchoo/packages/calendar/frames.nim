## The frames of a calendar: what the packages that manage a subject contribute for the calendar to draw.  The calendar is a
## view; a frame says which days to mark, made by the package that knows the subject, so the calendar needs nothing of the
## packages above it.  This is an extension point of this package (`calendarFramePoint`).
##
## A subject has at most one calendar frame (a test checks it): a day is marked or not, so two frames would have nothing to
## tell them apart.  A frame says which subject it is of, what it is, whether it reads the selection of the subject, which
## tables it reads (what it depends on; a test checks that the declaration holds every table the frame reads), and how to
## make it.  A frame that fails raises `StoreError` with what to say.
##
## Under every frame the calendar draws the days of a *background* (`calendarBackgroundPoint`), whatever the subject: the
## days that had an activity, contributed by the package that has them, so that the marked days are seen among the days
## you rode.  The calendar does not depend on that package; the contribution is the link.

import ../../core/[errors, extension]
import ../fit/time
import ../ui/style
import ../user/session

{.push raises: [].}

type
  CalendarData* = object ## What a frame made.
    marks*: seq[UnixTime]
      ## instants: the calendar marks the day each falls on, in the user's time zone
    summary*: Line ## the last line ("done: 35 activities, 1,234.5km, 50h12m")

  MakeCalendar* = proc(st: Session): CalendarData {.nimcall, raises: [StoreError].}
    ## Make the frame from the data as they are now, for the user of the session.

  CalendarFrame* = object
    subject*: string ## the subject it is a frame of ("activities")
    summary*: string ## one line
    readsSelection*: bool ## whether it is made from the selection of the subject
    tables*: seq[string] ## the tables it reads
    make*: MakeCalendar

  CalendarBackground* = object ## the days drawn under every frame
    summary*: string ## one line
    tables*: seq[string] ## the tables it reads
    make*: proc(st: Session): seq[UnixTime] {.nimcall, raises: [StoreError].}
      ## the instants whose days are drawn, for the user of the session

const
  calendarFramePoint* = ExtensionPoint[CalendarFrame](name: "calendar/frames")
    ## The frames the packages that manage a subject offer the calendar.
  calendarBackgroundPoint* =
    ExtensionPoint[CalendarBackground](name: "calendar/background")
    ## The days drawn under every frame (the activities).

func framesOf*(all: seq[CalendarFrame], subject: string): seq[CalendarFrame] =
  ## The frames of a subject (at most one, in the real registry).
  for f in all:
    if f.subject == subject:
      result.add f
