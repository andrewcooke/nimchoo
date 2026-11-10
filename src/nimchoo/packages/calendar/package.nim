## The activities of the selection on a calendar.
##
## `nch calendar` draws the selection: a row for each month that has an activity, the days in columns by weekday (weeks start
## on Monday).  `--all` draws every activity with those in the selection in blue; `-v` shows every month from the first to the
## last.  It takes no criteria, like `climbs` and `map`: to see a calendar of some activities, select them first
## (`nch activities CRITERIA --select`).  Without colour (a pipe, `NO_COLOR`) the cells are wider and carry marks, so nothing is
## lost.  The rows come from `activities`.

import ../../core/manifest
import ./command

const package* = Package(
  depends: @["activities", "args", "fit", "ui", "user"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the activities of the selection on a calendar",
      run: command.run,
      options: command.options,
    )
  ],
)
