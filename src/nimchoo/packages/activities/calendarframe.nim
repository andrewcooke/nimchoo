## The frame of the activities on a calendar (`calendar/frames`): the days of the selected activities, and the line that sums
## them up, as `nch activities` ends its listing; and the background of every calendar (`calendar/background`): the days any
## of the user's activities started on.

import std/[options, sequtils]
import ../../core/[errors, extension]
import ../db/statement
import ../fit/time
import ../calendar/frames
import ../ui/vocabulary
import ../user/session
import ./[rows, table]

{.push raises: [].}

proc makeCalendar(st: Session): CalendarData {.raises: [StoreError].} =
  let rows = selectionRows(st, false)
  CalendarData(
    marks: rows.mapIt(it.startT),
    summary:
      footerLine(rows, some(activityCount(st)), selectedStyle, isSelection = true),
  )

proc activityStarts(st: Session): seq[UnixTime] {.raises: [StoreError].} =
  ## When each of the user's activities started.
  for t in st.db.query(
    int64,
    """select cast(a.start_t as integer) from activity a join file f on f.id = a.file_id
      where f.user_id = :userId order by a.start_t""",
    userId = st.userId,
  ):
    result.add UnixTime(t)

proc background*(): Contribution =
  ## The days of all the user's activities, offered to the calendar to draw under every frame.
  contribute(
    calendarBackgroundPoint,
    CalendarBackground(
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
      tables: @["activity", "file", "selection", "user"],
      make: makeCalendar,
    ),
  )
