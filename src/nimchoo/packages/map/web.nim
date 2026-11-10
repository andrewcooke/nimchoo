## What the server may run for the map page: `nch map --worker` with these options and no others (`web/request.nim`).

import ../selection/bits
import ../web/request

{.push raises: [].}

func bitsValue(value: string): bool =
  ## A list of activities: it may have two dashes in a row, and be long.
  value.len > 0 and isBitsString(value)

func mapPage*(command: string): WebPage =
  ## The page of the command `command` (the map's name is its own: `command.commandName`).
  WebPage(
    command: command,
    options: @[
      PageOption(name: "bits", valid: bitsValue),
      PageOption(name: "check", valid: hexHash),
    ],
    pin: "bits",
  )
