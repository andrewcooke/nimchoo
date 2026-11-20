## The frame of the climbs on a calendar (`calendar/frames`): the days you went up a climb of the climbs selection, and a line
## that sums them up.

import std/strformat
import ../../core/[errors, extension, globals]
import ../calendar/frames
import ../db/statement
import ../fit/time
import ../ui/style
import ../user/session
import ./chosen

{.push raises: [].}

proc makeCalendar(st: Session): CalendarData {.raises: [StoreError].} =
  let climbs = chosenClimbs(st)
  for t in st.db.query(
    int64,
    """select cast(e.start_t as integer) from effort e
        join activity a on a.id = e.activity_id join file f on f.id = a.file_id
        where f.user_id = :userId and e.sector_id in (select value from json_each(:climbs))
        order by e.start_t""",
    userId = st.userId,
    climbs = jsonList(climbs),
  ):
    result.marks.add UnixTime(t)
  let attempts = if result.marks.len == 1: "attempt" else: "attempts"
  let noun = if climbs.len == 1: "climb" else: "climbs"
  result.summary = doneLine(
    plain(fmt"{result.marks.len} {attempts} on the {climbs.len} selected {noun}")
  )

proc contribution*(): Contribution =
  ## The frame of the climbs, offered to the calendar.
  contribute(
    calendarFramePoint,
    CalendarFrame(
      subject: "climbs",
      summary: "a day is marked when you went up a selected climb",
      readsSelection: true,
      tables: @["activity", "climb_selection", "effort", "file", "sector"],
      make: makeCalendar,
    ),
  )
