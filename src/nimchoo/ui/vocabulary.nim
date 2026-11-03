## The words commands use to say what happened, in the log and on the screen,
## and the look (colour) each one has everywhere.  One table, so that "failed" is
## red and "advisory" is yellow wherever they appear.
##
## An event is an enum value, so a command cannot log a word that is not here,
## and the `case` in `look` must cover every value, so a word without a colour does
## not compile.  A new event is one new value here (and its look).

import std/options
import ./style

{.push raises: [].}

type
  LogEvent* = enum
    leStart = "start"            ## a command begins its work (the number of things)
    leRun = "run"                ## the dispatcher: a command was run (with its arguments)
    leExit = "exit"              ## ... and ended (with its exit status)
    leImported = "imported"      ## something was made (a file's activities were stored)
    leDuplicate = "duplicate"    ## the same content was imported before
    leUnchanged = "unchanged"    ## nothing to do: as last time
    leFailed = "failed"          ## it did not work
    leAdvisory = "advisory"      ## something noticed in what was processed anyway
    leNote = "note"              ## something about the run itself
    leDone = "done"              ## a command ends its work (the totals)
    leDeleted = "deleted"        ## data was removed
    leSaved = "saved"            ## something was kept (the selection)

func look*(e: LogEvent): Look =
  ## How an event is shown: imported green, failed red and bold, advisory yellow,
  ## duplicate and unchanged dim (grey), the bookkeeping words dim.
  case e
  of leImported, leSaved: Look(fg: cGreen)
  of leFailed: Look(fg: cRed, bold: true)
  of leAdvisory: Look(fg: cYellow)
  of leDuplicate, leUnchanged: Look(dim: true)
  of leDeleted: Look(fg: cRed)
  of leStart, leRun, leExit, leDone, leNote: Look(dim: true)

func parseEvent*(s: string): Option[LogEvent] =
  ## The event whose word is `s`.
  for e in LogEvent:
    if $e == s: return some(e)
  none(LogEvent)

func span*(text: string, e: LogEvent): Span =
  ## `text` in the look of the event.
  Span(text: text, look: look(e))
