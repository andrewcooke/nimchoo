## The words commands use to say what happened, in the log and on the screen,
## and the style each one has everywhere.  One table, so that "failed" is
## bad and "advisory" a warning wherever they appear.
##
## An event is an enum value, so a command cannot log a word that is not here,
## and the `case` in `style` must cover every value, so a word without a style does
## not compile.  A new event is one new value here (and its style).

import std/options
import ../../core/logfile
export logfile.LogEvent
import ./style

{.push raises: [].}

const selectedStyle* = styleName"select"
  ## the style of what is in the selection (a row of the table, a day of the calendar, a ride of the climbs), used for
  ## nothing else

func style*(e: LogEvent): StyleName =
  ## How an event is shown: imported good, failed and deleted bad, advisory a warning, duplicate, unchanged and the
  ## bookkeeping words hidden.
  case e
  of leImported, leSaved, leDownloaded:
    styleName"good"
  of leFailed, leDeleted, leDenied:
    styleName"bad"
  of leAdvisory:
    styleName"warn"
  of leDuplicate, leUnchanged, leStart, leRun, leExit, leDone, leNote, leServed:
    styleName"hide"

func parseEvent*(s: string): Option[LogEvent] =
  ## The event whose word is `s`.
  for e in LogEvent:
    if $e == s:
      return some(e)
  none(LogEvent)

func span*(text: string, e: LogEvent): Span =
  ## `text` in the style of the event.
  span(text, style(e))
