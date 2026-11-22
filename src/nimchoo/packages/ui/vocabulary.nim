## The words commands use to say what happened, in the log and on the screen,
## and the style each one has everywhere.  One table, so that "failed" is
## bad and "advisory" a warning wherever they appear.
##
## An event is an enum value, so a command cannot log a word that is not here,
## and the `case` in `style` must cover every value, so a word without a style does
## not compile.  A new event is one new value here (and its style).

import std/options
import ../../core/logfile
export logfile.parseEvent
export logfile.LogEvent
import ./[style, units]

{.push raises: [].}

const selectedStyle* = styleName"select"
  ## the style of what is in the selection (a row of the table, a day of the calendar, a ride of the climbs), used for
  ## nothing else

func countSpan*(n: int, selected, marks: bool): Span =
  ## How many a list holds, for its last line ("done: 11 of 1,113 activities"): in the selection's style when what is
  ## listed is the selection (and, with `marks`, where there is no colour, in brackets, as a selected day or row is).
  let text = count(n)
  if not selected:
    span(text)
  elif marks:
    span("[" & text & "]", selectedStyle)
  else:
    span(text, selectedStyle)

func listDone*(
    n: int,
    total: Option[int],
    one, many: string,
    selected = false,
    marks = false,
    extra = "",
): Line =
  ## The last line of a list, after "done: " (`g.done`): "11 of 1,113 activities" (how many, of how many there are to
  ## choose from, if known), or "3 users"; the noun agrees with the last number said.  `extra` follows as it is (", 1,057.9km").
  ## One helper for every list, so that every list ends alike.
  let last = if total.isSome: total.get else: n
  let tail =
    if total.isSome:
      " of " & counted(last, one, many)
    else:
      " " & (if last == 1: one else: many)
  @[countSpan(n, selected, marks), span(tail & extra)]

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

func span*(text: string, e: LogEvent): Span =
  ## `text` in the style of the event.
  span(text, style(e))
