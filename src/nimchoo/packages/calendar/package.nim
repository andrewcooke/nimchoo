## A subject on a calendar: by default the days the selected activities started on.
##
## `nch calendar [SUBJECT]` draws a row for each month that has a marked day, the days in columns by weekday (weeks start on
## Monday).  `--detail N` says which months: those with a marked day (1), every month from the first to the last (2), or to this
## month (3); the default depends on what is shown.  `--shade NAME` colours the background by a value over time
## (`calendar/shades`: fitness, fatigue, form, impulse), from the theme's `NAME-lo` to `NAME-hi`.  It takes no criteria, like `climbs` and `map`: to see a
## calendar of some activities, select them first (`nch activities CRITERIA --select`).  Without colour (a pipe, `NO_COLOR`)
## the cells are wider and carry marks, so nothing is lost.
##
## The calendar is a view and knows no subject: it defines the point `calendar/frames` (`frames.nim`), to which the package
## that manages a subject contributes the frame of it (`activities`: the days of the selected activities, and the line that
## sums them up), and reads the subjects from `subject/subjects`.  A subject has at most one calendar frame.  Under every
## frame it draws the days of `calendar/days` (`activities`: the days any activity started on), so that the marked days
## are seen among the days you rode.

import ../../core/[extension, manifest]
import ./[command, frames]

const package* = Package(
  depends: @["args", "fit", "subject", "ui", "user"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "a subject (by default the selected activities) on a calendar",
      run: command.run,
      options: command.options,
    )
  ],
  defines: @[
    PointDecl(
      name: calendarFramePoint.name,
      summary:
        "the frame of a subject on a calendar, contributed by the package that manages it: the instants whose days are marked, and a last line",
    ),
    PointDecl(
      name: calendarDaysPoint.name,
      summary:
        "the days drawn under every frame, whatever the subject: the instants whose days are drawn plain, not dimmed (the activities)",
    ),
    PointDecl(
      name: calendarShadePoint.name,
      summary:
        "the values a calendar may be shaded by (`--shade`): a value for each interval of time, a curve's or a total",
    ),
  ],
)
