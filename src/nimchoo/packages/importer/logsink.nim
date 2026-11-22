## The log of `nch import`: what changed or went wrong, in full.  Each line is
## one of the shared events (packages/ui/vocabulary.nim), so `nch log import advisory` finds
## one kind: `start`, `imported`, `duplicate`, `failed`, `advisory` (something
## noticed in a file that was imported anyway), `note` (about the run), `done`.
## Files that were unchanged or known failures are not logged one by one (a
## re-import of thousands would fill the log); the `done` line counts them.  `-q`
## affects the screen only; the log is always complete.

import ../../core/[line, logfile]
import ./events
import ./failure
import ./cmdname
import ./sinks
import ../ui/units

{.push raises: [].}

type Entry* = object
  level*: Level
  event*: LogEvent
  text*: string

func entry(level: Level, event: LogEvent, text: string): Entry =
  Entry(level: level, event: event, text: text)

func logEntries*(ev: ImportEvent): seq[Entry] =
  ## The log lines for an event.
  case ev.kind
  of evStart:
    result.add entry(lvInfo, leStart, counted(ev.total, "file", "files"))
  of evFileStart:
    discard
  of evFileDone:
    case ev.outcome
    of oImported:
      result.add entry(
        lvInfo,
        leImported,
        ev.path & "  " & counted(ev.counts.activities, "activity", "activities") & ", " &
          counted(ev.counts.segments, "segment", "segments") & ", " &
          counted(ev.counts.coords, "coordinate", "coordinates") & extrasText(ev.counts),
      )
    of oDuplicate:
      result.add entry(
        lvInfo,
        leDuplicate,
        ev.path & "  " & (
          if ev.sameAs.len > 0: "same content as " & ev.sameAs
          else: "already imported"
        ),
      )
    of oUnchanged, oKnownFailure, oMonitor:
      discard
    of oFailed:
      result.add entry(
        lvError, leFailed, ev.path & "  (" & ev.failure.label & ") " & ev.message
      )
    for w in ev.advisories:
      result.add entry(
        lvWarn, leAdvisory, ev.path & "  offset " & $w.offset & ": " & w.msg
      )
  of evFinish:
    for note in ev.summary.warnings:
      result.add entry(lvWarn, leNote, note)
    result.add entry(lvInfo, leDone, summaryLine(ev.summary).plainText)

proc logSink*(l: Log): Sink =
  ## Write the entries of each event to `l`.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    for e in logEntries(ev):
      l.log(e.level, commandName, e.event, e.text)
