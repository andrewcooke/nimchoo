## Deleting with a pause: the countdown that gives time to press Ctrl-C, and the line that says what was deleted.
## Nothing is deleted without `--force`, and on a terminal there are then a few seconds in which to cancel.
## The commands that delete (`activities`, `climbs`, `users`, `landmarks`, `cache`, `db`) use these, so that the
## words and the pause are the same for all.

import std/os
import ../../core/globals
import ../ui/live
import ../ui/style
import ../util/args/args

{.push raises: [].}

const waitSeconds* = 5 ## the pause before a delete

type Force* = enum
  ## What `-f` has said: the one option of every command that deletes, written once (`forceOption`).
  fNo ## not given: only say what would be deleted
  fYes ## `-f`: delete, after the pause (on a terminal)
  fNow ## `-f -f`: delete without the pause

const forceHelp* =
  "really do it (nothing is deleted without it).  On a terminal there are then " &
  $waitSeconds &
  " seconds in which to press Ctrl-C; given twice (-f -f) there is no pause"

template forceOption*(P: typedesc, field: untyped, indent: int = 0): Opt[P] =
  ## `-f` / `--force` as an option of a command whose `P` holds a `Force` in `field`: the first time is `fYes`, the second
  ## `fNow`; `indent` is the option's `level` (how far in the usage it stands).
  custom(
    P,
    ["-f", "--force"],
    false,
    "",
    forceHelp,
    level = indent,
    body = (p.field = (if p.field == fNo: fYes else: fNow); fine),
  )

template forceOptionIn*(P: typedesc, group, field: untyped, indent: int = 0): Opt[P] =
  ## The same, for a `Force` that is `field` of the part `group` of `P` (`p.group.field`).
  custom(
    P,
    ["-f", "--force"],
    false,
    "",
    forceHelp,
    level = indent,
    body = (p.group.field = (if p.group.field == fNo: fYes else: fNow); fine),
  )

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

proc pause*(what: string, force: Force) =
  ## The countdown before deleting `what`, on a terminal, unless `-f` was given twice.
  if force != fNow and canLive():
    countdown(newTerminalLive(), what, waitSeconds, sleepMs)
