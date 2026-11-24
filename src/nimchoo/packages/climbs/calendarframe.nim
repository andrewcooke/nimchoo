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
import ../ui/units

{.push raises: [].}

proc makeCalendar(st: Session): CalendarData {.raises: [StoreError].} =
  let climbs = chosenClimbs(st)
  for t in st.db.query(
    int64,
    """select cast(e.start_epoch as integer) from effort e
        join activity a on a.id = e.activity_id join file f on f.id = a.file_id
        where f.user_id = :userId and e.sector_id in (select value from json_each(:climbs))
        order by e.start_epoch""",
    userId = st.userId,
    climbs = jsonList(climbs),
  ):
    result.marks.add UnixTime(t)
  let attempts = counted(result.marks.len, "attempt", "attempts")
  let selected = counted(climbs.len, "selected climb", "selected climbs")
  result.summary = doneLine(plain(fmt"{attempts} on the {selected}"))

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
