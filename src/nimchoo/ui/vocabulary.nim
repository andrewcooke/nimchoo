## The words commands use to say what happened, in the log and on the screen,
## and the look (colour) each one has everywhere.  One table, so that "failed" is
## red and "advisory" is yellow wherever they appear.
##
## An event is an enum value, so a command cannot log a word that is not here,
## and the `case` in `look` must cover every value, so a word without a colour does
## not compile.  A new event is one new value here (and its look).

import std/options
import ../core/logfile
export logfile.LogEvent
import ./style

{.push raises: [].}

func look*(e: LogEvent): Look =
  ## How an event is shown: imported green, failed red and bold, advisory yellow,
  ## duplicate and unchanged dim (grey), the bookkeeping words dim.
  case e
  of leImported, leSaved, leDownloaded:
    Look(colour: green)
  of leFailed:
    Look(colour: red, bold: true)
  of leAdvisory:
    Look(colour: yellow)
  of leDuplicate, leUnchanged:
    Look(colour: grey)
  of leDeleted:
    Look(colour: red)
  of leDenied:
    Look(colour: red)
  of leStart, leRun, leExit, leDone, leNote, leServed:
    Look(colour: grey)

func parseEvent*(s: string): Option[LogEvent] =
  ## The event whose word is `s`.
  for e in LogEvent:
    if $e == s:
      return some(e)
  none(LogEvent)

func span*(text: string, e: LogEvent): Span =
  ## `text` in the look of the event.
  Span(text: text, look: look(e))
