## The frame of the activities on a calendar (`calendar/frames`): the days of the selected activities, and the line that sums
## them up, as `nch activities` ends its listing; the days drawn under every calendar (`calendar/days`): the days any of
## the user's activities started on; and a shade (`calendar/shades`): the impulse of the selected activities each day, by
## the first selected model (as on the plot: `plotframes.selectedImpulses`).

import std/[options, sequtils, strformat]
import ../../core/[errors, extension]
import ../db/statement
import ../fit/time
import ../calendar/frames
import ../user/session
import ./[plotframes, rows, table]

{.push raises: [].}

proc makeCalendar(st: Session): CalendarData {.raises: [StoreError].} =
  let rows = selectionRows(st, false)
  CalendarData(
    marks: rows.mapIt(it.startT),
    summary: footerLine(rows, some(activityCount(st)), isSelection = true),
  )

proc activityStarts(st: Session): seq[UnixTime] {.raises: [StoreError].} =
  ## When each of the user's activities started.
  for t in st.db.query(
    int64,
    """select cast(a.start_epoch as integer) from activity a join file f on f.id = a.file_id
      where f.user_id = :userId order by a.start_epoch""",
    userId = st.userId,
  ):
    result.add UnixTime(t)

proc days*(): Contribution =
  ## The days of all the user's activities, offered to the calendar to draw under every frame.
  contribute(
    calendarDaysPoint,
    CalendarDays(
      summary: "the days any of your activities started on",
      tables: @["activity", "file"],
      make: activityStarts,
    ),
  )

proc contribution*(): Contribution =
  ## The frame of the activities, offered to the calendar.
  contribute(
    calendarFramePoint,
    CalendarFrame(
      subject: "activities",
      summary: "a day is marked when a selected activity started on it",
      readsSelection: true,
      tables: @["activity", "file", "activity_selection"],
      make: makeCalendar,
    ),
  )

proc makeImpulseShade(
    st: Session, intervals: seq[Interval]
): ShadeData {.nimcall, raises: [StoreError].} =
  ## The impulse of the selected activities in each interval (the intervals are in time order, the impulses too).
  let got = selectedImpulses(st)
  if got.model.isNone:
    result.warnings = got.warnings
    return
  result.label = fmt"impulse of the selected activities, by {got.model.get.name}"
  result.values = newSeq[float](intervals.len)
  var k = 0
  for (t, v) in got.lumps:
    while k < intervals.len and intervals[k].t1 <= t:
      inc k
    if k < intervals.len and t >= intervals[k].t0:
      result.values[k] += v

proc shade*(): Contribution =
  ## The impulse of the selected activities, offered to the calendar as a shade.
  contribute(
    calendarShadePoint,
    CalendarShade(
      name: "impulse",
      summary:
        "the impulse of the selected activities each day, by the first selected model",
      kind: skDaily,
      tables: impulseTables,
      make: makeImpulseShade,
    ),
  )
