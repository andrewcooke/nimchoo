## What the server may run for the fitness and fatigue page: `nch ff --worker` with these options and no others
## (`web/request.nim`).

import ../web/request

{.push raises: [].}

func ffPage*(command: string): WebPage =
  ## The page of the command `command` (its name is its own: `command.commandName`).
  WebPage(
    command: command,
    options: @[
      PageOption(name: "check", valid: hexHash),
      PageOption(name: "model", valid: anyWord),
      PageOption(name: "from", valid: day),
      PageOption(name: "to", valid: day),
      PageOption(name: "fitness-scale", valid: plainNumber),
      PageOption(name: "fatigue-scale", valid: plainNumber),
    ],
    flags: @["hourly", "utc"],
    pin: "check",
  )
