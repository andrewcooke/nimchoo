## The frames of a calendar: what the packages that manage a subject contribute for the calendar to draw.  The calendar is a
## view; a frame says which days to mark, made by the package that knows the subject, so the calendar needs nothing of the
## packages above it.  This is an extension point of this package (`calendarFramePoint`).
##
## A subject has at most one calendar frame (a test checks it): a day is marked or not, so two frames would have nothing to
## tell them apart.  A frame says which subject it is of, what it is, whether it reads the selection of the subject, which
## tables it reads (what it depends on; a test checks that the declaration holds every table the frame reads), and how to
## make it.  A frame that fails raises `StoreError` with what to say.
##
## Under every frame the calendar draws *the days* (`calendarDaysPoint`), whatever the subject: the days that had an
## activity, contributed by the package that has them, so that the marked days are seen among the days you rode.  The
## calendar does not depend on that package; the contribution is the link.
##
## Behind the days, a calendar may be *shaded* (`--shade NAME`, `calendarShadePoint`): a value over time as the background
## colour, from the theme's `NAME-lo` to `NAME-hi` (`core/theme`).  A shade is given intervals of time and gives a value
## for each: a curve's value at the end of the interval (fitness: three a day, a cell being three columns), or a total
## over it (impulse: one a day).

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

  CalendarDays* = object ## the days drawn under every frame
    summary*: string ## one line
    tables*: seq[string] ## the tables it reads
    make*: proc(st: Session): seq[UnixTime] {.nimcall, raises: [StoreError].}
      ## the instants whose days are drawn, for the user of the session

  ShadeKind* = enum
    skCurve ## a value at an instant: the end of each third of a day is shown
    skDaily ## a total over a span of time: each day's is shown

  Interval* = tuple[t0, t1: int64] ## from `t0` to `t1` (Unix seconds)

  ShadeData* = object ## What a shade made.
    values*: seq[float] ## one for each interval asked for, in the same order
    label*: string ## what the values are, for the legend: "fitness of default"
    warnings*: seq[Line]
      ## said to the user ("no model is selected"); then there are no values

  CalendarShade* = object
    name*: string
      ## what the user types after `--shade` ("fitness"), and the style its colours are of (`fitness-lo` to `fitness-hi`)
    summary*: string ## one line
    kind*: ShadeKind
    tables*: seq[string] ## the tables it reads
    make*: proc(st: Session, intervals: seq[Interval]): ShadeData {.
      nimcall, raises: [StoreError]
    .}
      ## the values for the intervals (in time order): for a curve its value at the end of each, for a total the sum
      ## over each; it may work out first what it needs (the impulses), in a transaction of its own

const
  calendarFramePoint* = ExtensionPoint[CalendarFrame](name: "calendar/frames")
    ## The frames the packages that manage a subject offer the calendar.
  calendarDaysPoint* = ExtensionPoint[CalendarDays](name: "calendar/days")
    ## The days drawn under every frame (the activities).
  calendarShadePoint* = ExtensionPoint[CalendarShade](name: "calendar/shades")
    ## The values a calendar may be shaded by (`--shade`).

func framesOf*(all: seq[CalendarFrame], subject: string): seq[CalendarFrame] =
  ## The frames of a subject (at most one, in the real registry).
  for f in all:
    if f.subject == subject:
      result.add f
