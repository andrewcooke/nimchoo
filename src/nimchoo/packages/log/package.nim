## Reading the log: `nch log`.
##
## The log is a plain text file (where it goes is `NCH_LOG`, else the state directory) with a line for each thing a command
## did: the time, the level, the command, an event word (`start`, `imported`, `failed`, `advisory`, `saved`, ...) and a text.
## `nch log` shows it filtered by command and event, with the events in the colours they have on the screen; `--last` shows the
## latest run.  The words and their colours are in `ui/vocabulary`.

import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "ui"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "show the log, filtered, with the events coloured",
      run: command.run,
    )
  ],
)
