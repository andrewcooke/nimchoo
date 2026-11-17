## The frame of the activities on a calendar (`calendar/frames`): the days of the selected activities, and the line that sums
## them up, as `nch activities` ends its listing.

import std/[options, sequtils]
import ../../core/[errors, extension]
import ../calendar/frames
import ../ui/vocabulary
import ../user/session
import ./[rows, table]

{.push raises: [].}

proc makeCalendar(st: Session): CalendarData {.raises: [StoreError].} =
  let rows = selectionRows(st, false)
  CalendarData(
    marks: rows.mapIt(it.startT), summary: footerLine(rows, none(int), selectedColour)
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
