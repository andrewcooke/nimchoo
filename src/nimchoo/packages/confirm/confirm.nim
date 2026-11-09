## Deleting with a pause: the countdown that gives time to press Ctrl-C, and the line that says what was deleted.
## Nothing is deleted without `--force`, and on a terminal there are then a few seconds in which to cancel.
## The commands that delete (`activities`, `climbs`, `users`, `landmarks`, `cache`, `db`) use these, so that the
## words and the pause are the same for all.

import std/os
import ../../core/globals
import ../ui/live
import ../ui/style

{.push raises: [].}

const waitSeconds* = 5 ## the pause before a delete

func countdownLine*(what: string, seconds: int): Line =
  ## "deleting WHAT in 5 s ... (Ctrl-C to cancel)", in red.
  @[
    span("deleting " & what & " in ", red),
    span($seconds, red, bold = true),
    span(" s ... (Ctrl-C to cancel)", red),
  ]

proc countdown*(
    l: Live, what: string, seconds: int, wait: proc(ms: int) {.closure, raises: [].}
) =
  ## Show the line once a second, from `seconds` down to 1, then take it away.
  for s in countdown(seconds, 1):
    l.show @[countdownLine(what, s)]
    wait 1000
  l.finish()

proc sayDeleted*(text: string) =
  ## The line that says what was deleted ("done: deleted ..."), in red on a terminal, so that it stands out.
  stdout.say render(@[span("done: " & text, red)], canColourStdout()) & "\n"

proc sleepMs*(ms: int) {.raises: [].} =
  ## Wait for `ms` milliseconds.
  try:
    sleep(ms)
  except OSError:
    discard
